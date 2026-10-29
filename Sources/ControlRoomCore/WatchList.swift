import Foundation

/// A scheduled task Nina watches (SPEC section 5): edited in Claude or Grok, only watched here.
public struct WatchedTask: Codable, Equatable, Identifiable, Sendable {
    public struct Cadence: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case daily, weekdays, weekly, fortnightly }
        public var kind: Kind
        /// For weekly and fortnightly: 1 = Sunday … 7 = Saturday, as Calendar counts.
        public var weekday: Int?
        /// For fortnightly: a date in a week it runs.
        public var anchor: Date?

        public init(kind: Kind, weekday: Int? = nil, anchor: Date? = nil) {
            self.kind = kind
            self.weekday = weekday
            self.anchor = anchor
        }

        /// "daily", "weekdays", "Mondays", "fortnightly"
        public var label: String {
            switch kind {
            case .daily: return "daily"
            case .weekdays: return "weekdays"
            case .weekly:
                var calendar = Calendar(identifier: .gregorian)
                calendar.locale = Locale(identifier: "en_GB")
                return weekday.map { calendar.weekdaySymbols[$0 - 1] + "s" } ?? "weekly"
            case .fortnightly: return "fortnightly"
            }
        }
    }

    public var id: String
    public var name: String
    public var tool: Tool
    /// "HH:mm", local time.
    public var time: String
    public var cadence: Cadence
    /// Where its results show up, for Open.
    public var link: String?
    public var created: Date
    /// The last run that landed as a card, and how it ended.
    public var lastLanded: Date?
    public var lastRead: Date?
    public var lastUnread: Date?
    public var lastMissed: Date?

    public init(id: String = UUID().uuidString.lowercased(), name: String, tool: Tool, time: String,
                cadence: Cadence, link: String? = nil, created: Date = Date()) {
        self.id = id
        self.name = name
        self.tool = tool
        self.time = time
        self.cadence = cadence
        self.link = link
        self.created = created
    }

    var hourMinute: (Int, Int)? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    /// Whether it runs on this day.
    func runs(on day: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        switch cadence.kind {
        case .daily: return true
        case .weekdays: return (2...6).contains(weekday)
        case .weekly: return weekday == (cadence.weekday ?? weekday)
        case .fortnightly:
            guard weekday == (cadence.weekday ?? weekday) else { return false }
            let anchor = calendar.startOfDay(for: cadence.anchor ?? created)
            let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: day)).day ?? 0
            return (days / 7) % 2 == 0
        }
    }

    func run(on day: Date, calendar: Calendar) -> Date? {
        guard let (h, m) = hourMinute, runs(on: day, calendar: calendar) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    /// The most recent run at or before now, looking back up to 15 days.
    public func previousRun(atOrBefore now: Date, calendar: Calendar = .current) -> Date? {
        for back in 0...15 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now),
                  let run = run(on: day, calendar: calendar), run <= now else { continue }
            return run
        }
        return nil
    }

    /// The next run after now, looking ahead up to 15 days.
    public func nextRun(after now: Date, calendar: Calendar = .current) -> Date? {
        for ahead in 0...15 {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: now),
                  let run = run(on: day, calendar: calendar), run > now else { continue }
            return run
        }
        return nil
    }
}

