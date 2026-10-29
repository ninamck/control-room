import Foundation
import Testing
@testable import ControlRoomCore

// Thursday 29 Oct 2026. London is on GMT (UTC+0) from 25 Oct, so London times equal UTC here.
private let ics = """
BEGIN:VCALENDAR
X-WR-CALNAME:nina@example.com
BEGIN:VEVENT
UID:pret-weekly
DTSTART;TZID=Europe/London:20260903T123000
DTEND;TZID=Europe/London:20260903T130000
RRULE:FREQ=WEEKLY;BYDAY=TH
SUMMARY:Pret weekly
END:VEVENT
BEGIN:VEVENT
UID:standup
DTSTART;TZID=Europe/London:20260901T091500
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
EXDATE;TZID=Europe/London:20261029T091500
SUMMARY:Standup
END:VEVENT
BEGIN:VEVENT
UID:one-off
DTSTART:20261029T150000Z
SUMMARY:Ed // Pyke sync\\, product
END:VEVENT
BEGIN:VEVENT
UID:focus
DTSTART:20261029T140000Z
TRANSP:TRANSPARENT
SUMMARY:Focus block
END:VEVENT
BEGIN:VEVENT
UID:declined
DTSTART:20261029T160000Z
SUMMARY:All hands
ATTENDEE;CN=Nina;PARTSTAT=DECLINED:mailto:nina@example.com
END:VEVENT
BEGIN:VEVENT
UID:holiday
DTSTART;VALUE=DATE:20261029
SUMMARY:Team day off
END:VEVENT
BEGIN:VEVENT
UID:moved
DTSTART;TZID=Europe/London:20260910T100000
RRULE:FREQ=WEEKLY;BYDAY=TH
SUMMARY:Design crit
END:VEVENT
BEGIN:VEVENT
UID:moved
RECURRENCE-ID;TZID=Europe/London:20261029T100000
DTSTART;TZID=Europe/London:20261029T170000
SUMMARY:Design crit (moved)
END:VEVENT
END:VCALENDAR
"""

@Test func todaysEventsFromAPrivateCalendarLink() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/London")!
    let day = ISO8601DateFormatter().date(from: "2026-10-29T08:00:00Z")!
    let events = ICSCalendar.events(on: day, in: ics, calendar: cal)
    let titles = Set(events.map(\.title))
    #expect(titles.contains("Pret weekly"))
    #expect(!titles.contains("Standup"))                // excluded today
    #expect(titles.contains("Ed // Pyke sync, product"))
    #expect(titles.contains("Design crit (moved)"))
    #expect(!titles.contains("Design crit"))            // the moved occurrence replaces it

    // At 12:07 the next hard stop is Pret weekly at 12:30.
    let lunchtime = ISO8601DateFormatter().date(from: "2026-10-29T12:07:00Z")!
    #expect(HardStop.next(in: events, now: lunchtime, calendar: cal)?.line(lunchtime) == "NEXT HARD STOP · 23 MIN · Pret weekly")
    // After that: the focus block is free and All hands is declined, so it's the 15:00 sync.
    let afternoon = ISO8601DateFormatter().date(from: "2026-10-29T13:30:00Z")!
    #expect(HardStop.next(in: events, now: afternoon, calendar: cal)?.title == "Ed // Pyke sync, product")
    // Then the moved design crit, skipping the declined all hands.
    let late = ISO8601DateFormatter().date(from: "2026-10-29T15:30:00Z")!
    #expect(HardStop.next(in: events, now: late, calendar: cal)?.title == "Design crit (moved)")
}

@Test func repeatsRespectTheirEnd() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/London")!
    let ended = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:a
    DTSTART:20261001T090000Z
    RRULE:FREQ=DAILY;UNTIL=20261020T235959Z
    SUMMARY:Ended
    END:VEVENT
    BEGIN:VEVENT
    UID:b
    DTSTART:20261027T090000Z
    RRULE:FREQ=DAILY;COUNT=2
    SUMMARY:Two days only
    END:VEVENT
    END:VCALENDAR
    """
    let day = ISO8601DateFormatter().date(from: "2026-10-29T08:00:00Z")!
    #expect(ICSCalendar.events(on: day, in: ended, calendar: cal).isEmpty)
}
