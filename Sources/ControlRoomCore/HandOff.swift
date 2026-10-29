import Foundation

/// Hand off (SPEC section 6): a brief, a tool and a place become a Working ticket.
public enum HandOff {
    /// The ticket Go creates. Claude Code tickets carry the session id the new session will use,
    /// so its hook events land on this ticket instead of making a new one.
    public static func ticket(tool: Tool, brief: String, folder: String?, sessionID: String? = nil,
                              notionPage: String? = nil, now: Date = Date()) -> Ticket {
        let title = FeedText.title(from: brief) ?? "Handed off"
        var ticket = Ticket(tool: tool, source: tool == .claudeCode ? .automatic : .manual, title: title,
                            thread: folder.flatMap(QuickAdd.threadName(forLink:)) ?? "",
                            deepLink: folder ?? (tool == .grok ? "https://grok.com" : ""),
                            state: .working, stateSince: now)
        ticket.brief = brief
        ticket.notionPage = notionPage
        if tool == .claudeCode, let sessionID {
            ticket.externalId = "claude-code:\(sessionID)"
            ticket.hostApp = "com.apple.Terminal"
            ticket.activity = "Starting up"
            ticket.activityAt = now
        }
        return ticket
    }

    /// A Cursor hand-off waits for Nina to paste the brief. When a new Cursor chat's first message
    /// is that brief, the chat takes over the hand-off ticket instead of getting a second one.
    static func matchesBrief(_ ticket: Ticket, prompt: String, now: Date) -> Bool {
        guard ticket.tool == .cursor, ticket.externalId == nil, ticket.state == .working,
              let brief = ticket.brief, now.timeIntervalSince(ticket.stateSince) < 24 * 3600 else { return false }
        let a = normalised(brief), b = normalised(prompt)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return b.hasPrefix(String(a.prefix(200))) || a.hasPrefix(String(b.prefix(200)))
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Folders Nina hands work off to, most recently used first. Kept in places.json next to the tickets.
public struct PlaceBook: Sendable {
    public struct Place: Codable, Equatable, Sendable {
        public var path: String
        public var lastUsed: Date
        /// The tool last handed off here, for remembering a default per project.
        public var lastTool: Tool?
    }

    let fileURL: URL

    public init(fileURL: URL = Config.directory.appendingPathComponent("places.json")) {
        self.fileURL = fileURL
    }

    public func saved() -> [Place] {
        guard let data = try? Data(contentsOf: fileURL),
              let places = try? JSONDecoder.controlRoom.decode([Place].self, from: data) else { return [] }
        return places
    }

    /// Folders to offer: ones handed off to (newest first), then any others seen on tickets, all still on disk.
    public func list(seenIn tickets: [Ticket]) -> [String] {
        var paths = saved().sorted { $0.lastUsed > $1.lastUsed }.map(\.path)
        let seen = tickets.sorted { $0.stateSince > $1.stateSince }.compactMap { QuickAdd.localFolder($0.deepLink)?.path }
        for path in seen where !paths.contains(path) { paths.append(path) }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    public func lastTool(for path: String) -> Tool? {
        saved().first { $0.path == path }?.lastTool
    }

    public func record(_ path: String, tool: Tool, at date: Date = Date()) {
        var places = saved().filter { $0.path != path }
        places.append(Place(path: path, lastUsed: date, lastTool: tool))
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.controlRoom.encode(places).write(to: fileURL, options: .atomic)
    }
}
