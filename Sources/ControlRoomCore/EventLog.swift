import Foundation

/// Keeps the last 300 feed events (time, event name, tool name only, never message text)
/// in feed-events.log, so a feed that misbehaves can be diagnosed.
enum EventLog {
    private static let lock = NSLock()
    private static let limit = 300

    static func record(_ payload: [String: Any], note: String? = nil) {
        let time = ISO8601DateFormatter().string(from: Date())
        var line = "\(time) \(payload["hook_event_name"] as? String ?? "?")"
        if let tool = payload["tool_name"] as? String { line += " tool=\(tool)" }
        if let status = payload["status"] as? String { line += " status=\(status)" }
        if let conversation = payload["conversation_id"] as? String { line += " conversation=\(conversation.prefix(8))" }
        if let session = payload["session_id"] as? String, payload["conversation_id"] == nil { line += " session=\(session.prefix(8))" }
        if let type = payload["notification_type"] as? String { line += " type=\(type)" }
        if let note { line += " (\(note))" }

        lock.lock()
        defer { lock.unlock() }
        let url = Config.directory.appendingPathComponent("feed-events.log")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append(line)
        try? lines.suffix(limit).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
