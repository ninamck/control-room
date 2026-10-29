import Foundation

/// Turns Claude Code's hook events (https://code.claude.com/docs/en/hooks) into tickets.
/// One ticket per Claude Code session, found again by its session id.
///
///   UserPromptSubmit  Nina sent a message: working, titled with what she asked
///   PreToolUse        shows what it's doing; AskUserQuestion or a plan for approval: needs_you
///   PostToolUse       between tools it's thinking; after her answer: working
///   Notification      asking permission, or idle waiting for her: needs_you
///   Stop              a finished reply is her turn: needs_you, until she marks it Done
///   SessionEnd        the session closed: done
public enum ClaudeCodeFeed {
    public static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    static let fallbackTitle = "Claude Code session"

    /// Notification types that mean Claude Code is waiting on Nina.
    static let waitingNotifications = ["permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog"]

    @discardableResult
    public static func handle(_ payload: [String: Any], store: TicketStore) throws -> Ticket? {
        guard let event = payload["hook_event_name"] as? String,
              let session = payload["session_id"] as? String, !session.isEmpty else { return nil }
        let key = "claude-code:\(session)"
        let cwd = payload["cwd"] as? String
        let env = payload["_env"] as? [String: Any] ?? [:]
        let hostApp = (env["app"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? ((env["entrypoint"] as? String) == "claude-desktop" ? ClaudeCodeFeed.claudeDesktop : nil)
        // The session's name: its custom title when it has one, read before taking the store's lock.
        let sessionName = (payload["session_title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (payload["transcript_path"] as? String).flatMap(ClaudeCodeTranscript.title(at:))

        return try store.update { tickets, now in
            let known = tickets.contains { $0.externalId == key }
            // A session we never saw working doesn't get a ticket just for closing or a passing notice.
            let waitingNotice = (payload["notification_type"] as? String).map(waitingNotifications.contains) ?? false
            if !known && (event == "SessionEnd" || (event == "Notification" && !waitingNotice)) { return nil }
            func ticketIndex(title: String? = nil) -> Int {
                if let i = tickets.firstIndex(where: { $0.externalId == key }) { return i }
                var ticket = Ticket(tool: .claudeCode, source: .automatic, title: title ?? fallbackTitle,
                                    thread: cwd.flatMap(QuickAdd.threadName(forLink:)) ?? "",
                                    deepLink: cwd ?? "", state: .working, stateSince: now)
                ticket.externalId = key
                tickets.append(ticket)
                return tickets.count - 1
            }
            func doing(_ i: Int, _ what: String?) {
                tickets[i].activity = what
                tickets[i].activityAt = what == nil ? nil : now
            }
            func waitOnNina(_ i: Int) throws {
                doing(i, nil)
                try tickets[i].apply(.needsYou, now: now)
            }

            // Before the event, so a brand-new ticket gets these too.
            let asked = (payload["prompt"] as? String).flatMap(FeedText.title(from:))
            let i = ticketIndex(title: asked)
            if let sessionName { tickets[i].chatName = sessionName }
            if tickets[i].chatName == nil, let asked { tickets[i].chatName = asked }  // first thing asked names it until it has a title
            if let hostApp { tickets[i].hostApp = hostApp }

            switch event {
            case "UserPromptSubmit":
                if let asked { tickets[i].title = asked }
                tickets[i].questionType = .none
                doing(i, "Reading your message")
                try tickets[i].apply(.stillRunning, now: now)

            case "PreToolUse":
                let tool = payload["tool_name"] as? String ?? ""
                let input = payload["tool_input"] as? [String: Any] ?? [:]
                if FeedText.isQuestion(tool) {
                    if let question = FeedText.questionText(input) { tickets[i].lastMessage = question }
                    let options = FeedText.optionLabels(input)
                    tickets[i].questionType = options.isEmpty ? .free : .choice(options)
                    try waitOnNina(i)
                } else {
                    doing(i, FeedText.activity(tool: tool, input: input))
                    if tickets[i].state != .working {
                        tickets[i].questionType = .none
                        try tickets[i].apply(.stillRunning, now: now)
                    }
                }

            case "PostToolUse":
                doing(i, "Thinking")
                if FeedText.isQuestion(payload["tool_name"]), tickets[i].state == .needsYou {
                    tickets[i].questionType = .none
                    try tickets[i].apply(.stillRunning, now: now)
                }

            case "Notification":
                guard let type = payload["notification_type"] as? String, waitingNotifications.contains(type) else {
                    return known ? nil : tickets[i]
                }
                // Idle after a finished reply is already waiting; don't restart its clock.
                if type == "idle_prompt" && tickets[i].state == .needsYou { return tickets[i] }
                if let message = payload["message"] as? String, !message.isEmpty, type != "idle_prompt" {
                    tickets[i].lastMessage = message
                    tickets[i].questionType = type == "permission_prompt" ? .yesNo : .free
                }
                try waitOnNina(i)

            case "Stop":
                if let reply = payload["last_assistant_message"] as? String, !reply.isEmpty { tickets[i].lastMessage = reply }
                tickets[i].questionType = QuestionDetector.detect(tickets[i].lastMessage)
                try waitOnNina(i)

            case "SessionEnd":
                doing(i, nil)
                try tickets[i].apply(.done, now: now)

            default:
                return known ? nil : tickets[i]
            }
            return tickets[i]
        }
    }

    static let claudeDesktop = "com.anthropic.claudefordesktop"
}

/// Reads a Claude Code session's title from its transcript. The transcript format is internal to
/// Claude Code, so this only looks for the title and gives up quietly if it's not there.
enum ClaudeCodeTranscript {
    private static let tailBytes = 256 * 1024

    static func title(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"custom-title\"") {
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let title = object["customTitle"] as? String, !title.isEmpty {
                return title
            }
        }
        return nil
    }
}
