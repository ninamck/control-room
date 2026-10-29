import Foundation

/// End of day (SPEC section 6): what finished, what still wants Nina, and what keeps getting put off.
public struct EndOfDay: Sendable {
    public let done: [Ticket]
    public let waiting: [Ticket]
    public let putOff: [Ticket]

    public init(tickets: [Ticket], now: Date) {
        let putOff = tickets.filter { Self.isPutOff($0, now: now) }
            .sorted { $0.stateSince < $1.stateSince }
        let putOffIDs = Set(putOff.map(\.id))
        self.putOff = putOff
        done = tickets.filter { $0.state == .done }.sorted { $0.stateSince > $1.stateSince }
        waiting = tickets.filter { ($0.state == .needsYou || $0.state == .blocked) && !putOffIDs.contains($0.id) }
            .sorted { $0.stateSince < $1.stateSince }
    }

    /// Later pressed three or more times, or parked for over a day, and not kept for another day.
    public static func isPutOff(_ t: Ticket, now: Date) -> Bool {
        guard t.state != .done, t.state != .working else { return false }
        if let kept = t.keptUntil, kept > now { return false }
        if t.laterCount >= 3 { return true }
        return t.state == .parked && now.timeIntervalSince(t.stateSince) > 24 * 3600
    }

    /// "Nine finished. Two still want you."
    public var headline: String {
        let finished = done.isEmpty ? "Nothing finished." : "\(Self.words(done.count).capitalizedFirst) finished."
        let want: String
        switch waiting.count {
        case 0: want = "Nothing still wants you."
        case 1: want = "One still wants you."
        default: want = "\(Self.words(waiting.count).capitalizedFirst) still want you."
        }
        return "\(finished) \(want)"
    }

    /// Why a put-off ticket is here: "pressed Later 3 times", "parked since Tuesday", "never handed off".
    public static func reason(_ t: Ticket, now: Date) -> String {
        if t.laterCount >= 3 { return "pressed Later \(t.laterCount) times" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = now.timeIntervalSince(t.stateSince) < 6 * 24 * 3600 ? "EEEE" : "d MMM"
        return "parked since \(f.string(from: t.stateSince))"
    }

    /// Never given to an agent: worth handing off rather than keeping.
    public static func neverStarted(_ t: Ticket) -> Bool {
        t.source == .manual && t.externalId == nil
    }

    /// "nine", for headlines and "and three more".
    public static func words(_ n: Int) -> String {
        let names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        return n < names.count ? names[n] : "\(n)"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
