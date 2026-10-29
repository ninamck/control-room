import Foundation

/// Turns Cursor's agent hook events (https://cursor.com/docs/agent/hooks) into tickets.
/// One ticket per Cursor conversation, found again by its conversation id.
///
///   beforeSubmitPrompt  Nina sent a message: working
///   afterAgentResponse  keep the agent's reply as the last message
///   preToolUse          the agent is asking Nina a question: needs_you
///   postToolUse         she answered it: working
///   stop                completed: needs_you if it ended on a question, otherwise done.
///                       aborted: done. error: blocked.
///   sessionEnd          conversation closed while working: done
public enum CursorFeed {
    public static let events = ["beforeSubmitPrompt", "afterAgentResponse", "preToolUse", "postToolUse", "stop", "sessionEnd"]

    /// Applies one hook event. Returns the ticket it touched, if any.
    @discardableResult
    public static func handle(_ payload: [String: Any], store: TicketStore) throws -> Ticket? {
        guard let event = payload["hook_event_name"] as? String,
              let conversation = payload["conversation_id"] as? String, !conversation.isEmpty else { return nil }
        let externalID = "cursor:\(conversation)"
        let folder = (payload["workspace_roots"] as? [String])?.first

        return try store.update { tickets, now in
            let index = tickets.firstIndex { $0.externalID == externalID }

            switch event {
            case "beforeSubmitPrompt":
                let prompt = payload["prompt"] as? String ?? ""
                guard let i = index else {
                    var ticket = Ticket(tool: .cursor, source: .automatic, title: title(from: prompt),
                                        thread: folder.flatMap(QuickAdd.threadName(forLink:)) ?? "",
                                        deepLink: folder ?? "", state: .working, stateSince: now)
                    ticket.externalID = externalID
                    tickets.append(ticket)
                    return ticket
                }
                tickets[i].questionType = .none
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "afterAgentResponse":
                guard let i = index, let text = payload["text"] as? String, !text.isEmpty else { return nil }
                tickets[i].lastMessage = text
                return tickets[i]

            case "preToolUse":
                guard let i = index, isQuestion(payload["tool_name"]) else { return nil }
                let input = payload["tool_input"] as? [String: Any] ?? [:]
                if let question = questionText(input) { tickets[i].lastMessage = question }
                let options = optionLabels(input)
                tickets[i].questionType = options.isEmpty ? .free : .choice(options)
                try tickets[i].apply(.needsYou, now: now)
                return tickets[i]

            case "postToolUse":
                guard let i = index, isQuestion(payload["tool_name"]), tickets[i].state == .needsYou else { return nil }
                tickets[i].questionType = .none
                try tickets[i].apply(.stillRunning, now: now)
                return tickets[i]

            case "stop":
                guard let i = index else { return nil }
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
                guard let i = index, tickets[i].state == .working else { return nil }
                try tickets[i].apply(.done, now: now)
                return tickets[i]

            default:
                return nil
            }
        }
    }

    /// First line of Nina's first prompt, cut to fit a row.
    static func title(from prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if line.isEmpty { return "Cursor agent" }
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
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
