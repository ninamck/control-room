import Foundation

/// Owns the tickets and saves them to tickets.json after every change.
public final class TicketStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var tickets: [Ticket] = []
    private let now: () -> Date

    public init(fileURL: URL = Config.directory.appendingPathComponent("tickets.json"),
                now: @escaping () -> Date = Date.init) throws {
        self.fileURL = fileURL
        self.now = now
        if let data = try? Data(contentsOf: fileURL) {
            tickets = try JSONDecoder.controlRoom.decode([Ticket].self, from: data)
        }
    }

    /// All tickets, with the timing rules applied first.
    public func all() throws -> [Ticket] {
        try locked { tickets }
    }

    @discardableResult
    public func add(_ ticket: Ticket) throws -> Ticket {
        try locked {
            tickets.append(ticket)
            return ticket
        }
    }

    @discardableResult
    public func apply(_ action: TicketAction, to idOrPrefix: String) throws -> Ticket {
        try locked {
            let i = try index(of: idOrPrefix)
            try tickets[i].apply(action, now: now())
            return tickets[i]
        }
    }

    @discardableResult
    public func drop(_ idOrPrefix: String) throws -> Ticket {
        try locked {
            let i = try index(of: idOrPrefix)
            return tickets.remove(at: i)
        }
    }

    /// Runs the timing rules and saves if anything changed. Called on a timer.
    public func tick() throws {
        try locked { () }
    }

    /// Every read and write goes through here: rules first, then the change, then save.
    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let before = tickets
        tickets = Rules.tick(tickets, now: now())
        let result = try body()
        if tickets != before { try save() }
        return result
    }

    private func index(of idOrPrefix: String) throws -> Int {
        let key = idOrPrefix.lowercased()
        let matches = tickets.indices.filter { tickets[$0].id.hasPrefix(key) }
        guard !key.isEmpty, let first = matches.first else { throw RuleError("No ticket with id \(idOrPrefix).") }
        guard matches.count == 1 else { throw RuleError("More than one ticket starts with \(idOrPrefix). Type more of the id.") }
        return first
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.controlRoom.encode(tickets).write(to: fileURL, options: .atomic)
    }
}
