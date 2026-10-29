import Foundation
import Testing
@testable import ControlRoomCore

@Test func nextHardStopIsTheNextBusyTimedEventToday() {
    let events = [
        HardStop.Event(title: "Lunch", start: noon - 3600),                          // already started
        HardStop.Event(title: "Focus time", start: noon + 600, busy: false),          // marked free
        HardStop.Event(title: "Company holiday", start: noon + 700, allDay: true),
        HardStop.Event(title: "Skipping this", start: noon + 800, declined: true),
        HardStop.Event(title: "Pret weekly", start: noon + 23 * 60),
        HardStop.Event(title: "Later today", start: noon + 3 * 3600),
        HardStop.Event(title: "Tomorrow", start: noon + 20 * 3600),
    ]
    let stop = HardStop.next(in: events, now: noon, calendar: utc)
    #expect(stop?.title == "Pret weekly")
    #expect(stop?.line(noon) == "NEXT HARD STOP · 23 MIN · Pret weekly")
    #expect(HardStop(title: "x", start: noon + 80 * 60).until(noon) == "1H 20M")
    #expect(HardStop.next(in: [HardStop.Event(title: "Tomorrow", start: noon + 20 * 3600)], now: noon, calendar: utc) == nil)
}