/// The watch list, kept in watch.json next to the tickets.
public final class WatchList: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    public private(set) var tasks: [WatchedTask] = []

    public init(fileURL: URL = Config.directory.appendingPathComponent("watch.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.controlRoom.decode([WatchedTask].self, from: data) {
            tasks = saved
        }
    }

    public func add(_ task: WatchedTask) { change { $0.append(task) } }
    public func remove(_ id: String) { change { $0.removeAll { $0.id == id } } }

    /// Lands any run whose time has come: a card for Nina to read, which never wakes the companion.
    /// An unread card from the previous run goes when the next one lands (DECISIONS.md).
    public func land(into store: TicketStore, now: Date = Date(), calendar: Calendar = .current) throws {
        let due: [(Int, Date)] = lock.withLock {
            tasks.indices.compactMap { i in
                let task = tasks[i]
                guard let run = task.previousRun(atOrBefore: now, calendar: calendar),
                      run > task.created, run > (task.lastLanded ?? .distantPast) else { return nil }
                return (i, run)
            }
        }
        guard !due.isEmpty else { return }
        var unread: [String: Date] = [:]
        try store.update { tickets, now in
            for (i, run) in due {
                let task = tasks[i]
                let key = "schedule:\(task.id)"
                if let old = tickets.firstIndex(where: { $0.externalId == key && $0.state == .needsYou }) {
                    unread[task.id] = tickets[old].schedule?.expected
                    tickets.remove(at: old)
                }
                tickets.removeAll { $0.externalId == key }
                var ticket = Ticket(tool: task.tool, source: .manual, kind: .scheduled, title: task.name,
                                    deepLink: task.link ?? "", state: .needsYou, stateSince: run,
                                    schedule: Schedule(cadence: task.cadence.label, expected: run))
                ticket.externalId = key
                tickets.append(ticket)
            }
        }
        change { tasks in
            for (i, run) in due {
                tasks[i].lastLanded = run
                if let missedRead = unread[tasks[i].id] { tasks[i].lastUnread = missedRead }
            }
        }
    }

    /// Read it: the card goes to Done and the watch list remembers the run was fine.
    public func markRead(_ ticket: Ticket, store: TicketStore) throws {
        try store.apply(.done, to: ticket.id)
        record(ticket) { $0.lastRead = $1 }
    }

    /// Didn't run: the card goes and the watch list shows Missed until the next run.
    public func markMissed(_ ticket: Ticket, store: TicketStore) throws {
        _ = try store.drop(ticket.id)
        record(ticket) { $0.lastMissed = $1 }
    }

    private func record(_ ticket: Ticket, _ body: @escaping (inout WatchedTask, Date) -> Void) {
        guard let id = ticket.externalId?.replacingOccurrences(of: "schedule:", with: ""),
              let run = ticket.schedule?.expected else { return }
        change { tasks in
            if let i = tasks.firstIndex(where: { $0.id == id }) { body(&tasks[i], run) }
        }
    }

    private func change(_ body: (inout [WatchedTask]) -> Void) {
        lock.withLock {
            body(&tasks)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder.controlRoom.encode(tasks).write(to: fileURL, options: .atomic)
        }
    }

    // MARK: How a row reads

    public enum Status: Equatable, Sendable {
        case soon(minutes: Int)   // IN 8 MIN (sky)
        case later(String)        // TOMORROW, MON, 14:00 (paper)
        case unread               // UNREAD (pink)
        case missed               // MISSED (coral)
    }

    public static func status(_ task: WatchedTask, tickets: [Ticket], now: Date, calendar: Calendar = .current) -> Status {
        if tickets.contains(where: { $0.externalId == "schedule:\(task.id)" && $0.state == .needsYou }) { return .unread }
        if let missed = task.lastMissed, missed == task.lastLanded { return .missed }
        guard let next = task.nextRun(after: now, calendar: calendar) else { return .later("—") }
        let minutes = Int(next.timeIntervalSince(now) / 60)
        if minutes < 60 { return .soon(minutes: max(1, minutes)) }
        if calendar.isDate(next, inSameDayAs: now) { return .later("TODAY") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next, inSameDayAs: tomorrow) { return .later("TOMORROW") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE"
        return .later(f.string(from: next).uppercased())
    }

    /// "last ok · Thu", "unread · Thu", "no run Mon 27", or "—".
    public static func lastResult(_ task: WatchedTask) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE"
        let latest = [(task.lastRead, "last ok"), (task.lastUnread, "unread"), (task.lastMissed, "no run")]
            .compactMap { date, label in date.map { ($0, label) } }
            .max { $0.0 < $1.0 }
        guard let (date, label) = latest else { return "—" }
        if label == "no run" {
            f.dateFormat = "EEE d"
            return "no run \(f.string(from: date))"
        }
        return "\(label) · \(f.string(from: date))"
    }
}
