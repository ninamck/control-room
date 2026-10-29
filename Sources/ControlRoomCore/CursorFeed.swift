import Foundation

/// Turns Cursor's agent hook events (https://cursor.com/docs/agent/hooks) into tickets.
/// One ticket per Cursor conversation, found again by its conversation id.
///
///   beforeSubmitPrompt  Nina sent a message: working, titled with what she asked
///   afterAgentResponse  keep the agent's reply as the last message
///   preToolUse          the agent is asking Nina a question: needs_you
///   postToolUse         she answered it: working
///   stop                completed: needs_you, it's Nina's turn. aborted (she stopped it): done. error: blocked.
///   sessionEnd          conversation closed while working: done
///
/// A conversation that was already running before the hooks went in gets its ticket
/// on its first event of any kind, titled from the transcript Cursor points to.
public enum CursorFeed {
    public static let events = ["beforeSubmitPrompt", "afterAgentResponse", "preToolUse", "postToolUse", "stop", "sessionEnd"]

    /// Applies one hook event. Returns the ticket it touched, if any.
    @discardableResult
    public static func handle(_ payload: [String: Any], store: TicketStore) throws -> Ticket? {
        guard let event = payload["hook_event_name"] as? String,
              let conversation = payload["conversation_id"] as? String, !conversation.isEmpty else { return nil }
        let key = "cursor:\(conversation)"
        let folder = (payload["workspace_roots"] as? [String])?.first
        let transcript = (payload["transcript_path"] as? String).map(CursorTranscript.init(path:))
        // Looked up before taking the store's lock, so a slow read never holds up other events.
        // Cursor names a chat after its first reply, so keep asking until it has one.
        let cursorName = CursorChatNames.name(for: conversation)
        let chatName = cursorName ?? transcript?.firstQuestion().flatMap(FeedText.title(from:))

        return try store.update { tickets, now in
            func newTicket(title: String) -> Int {
                var ticket = Ticket(tool: .cursor, source: .automatic, title: title,
                                    thread: folder.flatMap(QuickAdd.threadName(forLink:)) ?? "",
                                    deepLink: folder ?? "", state: .working, stateSince: now)
                ticket.externalId = key
                ticket.chatName = chatName
                tickets.append(ticket)
                return tickets.count - 1
            }
            // Cursor's own name always wins; the first-message name only fills a gap, so a busy moment can't swap it back.
            if let i = tickets.firstIndex(where: { $0.externalId == key }) {
                if let cursorName, tickets[i].chatName != cursorName {
                    tickets[i].chatName = cursorName
                } else if tickets[i].chatName == nil, let chatName {
                    tickets[i].chatName = chatName
                }
            }
            /// The ticket for this conversation, made now if it started before the hooks were installed.
            func ticketIndex() -> Int {
                if let i = tickets.firstIndex(where: { $0.externalId == key }) { return i }
                return newTicket(title: transcript?.lastQuestion().flatMap(FeedText.title(from:)) ?? fallbackTitle)
            }
            let known = tickets.contains { $0.externalId == key }
            func doing(_ i: Int, _ what: String?) {
                tickets[i].activity = what
                tickets[i].activityAt = what == nil ? nil : now
            }

            switch event {
            case "beforeSubmitPrompt":
                let prompt = payload["prompt"] as? String ?? ""
                guard known else {
                    // Nina pasting a handed-off brief: this chat takes over the hand-off ticket.
                    if let i = tickets.firstIndex(where: { HandOff.matchesBrief($0, prompt: prompt, now: now) }) {
                        tickets[i].externalId = key
                        tickets[i].source = .automatic
                        tickets[i].chatName = chatName ?? tickets[i].chatName
                        if let folder { tickets[i].deepLink = folder }
                        doing(i, "Reading your message")
                        return tickets[i]
                    }
                    let asked = FeedText.title(from: prompt) ?? transcript?.lastQuestion().flatMap(FeedText.title(from:)) ?? fallbackTitle
                    let i = newTicket(title: asked)
                    doing(i, "Reading your message")
                    return tickets[i]
                }
                let i = ticketIndex()
                // A message that's only a pasted page element keeps the title it had.
                if let asked = FeedText.title(from: prompt) { tickets[i].title = asked }
                tickets[i].questionType = .none
                doing(i, "Reading your message")
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "afterAgentResponse":
                guard let text = payload["text"] as? String, !text.isEmpty else { return nil }
                let i = ticketIndex()
                tickets[i].lastMessage = text
                doing(i, "Finishing its reply")
                return tickets[i]

            case "preToolUse":
                let i = ticketIndex()
                let input = payload["tool_input"] as? [String: Any] ?? [:]
                guard FeedText.isQuestion(payload["tool_name"]) else {
                    doing(i, FeedText.activity(tool: payload["tool_name"] as? String ?? "", input: input))
                    // Using any other tool means it's busy, whatever it was before.
                    if tickets[i].state != .working {
                        tickets[i].questionType = .none
                        try tickets[i].apply(.stillRunning, now: now)
                    }
                    return tickets[i]
                }
                doing(i, nil)
                if let question = FeedText.questionText(input) { tickets[i].lastMessage = question }
                let options = FeedText.optionLabels(input)
                tickets[i].questionType = options.isEmpty ? .free : .choice(options)
                try tickets[i].apply(.needsYou, now: now)
                return tickets[i]

            case "postToolUse":
                let i = ticketIndex()
                // Between tools the agent is working out what to do next.
                doing(i, "Thinking")
                guard FeedText.isQuestion(payload["tool_name"]), tickets[i].state == .needsYou else { return tickets[i] }
                tickets[i].questionType = .none
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "stop":
                let i = ticketIndex()
                doing(i, nil)
                // The transcript is complete by now, so it's the surest source of what she last asked.
                if let asked = transcript?.lastQuestion().flatMap(FeedText.title(from:)) { tickets[i].title = asked }
                if tickets[i].lastMessage.isEmpty, let reply = transcript?.lastReply() { tickets[i].lastMessage = reply }
                switch payload["status"] as? String {
                case "error":
                    try tickets[i].apply(.blocked, now: now)
                case "aborted":
                    try tickets[i].apply(.done, now: now)
                default:
                    // DECISIONS.md: a finished reply is Nina's turn, so it waits on her until she marks it Done.
                    tickets[i].questionType = QuestionDetector.detect(tickets[i].lastMessage)
                    try tickets[i].apply(.needsYou, now: now)
                }
                return tickets[i]

            case "sessionEnd":
                guard known, let i = tickets.firstIndex(where: { $0.externalId == key }), tickets[i].state == .working else { return nil }
                doing(i, nil)
                try tickets[i].apply(.done, now: now)
                return tickets[i]

            default:
                return nil
            }
        }
    }

