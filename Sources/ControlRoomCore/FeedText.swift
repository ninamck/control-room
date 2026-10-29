import Foundation

/// How agent messages and tool calls read to Nina. Shared by every feed (Cursor, Claude Code).
enum FeedText {
    /// Messages a tool sends on its own, in the same form as Nina's, e.g. when a background task finishes.
    static let automaticFollowUps = ["Briefly inform the user about the task result"]

    /// Lines Cursor adds when Nina points at something on a page. Not her words.
    static let pastedElementPrefixes = ["DOM Path:", "Position:", "HTML Element:", "React Component:"]

    /// A row-length title from what Nina asked, or nil if the message has none of her own words.
    /// A bare link becomes its readable last part.
    static func title(from prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if automaticFollowUps.contains(where: trimmed.hasPrefix) { return nil }
        let line = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .lazy
            .compactMap { line -> String? in
                if line.isEmpty { return nil }
                // Her words follow the pasted element on the same line: "...</div> will this default to open?"
                if line.hasPrefix("HTML Element:") { return wordsAfterElement(line) }
                return pastedElementPrefixes.contains(where: line.hasPrefix) ? nil : line
            }
            .first
        guard let line else { return nil }
        if let readable = readableLink(line) { return readable }
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }

    /// Text after the last closing tag of a pasted element, if any.
    static func wordsAfterElement(_ line: String) -> String? {
        guard let close = line.range(of: "</", options: .backwards),
              let end = line.range(of: ">", range: close.upperBound..<line.endIndex) else { return nil }
        let words = line[end.upperBound...].trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? nil : words
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

    /// What a tool call looks like to Nina: "Running npm test", "Editing basket.tsx", "Searching the code".
    static func activity(tool: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String ?? input["target_file"] as? String ?? input["path"] as? String)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        let name = tool.lowercased()
        switch name {
        case "shell", "bash", "terminal", "run_terminal_cmd":
            return command(input["command"] as? String).map { "Running \($0)" } ?? "Running a command"
        case "read", "read_file":
            return file.map { "Reading \($0)" } ?? "Reading files"
        case "write", "edit", "multiedit", "notebookedit", "strreplace", "str_replace", "search_replace", "applypatch", "apply_patch", "edit_file":
            return file.map { "Editing \($0)" } ?? "Editing files"
        case "delete", "delete_file":
            return file.map { "Deleting \($0)" } ?? "Deleting a file"
        case "grep", "glob", "search", "codebase_search", "semanticsearch", "list_dir", "ls":
            return "Searching the code"
        case "websearch", "web_search", "webfetch", "fetch":
            return "Looking something up online"
        case "task", "agent":
            return "Handing part of it to a helper"
        case "todowrite", "todo_write":
            return "Updating its plan"
        case "readlints", "read_lints":
            return "Checking for errors"
        default:
            // Cursor: "mcp:server:tool". Claude Code: "mcp__server__tool".
            if name.hasPrefix("mcp") {
                let parts = tool.components(separatedBy: tool.contains("__") ? "__" : ":").filter { !$0.isEmpty }
                return "Using \(parts.last ?? tool)"
            }
            return "Using \(tool)"
        }
    }

    /// The interesting part of a shell command: skips a leading `cd ... &&`, cut to fit.
    static func command(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        while text.hasPrefix("cd "), let and = text.range(of: "&&") {
            text = text[and.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.count > 40 ? String(firstLine.prefix(39)) + "…" : firstLine
    }

    /// The tool an agent uses to ask Nina a multiple-choice question: Cursor's isn't documented,
    /// Claude Code's is AskUserQuestion, so match anything that sounds like asking.
    static func isQuestion(_ toolName: Any?) -> Bool {
        guard let name = (toolName as? String)?.lowercased() else { return false }
        // Not just "ask": the subagent tool is called Task. A plan waiting for approval needs her too.
        return name.contains("question") || name.hasPrefix("ask") || name == "exitplanmode"
    }

    static func questionText(_ input: [String: Any]) -> String? {
        if let q = input["question"] as? String { return q }
        if let questions = input["questions"] as? [[String: Any]], let q = questions.first?["question"] as? String { return q }
        if input["plan"] != nil { return "Plan ready for your approval" }
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
