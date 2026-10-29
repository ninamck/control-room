import Foundation

/// Events the Cursor hook couldn't deliver because Control Room was closed or restarting.
/// The hook writes each one to queue/cursor; this applies them in the order they happened.
public enum EventQueue {
    static var cursorFolder: URL { Config.directory.appendingPathComponent("queue/cursor", isDirectory: true) }

    /// Applies and removes every queued event. Returns how many were applied.
    @discardableResult
    public static func drain(into store: TicketStore) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cursorFolder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
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
                if (try? CursorFeed.handle(payload, store: store)) != nil { applied += 1 }
            }
            try? fm.removeItem(at: file)
        }
        return applied
    }
}
