import Foundation

/// Events the hooks couldn't deliver because Control Room was closed or restarting.
/// Each hook writes them to queue/<feed>; this applies them in the order they happened.
public enum EventQueue {
    static let feeds: [(folder: String, handle: ([String: Any], TicketStore) throws -> Ticket?)] = [
        ("cursor", { try CursorFeed.handle($0, store: $1) }),
        ("claude-code", { try ClaudeCodeFeed.handle($0, store: $1) }),
    ]

    /// Applies and removes every queued event. Returns how many were applied.
    @discardableResult
    public static func drain(into store: TicketStore) -> Int {
        feeds.reduce(0) { $0 + drain(folder: $1.folder, into: store, with: $1.handle) }
    }

    private static func drain(folder: String, into store: TicketStore, with handle: ([String: Any], TicketStore) throws -> Ticket?) -> Int {
        let fm = FileManager.default
        let url = Config.directory.appendingPathComponent("queue/\(folder)", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let ordered = files.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da == db ? a.lastPathComponent < b.lastPathComponent : da < db
        }
        var applied = 0
        for file in ordered {
            if let data = try? Data(contentsOf: file),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                EventLog.record(payload, note: "from queue")
                if (try? handle(payload, store)) != nil { applied += 1 }
            }
            try? fm.removeItem(at: file)
        }
        return applied
    }
}
