import Foundation

/// The next hard stop (SPEC section 5): time until the next event marked busy, and its title.
public struct HardStop: Equatable, Sendable {
    public let title: String
    public let start: Date

    /// A calendar event, as much as this needs to know.
    public struct Event: Sendable {
        public var title: String
        public var start: Date
        public var busy: Bool
        public var allDay: Bool
        public var declined: Bool

        public init(title: String, start: Date, busy: Bool = true, allDay: Bool = false, declined: Bool = false) {
            self.title = title
            self.start = start
            self.busy = busy
            self.allDay = allDay
            self.declined = declined
        }
    }

    /// The next busy, timed, not-declined event starting later today.
    public static func next(in events: [Event], now: Date, calendar: Calendar = .current) -> HardStop? {
        events
            .filter { $0.busy && !$0.allDay && !$0.declined && $0.start > now && calendar.isDate($0.start, inSameDayAs: now) }
            .min { $0.start < $1.start }
            .map { HardStop(title: $0.title, start: $0.start) }
    }

    public func minutes(from now: Date) -> Int {
        max(0, Int(ceil(start.timeIntervalSince(now) / 60)))
    }

    /// "23 MIN", "1H 20M"
    public func until(_ now: Date) -> String {
        let m = minutes(from: now)
        return m < 60 ? "\(m) MIN" : (m % 60 == 0 ? "\(m / 60)H" : "\(m / 60)H \(m % 60)M")
    }

    /// "NEXT HARD STOP · 23 MIN · Pret weekly"
    public func line(_ now: Date) -> String {
        "NEXT HARD STOP · \(until(now)) · \(title)"
    }
}
