import ControlRoomCore
import EventKit
import Foundation

/// Reads today's events from the Mac's Calendar (which includes Google calendars added to the Mac).
/// Read only; nothing is written to the calendar (SPEC section 2).
@MainActor
final class CalendarWatch {
    private let store = EKEventStore()
    private var watching: NSObjectProtocol?

    /// The next hard stop, or why there isn't one to show.
    var onChange: (HardStop?, String?) -> Void = { _, _ in }

    func start() {
        watching = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            // macOS asks Nina once.
            store.requestFullAccessToEvents { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        default:
            refresh()
        }
    }

    func refresh(now: Date = Date()) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            onChange(nil, "Control Room can't see your calendar. Allow it in System Settings → Privacy & Security → Calendars.")
            return
        }
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else {
            onChange(nil, "No calendars on this Mac yet. Add your Google account in System Settings → Internet Accounts.")
            return
        }
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: calendars)
        let events = store.events(matching: predicate).map { event in
            HardStop.Event(title: event.title ?? "Busy",
                           start: event.startDate,
                           busy: event.availability != .free,
                           allDay: event.isAllDay,
                           declined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
        onChange(HardStop.next(in: events, now: now), nil)
    }
}
