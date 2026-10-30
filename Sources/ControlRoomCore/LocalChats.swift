import Foundation

/// A chat in an app that keeps its conversations on this Mac (the Claude app's task sessions, Grok Bot),
/// as Control Room reads it. Neither app documents these files, so everything here is read only and
/// anything unexpected means "nothing to report" rather than a wrong state.
public struct LocalChat: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case working(String)
        /// A reply has finished: Nina's turn.
        case replied(String)
        /// Stopped for something only Nina can give, like permission.
        case waiting(String)
        case idle
    }

    public var key: String
    public var tool: Tool
    public var kind: Kind
    public var chatName: String?
    /// What Nina last asked.
    public var asked: String?
    public var status: Status
    /// Changes whenever the chat does something new, so Nina's Done sticks until it does.
    public var signature: String
    public var lastActivity: Date
    public var hostApp: String
    /// Grok Bot's own unread flag.
    public var unread = false
    public var scheduledTask: String?
    public var cadence: String?
}

// MARK: Claude app

/// The Claude app's task sessions: ~/Library/Application Support/Claude/local-agent-mode-sessions.
/// Each has local_<id>.json (title, times, scheduled task) and local_<id>/audit.jsonl (what happened).
public enum ClaudeAppChats {
    static let bundleID = "com.anthropic.claudefordesktop"

    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_CLAUDE_APP_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
    }

    /// A turn still "working" this long after its last activity was cut off (the app quit mid-reply).
    static let stale: TimeInterval = 30 * 60

    public static func scan(root: URL = root, now: Date = Date(), within: TimeInterval = 48 * 3600) -> [LocalChat] {
        let fm = FileManager.default
        var chats: [LocalChat] = []
        var cadences: [String: String] = [:]
        for account in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for space in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                cadences.merge(scheduledCadences(in: space)) { a, _ in a }
                let files = (try? fm.contentsOfDirectory(at: space, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    let audit = auditFile(for: file)
                    guard let modified = (try? audit.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                            ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                          now.timeIntervalSince(modified) < within,
                          let chat = read(session: file, audit: audit, modified: modified, now: now) else { continue }
                    chats.append(chat)
                }
            }
        }
        return chats.map { chat in
            var c = chat
            if let task = c.scheduledTask { c.cadence = cadences[task] }
            return c
        }
    }

    /// Older sessions log to local_<id>/audit.jsonl; newer ones to <first 8 characters of the id>/audit.jsonl.
    static func auditFile(for session: URL) -> URL {
        let old = session.deletingPathExtension().appendingPathComponent("audit.jsonl")
        if FileManager.default.fileExists(atPath: old.path) { return old }
        let id = session.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "local_", with: "")
        return session.deletingLastPathComponent().appendingPathComponent(String(id.prefix(8))).appendingPathComponent("audit.jsonl")
    }

    static func read(session file: URL, audit: URL, modified: Date, now: Date) -> LocalChat? {
        guard let data = try? Data(contentsOf: file),
              let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = session["sessionId"] as? String,
              session["isArchived"] as? Bool != true else { return nil }
        let task = (session["scheduledTaskId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = (session["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let entries = tail(of: audit)
        let size = (try? FileManager.default.attributesOfItem(atPath: audit.path)[.size] as? Int) ?? 0

        var status = LocalChat.Status.idle
        var asked: String?
        var lastAssistantText: String?
        var lastTool: (String, [String: Any])?
        for entry in entries {
            let type = entry["type"] as? String ?? ""
            let subtype = entry["subtype"] as? String
            switch type {
            case "user":
                if let text = text(of: entry), FeedText.title(from: text) != nil { asked = text }
                status = .working("Reading your message")
            case "assistant":
                if let text = text(of: entry), !text.isEmpty { lastAssistantText = text }
                if let use = toolUse(of: entry) { lastTool = use }
                status = .working(lastTool.map { FeedText.activity(tool: $0.0, input: $0.1) } ?? "Thinking")
            case "result":
                let summary = (entry["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? lastAssistantText ?? "Finished."
                status = (subtype ?? "success") == "success" ? .replied(summary) : .waiting("Stopped: \(subtype!.replacingOccurrences(of: "_", with: " "))")
                lastTool = nil
            case "system" where subtype == "permission_request":
                status = .waiting("Wants your permission to carry on")
            case "system" where subtype == "permission_response":
                status = .working(lastTool.map { FeedText.activity(tool: $0.0, input: $0.1) } ?? "Thinking")
            default:
                break
            }
        }
        if case .working = status, now.timeIntervalSince(modified) > stale { status = .idle }
        if entries.isEmpty, let first = session["initialMessage"] as? String { asked = first }

        let kindName: String = switch status {
        case .working: "working"
        case .replied: "replied"
        case .waiting: "waiting"
        case .idle: "idle"
        }
        return LocalChat(key: "claude-app:\(id)", tool: .claudeAI, kind: task == nil ? .interactive : .scheduled,
                         chatName: title, asked: asked, status: status, signature: "\(kindName)|\(size)",
                         lastActivity: modified, hostApp: bundleID, scheduledTask: task)
    }

    /// The last part of the log, enough for the latest turn. Progress ticks are dropped.
    static func tail(of file: URL, bytes: Int = 384 * 1024) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: file.path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { line in
            // Skip progress ticks by their type, not by searching the text: a finished turn's line
            // mentions thinking tokens in its usage figures.
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  entry["type"] as? String != "tool_progress", entry["subtype"] as? String != "thinking_tokens" else { return nil }
            return entry
        }
    }

    static func text(of entry: [String: Any]) -> String? {
        let content = (entry["message"] as? [String: Any])?["content"]
        if let s = content as? String { return s }
        let parts = (content as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func toolUse(of entry: [String: Any]) -> (String, [String: Any])? {
        let parts = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        guard let use = parts.last(where: { $0["type"] as? String == "tool_use" }), let name = use["name"] as? String else { return nil }
        return (name, use["input"] as? [String: Any] ?? [:])
    }

    /// "weekdays", "daily", "Mondays" from each scheduled task's cron line.
    static func scheduledCadences(in space: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: space.appendingPathComponent("scheduled-tasks.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let tasks = json["scheduledTasks"] as? [[String: Any]] ?? (json["scheduledTasks"] as? [String: [String: Any]]).map { Array($0.values) } ?? []
        var result: [String: String] = [:]
        for task in tasks {
            guard let id = task["id"] as? String, let cron = task["cronExpression"] as? String else { continue }
            result[id] = cadence(cron)
        }
        return result
    }

    static func cadence(_ cron: String) -> String {
        let fields = cron.split(separator: " ").map(String.init)
        guard fields.count >= 5 else { return "scheduled" }
        let names = ["0": "Sundays", "1": "Mondays", "2": "Tuesdays", "3": "Wednesdays", "4": "Thursdays", "5": "Fridays", "6": "Saturdays", "7": "Sundays"]
        switch fields[4] {
        case "*": return fields[2] == "*" ? "daily" : "monthly"
        case "1-5": return "weekdays"
        case let day where names[day] != nil: return names[day]!
        default: return "scheduled"
        }
    }

    /// "morning-briefing" → "Morning briefing"
    static func taskName(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

// MARK: Grok Bot

/// Grok Bot keeps its chats in sand-client-persistence as JSON files with base32-encoded names:
/// a roster (each chat's name, unread count, last activity) and a transcript per chat.
public enum GrokBotChats {
    static let bundleID = "com.anysphere.sand"

    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_GROK_BOT_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
    }

    public static func scan(root: URL = root, now: Date = Date(), within: TimeInterval = 48 * 3600) -> [LocalChat] {
        let files = keyedFiles(in: root)
        guard let rosterFile = files.first(where: { $0.key.hasSuffix(".roster.last-roster") })?.value,
              let roster = json(rosterFile)?["value"] as? [String: Any],
              let rows = roster["rows"] as? [[String: Any]] else { return [] }
        let transcripts = Dictionary(files.compactMap { key, url -> (String, URL)? in
            guard let range = key.range(of: ".transcript.replicas.") else { return nil }
            return (String(key[range.upperBound...]), url)
        }, uniquingKeysWith: { a, _ in a })

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  row["isHiddenFromSidebar"] as? Bool != true, row["isRemovedFromSidebar"] as? Bool != true else { return nil }
            let unreadCount = row["unreadCount"] as? Int ?? 0
            let unread = (row["hasUnread"] as? Bool ?? false) || unreadCount > 0
            let activity = (row["lastActivityAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? .distantPast
            guard unread || now.timeIntervalSince(activity) < within else { return nil }

            let entries = transcripts[id].flatMap(json).flatMap { ($0["value"] as? [String: Any])?["entries"] as? [[String: Any]] } ?? []
            let lastReply = entries.last { $0["kind"] as? String == "message" && $0["role"] as? String == "assistant" }
            let lastSent = entries.last { $0["kind"] as? String == "send-message" }
            let asked = (lastSent?["message"] as? [String: Any])?["content"] as? String
            let preview = (row["lastEntry"] as? [String: Any])?["text"] as? String

            let status: LocalChat.Status
            if unread {
                status = .replied(preview ?? (lastReply?["content"] as? String) ?? "New reply")
            } else if lastReply?["isStreaming"] as? Bool == true {
                status = .working("Writing a reply")
            } else if let sent = lastSent?["seq"] as? Int, sent > (lastReply?["seq"] as? Int ?? -1),
                      now.timeIntervalSince(activity) < 15 * 60 {
                status = .working("Thinking")
            } else {
                status = .idle
            }
            let kindName: String = switch status {
            case .working: "working"
            case .replied: "replied"
            case .waiting: "waiting"
            case .idle: "idle"
            }
            let newest = row["newestEntryId"] as? String ?? ""
            return LocalChat(key: "grok-bot:\(id)", tool: .grok, kind: .interactive,
                             chatName: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             asked: asked, status: status, signature: "\(kindName)|\(newest)|\(unreadCount)",
                             lastActivity: activity, hostApp: bundleID, unread: unread)
        }
    }

    static func keyedFiles(in root: URL) -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return Dictionary(files.compactMap { url -> (String, URL)? in
            guard url.pathExtension == "blob" else { return nil }
            return decode(url.deletingPathExtension().lastPathComponent).map { ($0, url) }
        }, uniquingKeysWith: { a, _ in a })
    }

    /// Lower-case base32 without padding.
    static func decode(_ name: String) -> String? {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0, value = 0
        var bytes: [UInt8] = []
        for ch in name.lowercased() {
            guard let index = alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: Into tickets

public enum LocalChatFeed {
    /// What each chat looked like last time, so only new activity makes a ticket
    /// (and the first look after installing doesn't flood the board with old replies).
    static var seenURL: URL { Config.directory.appendingPathComponent("local-chats-seen.json") }

    public static func apply(_ chats: [LocalChat], store: TicketStore) throws {
        let previous: [String: String]? = (try? Data(contentsOf: seenURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        try apply(chats, store: store, seen: previous)
        let now = Dictionary(chats.map { ($0.key, $0.signature) }, uniquingKeysWith: { a, _ in a })
        try? JSONEncoder().encode(now).write(to: seenURL, options: .atomic)
    }

    /// `seen` nil means this is the first look: only chats working now, or with unread Grok replies, get tickets.
    static func apply(_ chats: [LocalChat], store: TicketStore, seen: [String: String]?) throws {
        try store.update { tickets, now in
            for chat in chats {
                var index = tickets.firstIndex { $0.externalId == chat.key }
                let isNew = index == nil
                if index == nil {
                    let changed = seen.map { $0[chat.key] != chat.signature } ?? false
                    let isWorking: Bool = if case .working = chat.status { true } else { false }
                    guard chat.status != .idle, changed || isWorking || chat.unread else { continue }
                    let title = chat.asked.flatMap(FeedText.title(from:))
                        ?? chat.scheduledTask.map(ClaudeAppChats.taskName) ?? chat.chatName ?? "\(chat.tool.displayName) chat"
                    var ticket = Ticket(tool: chat.tool, source: .automatic, kind: chat.kind, title: title,
                                        state: .working, stateSince: chat.lastActivity)
                    ticket.externalId = chat.key
                    ticket.hostApp = chat.hostApp
                    ticket.scheduledTask = chat.scheduledTask
                    if chat.kind == .scheduled {
                        ticket.title = chat.scheduledTask.map(ClaudeAppChats.taskName) ?? title
                        ticket.schedule = Schedule(cadence: chat.cadence ?? "scheduled", expected: chat.lastActivity)
                    }
                    tickets.append(ticket)
                    index = tickets.count - 1
                }
                let i = index!
                if let name = chat.chatName { tickets[i].chatName = name }
                guard tickets[i].feedStatus != chat.signature else { continue }
                tickets[i].feedStatus = chat.signature
                if chat.kind == .interactive, let asked = chat.asked.flatMap(FeedText.title(from:)) { tickets[i].title = asked }

                switch chat.status {
                case .working(let what):
                    tickets[i].activity = what
                    tickets[i].activityAt = now
                    tickets[i].questionType = .none
                    tickets[i].quickReplyReady = false
                    try tickets[i].apply(.stillRunning, now: now)
                case .replied(let text), .waiting(let text):
                    tickets[i].lastMessage = text
                    tickets[i].questionType = QuestionDetector.detect(text)
                    tickets[i].activity = nil
                    if tickets[i].kind == .scheduled {
                        // A new run of a scheduled task replaces an unread earlier one (DECISIONS.md).
                        let task = tickets[i].scheduledTask
                        let id = tickets[i].id
                        tickets[i].schedule?.expected = chat.lastActivity
                        try tickets[i].apply(.needsYou, now: now)
                        tickets.removeAll { $0.id != id && task != nil && $0.scheduledTask == task && $0.state == .needsYou }
                    } else {
                        try tickets[i].apply(.needsYou, now: now)
                    }
                    // A reply found on first sight has been waiting since it arrived, not since Control Room noticed.
                    // Found by id: the scheduled branch above may have removed an earlier ticket and shifted positions.
                    if isNew, let j = tickets.firstIndex(where: { $0.externalId == chat.key }),
                       chat.lastActivity < tickets[j].stateSince {
                        tickets[j].stateSince = chat.lastActivity
                    }
                case .idle:
                    // Read in Grok Bot: its own unread flag cleared, so the reply has been seen.
                    if chat.tool == .grok, !chat.unread, tickets[i].state == .needsYou { try tickets[i].apply(.done, now: now) }
                    tickets[i].activity = nil
                }
            }
        }
    }
}
