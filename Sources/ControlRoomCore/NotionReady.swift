import Foundation

/// The "Ready to delegate" list: Task Tracker tasks with Agent ticked that aren't Done or Cancelled.
/// Read-only. Nothing is written back to Notion in v1 (SPEC section 5).
public enum NotionReady {
    /// Brain → Task Tracker.
    public static let taskTracker = "328c88a0-34db-8090-9ac8-000b36dd7c37"

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var notes: String
        public var due: Date?
        public var project: String?
        public var url: String

        /// What goes in the brief when it's clicked.
        public var brief: String { notes.isEmpty ? title : "\(title)\n\n\(notes)" }
    }

    public struct Problem: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func fetch(token: String, dataSource: String = taskTracker) async throws -> [Item] {
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/data_sources/\(dataSource)/query")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = [
            "filter": ["and": [
                ["property": "Agent", "checkbox": ["equals": true]],
                ["property": "Status", "select": ["does_not_equal": "Done"]],
                ["property": "Status", "select": ["does_not_equal": "Cancelled"]],
            ]],
            "sorts": [["property": "Due Date", "direction": "ascending"]],
            "page_size": 50,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem(message: "Couldn't reach Notion. Check the internet connection.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let message = json["message"] as? String ?? ""
            switch status {
            case 401: throw Problem(message: "Notion didn't accept the token. Run `cr set-notion-token` again with a fresh one.")
            case 404: throw Problem(message: "Notion can't see Task Tracker yet. In Notion, open Task Tracker, choose ••• → Connections, and add Control Room.")
            case 400 where message.contains("Agent"):
                throw Problem(message: "Task Tracker has no Agent checkbox yet. Add a checkbox column called Agent.")
            default: throw Problem(message: "Notion said: \(message.isEmpty ? "error \(status)" : message)")
            }
        }
        return (json["results"] as? [[String: Any]] ?? []).compactMap(item)
    }

    static func item(_ page: [String: Any]) -> Item? {
        guard let id = page["id"] as? String, let properties = page["properties"] as? [String: Any] else { return nil }
        func text(_ name: String, _ kind: String) -> String {
            let parts = (properties[name] as? [String: Any])?[kind] as? [[String: Any]] ?? []
            return parts.compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = text("Task", "title")
        guard !title.isEmpty else { return nil }
        let dueText = (((properties["Due Date"] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String)
        let project = ((properties["Project"] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String
        return Item(id: id, title: title, notes: text("Notes", "rich_text"), due: dueText.flatMap(parseDate),
                    project: project, url: page["url"] as? String ?? "")
    }

    static func parseDate(_ text: String) -> Date? {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(text.prefix(10)))
    }

    /// "Due Fri · Pret", "Tomorrow · Design", "No date · AI Thinking", as in the mockup.
    public static func meta(_ item: Item, now: Date = Date(), calendar: Calendar = .current) -> String {
        var due = "No date"
        if let date = item.due {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            switch days {
            case ..<0: f.dateFormat = "d MMM"; due = "Overdue · \(f.string(from: date))"
            case 0: due = "Today"
            case 1: due = "Tomorrow"
            case 2...6: f.dateFormat = "EEE"; due = "Due \(f.string(from: date))"
            default: f.dateFormat = "d MMM"; due = "Due \(f.string(from: date))"
            }
        }
        // Project options start with an emoji; the meta line is plain words.
        let project = item.project.map { String($0.drop { !$0.isLetter && !$0.isNumber }) }.flatMap { $0.isEmpty ? nil : $0 }
        return [due, project].compactMap { $0 }.joined(separator: " · ")
    }
}