    static let fallbackTitle = "Cursor agent"
}

/// Reads the transcript file Cursor names in every hook event (`transcript_path`).
/// Only the tail is read, and only Nina's last question and the agent's last reply are taken.
struct CursorTranscript {
    let path: String
    private static let tailBytes = 512 * 1024

    /// Nina's last message with words of her own in it, from its <user_query> block.
    func lastQuestion() -> String? {
        for message in messages().reversed() where message.role == "user" {
            if let query = Self.userQuery(in: message.text), FeedText.title(from: query) != nil { return query }
        }
        return nil
    }

    /// Nina's first message with words of her own, used to name the chat when Cursor's name can't be read.
    /// Reads from the start of the file, stopping at the first one.
    func firstQuestion() -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.tailBytes), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["role"] as? String == "user",
                  let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let t = part["text"] as? String, let query = Self.userQuery(in: t), FeedText.title(from: query) != nil { return query }
            }
        }
        return nil
    }

    /// The agent's last written reply.
    func lastReply() -> String? {
        messages().reversed().first { $0.role == "assistant" && !$0.text.isEmpty }?.text
    }

    private func messages() -> [(role: String, text: String)] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }  // probably cut mid-line
        return lines.compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let role = object["role"] as? String,
                  let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            return (role, text)
        }
    }

    static func userQuery(in text: String) -> String? {
        guard let open = text.range(of: "<user_query>"),
              let close = text.range(of: "</user_query>", range: open.upperBound..<text.endIndex) else { return nil }
        let query = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }
}

/// Reads whether an agent's last message is asking Nina something.
public enum QuestionDetector {
    public static func detect(_ text: String) -> QuestionType {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return .none }

        // Numbered or lettered options near the end: "1. Menu", "2) Integrations", "A. ..."
        let options = lines.suffix(6).compactMap(option(in:))
        if options.count >= 2 && (last.hasSuffix("?") || option(in: last) != nil) {
            return .choice(options)
        }
        guard last.hasSuffix("?") else { return .none }
        // Judge the question itself, not what comes before it: "Built it. Should I install the hooks?"
        let sentence = last.components(separatedBy: CharacterSet(charactersIn: ".!")).last ?? last
        let opener = sentence.trimmingCharacters(in: .whitespaces).lowercased()
        let yesNo = ["should i", "shall i", "do you", "can i", "is it", "are you", "would you", "want me", "ok to", "okay to"]
        return yesNo.contains(where: opener.hasPrefix) ? .yesNo : .free
    }

    private static func option(in line: String) -> String? {
        let pattern = #"^(?:\d+|[A-Da-d])[.)]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }
}
