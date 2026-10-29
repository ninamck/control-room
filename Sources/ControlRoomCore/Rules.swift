import Foundation

/// The timing rules from SPEC section 4. Pure functions of the tickets and the clock.
public enum Rules {
    /// needs_you turns coral after this long.
    public static let coralAfter: TimeInterval = 15 * 60
    /// Later hides a ticket for this long.
    public static let laterFor: TimeInterval = 30 * 60

    /// Applies everything that happens with the passing of time:
    /// Later tickets come back, and done tickets expire at midnight.
    public static func tick(_ tickets: [Ticket], now: Date, calendar: Calendar = .current) -> [Ticket] {
        let startOfToday = calendar.startOfDay(for: now)
        return tickets.compactMap { ticket in
            var t = ticket
            if t.state == .done && t.stateSince < startOfToday { return nil }
            if t.state == .later, let until = t.laterUntil, until <= now {
                t.state = .needsYou
                t.stateSince = t.waitingSince ?? t.stateSince
                t.laterUntil = nil
                t.waitingSince = nil
            }
            return t
        }
    }
}

public enum TicketAction: String, CaseIterable, Sendable {
    case later
    case park
    case done
    case stillRunning = "still-running"
    case needsYou = "needs-you"
    case blocked
}

public struct RuleError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension Ticket {
    /// Moves the ticket the way a button press or a feed would.
    public mutating func apply(_ action: TicketAction, now: Date) throws {
        switch action {
        case .later:
            guard state == .needsYou else { throw RuleError("Only a ticket waiting on you can go to Later.") }
            waitingSince = stateSince
            laterUntil = now.addingTimeInterval(Rules.laterFor)
            laterCount += 1
            state = .later
            stateSince = now
        case .park: move(to: .parked, now: now)
        case .done: move(to: .done, now: now)
        case .stillRunning: move(to: .working, now: now)
        case .needsYou: move(to: .needsYou, now: now)
        case .blocked: move(to: .blocked, now: now)
        }
    }

    private mutating func move(to newState: TicketState, now: Date) {
        if newState != state { stateSince = now }
        state = newState
        laterUntil = nil
        waitingSince = nil
    }
}
