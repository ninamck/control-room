import ControlRoomCore
import Foundation

/// Reads the next hard stop from the calendar's private iCal link (the Google calendar Notion Calendar shows).
/// Fetched every 5 minutes; the hard stop itself is worked out again on every tick. Read only.
@MainActor
final class CalendarWatch {
    private var text: String?
    private var fetchedAt: Date?
    private var fetching = false
    static let refetchEvery: TimeInterval = 5 * 60

    /// The next hard stop, or why there isn't one to show.
    var onChange: (HardStop?, String?) -> Void = { _, _ in }

    func start() { refresh() }

    func refresh(now: Date = Date()) {
        guard let link = (try? Config.loadOrCreate())?.calendarLink, !link.isEmpty else {
            onChange(nil, "Calendar not connected. Run `cr set-calendar-link` in Terminal and paste your calendar's secret iCal address.")
            return
        }
        if let text {
            onChange(HardStop.next(in: ICSCalendar.events(on: now, in: text), now: now), nil)
        }
        guard !fetching, now.timeIntervalSince(fetchedAt ?? .distantPast) > Self.refetchEvery else { return }
        fetching = true
        Task {
            do {
                text = try await ICSCalendar.fetch(link)
                fetchedAt = Date()
                onChange(HardStop.next(in: ICSCalendar.events(on: Date(), in: text!), now: Date()), nil)
            } catch {
                // Keep showing what we had; only explain if there's nothing.
                if text == nil { onChange(nil, error.localizedDescription) }
                fetchedAt = Date()
            }
            fetching = false
        }
    }
}
