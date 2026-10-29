import Foundation

/// Turns Cursor's agent hook events (https://cursor.com/docs/agent/hooks) into tickets.
/// One ticket per Cursor conversation, found again by its conversation id.
///
///   beforeSubmitPrompt  Nina sent a message: working, titled with what she asked
///   afterAgentResponse  keep the agent's reply as the last message
///   preToolUse          the agent is asking Nina a question: needs_you
///   postToolUse         she answered it: working
///   stop                completed: needs_you if it ended on a question, otherwise done.
///                       aborted: done. error: blocked.
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

        return try store.update { tickets, now in
            func newTicket(title: String) -> Int {
                var ticket = Ticket(tool: .cursor, source: .automatic, title: title,
                                    thread: folder.flatMap(QuickAdd.threadName(forLink:)) ?? "",
                                    deepLink: folder ?? "", state: .working, stateSince: now)
                ticket.externalId = key
                tickets.append(ticket)
                return tickets.count - 1
            }
            /// The ticket for this conversation, made now if it started before the hooks were installed.
            func ticketIndex() -> Int {
                if let i = tickets.firstIndex(where: { $0.externalId == key }) { return i }
                return newTicket(title: transcript?.lastQuestion().flatMap(title(from:)) ?? fallbackTitle)
            }
            let known = tickets.contains { $0.externalId == key }

            switch event {
            case "beforeSubmitPrompt":
                let prompt = payload["prompt"] as? String ?? ""
                guard known else {
                    let asked = title(from: prompt) ?? transcript?.lastQuestion().flatMap(title(from:)) ?? fallbackTitle
                    return tickets[newTicket(title: asked)]
                }
                let i = ticketIndex()
                // A message that's only a pasted page element keeps the title it had.
                if let asked = title(from: prompt) { tickets[i].title = asked }
                tickets[i].questionType = .none
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "afterAgentResponse":
                guard let text = payload["text"] as? String, !text.isEmpty else { return nil }
                let i = ticketIndex()
                tickets[i].lastMessage = text
                return tickets[i]

            case "preToolUse":
                let i = ticketIndex()
                guard isQuestion(payload["tool_name"]) else {
                    // Using any other tool means it's busy, whatever it was before.
                    guard tickets[i].state != .working else { return known ? nil : tickets[i] }
                    tickets[i].questionType = .none
                    try tickets[i].apply(.stillRunning, now: now)
                    return tickets[i]
                }
                let input = payload["tool_input"] as? [String: Any] ?? [:]
                if let question = questionText(input) { tickets[i].lastMessage = question }
                let options = optionLabels(input)
                tickets[i].questionType = options.isEmpty ? .free : .choice(options)
                try tickets[i].apply(.needsYou, now: now)
                return tickets[i]

            case "postToolUse":
                let i = ticketIndex()
                guard isQuestion(payload["tool_name"]), tickets[i].state == .needsYou else { return known ? nil : tickets[i] }
                tickets[i].questionType = .none
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "stop":
                let i = ticketIndex()
                if tickets[i].lastMessage.isEmpty, let reply = transcript?.lastReply() { tickets[i].lastMessage = reply }
                switch payload["status"] as? String {
                case "error":
                    try tickets[i].apply(.blocked, now: now)
                case "aborted":
                    try tickets[i].apply(.done, now: now)
                default:
                    // DECISIONS.md: ending on a question means it needs Nina; otherwise it's done.
                    let question = QuestionDetector.detect(tickets[i].lastMessage)
                    tickets[i].questionType = question
                    try tickets[i].apply(question == .none ? .done : .needsYou, now: now)
                }
                return tickets[i]

            case "sessionEnd":
                guard known, let i = tickets.firstIndex(where: { $0.externalId == key }), tickets[i].state == .working else { return nil }
                try tickets[i].apply(.done, now: now)
                return tickets[i]

            default:
                return nil
            }
        }
    }

    static let fallbackTitle = "Cursor agent"

    /// Lines Cursor adds when Nina points at something on a page. Not her words.
    static let pastedElementPrefixes = ["DOM Path:", "Position:", "HTML Element:", "React Component:"]

    /// A row-length title from what Nina asked, or nil if the message has none of her own words.
    /// A bare link becomes its readable last part.
    static func title(from prompt: String) -> String? {
        let line = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !pastedElementPrefixes.contains(where: $0.hasPrefix) }
        guard let line else { return nil }
        if let readable = readableLink(line) { return readable }
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }

    /// "https://linear.app/x/project/predictive-ordering-ai-rules-and-ui-sweep-8c6" → "Predictive ordering ai rules and ui sweep".
    static func readableLink(_ text: String) -> String? {
        guard !text.contains(" "), let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
        var words = url.lastPathComponent.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        // Drop a trailing id like "8c6" or "a1b2c3".
        if let last = words.last, words.count > 1, last.count <= 12, last.contains(where: \.isNumber) { words.removeLast() }
        let phrase = words.joined(separator: " ")
        guard !phrase.isEmpty else { return url.host }
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    /// Cursor's tool for the multiple-choice Questions prompt. Its exact name isn't documented,
    /// so match anything that sounds like asking.
    static func isQuestion(_ toolName: Any?) -> Bool {
        guard let name = (toolName as? String)?.lowercased() else { return false }
        // Not just "ask": the subagent tool is called Task.
        return name.contains("question") || name.hasPrefix("ask")
    }

    static func questionText(_ input: [String: Any]) -> String? {
        if let q = input["question"] as? String { return q }
        if let questions = input["questions"] as? [[String: Any]], let q = questions.first?["question"] as? String { return q }
        return input["title"] as? String
    }

    static func optionLabels(_ input: [String: Any]) -> [String] {
        let source = input["options"] ?? (input["questions"] as? [[String: Any]])?.first?["options"]
        guard let options = source as? [Any] else { return [] }
        return options.compactMap { option in
            if let s = option as? String { return s }
            if let d = option as? [String: Any] { return (d["label"] ?? d["text"] ?? d["title"]) as? String }
            return nil
        }
    }
}

/// Reads the transcript file Cursor names in every hook event (`transcript_path`).
/// Only the tail is read, and only Nina's last question and the agent's last reply are taken.
struct CursorTranscript {
    let path: String
    private static let tailBytes = 512 * 1024

    /// Nina's last message with words of her own in it, from its <user_query> block.
    func lastQuestion() -> String? {
        for message in messages().reversed() where message.role == "user" {
            if let query = Self.userQuery(in: message.text), CursorFeed.title(from: query) != nil { return query }
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
        let opener = last.lowercased()
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
