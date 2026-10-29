import Foundation

/// Reads a calendar's private iCal link (Google Calendar's "secret address in iCal format")
/// and works out today's events, including repeating ones. Read only.
public enum ICSCalendar {
    public struct Problem: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func fetch(_ link: String) async throws -> String {
        var address = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.hasPrefix("webcal://") { address = "https://" + address.dropFirst("webcal://".count) }
        guard let url = URL(string: address), url.scheme == "https" else {
            throw Problem(message: "That doesn't look like a calendar link. It should start with https://")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Problem(message: "Couldn't reach the calendar. Check the internet connection.") }
        let text = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200, text.contains("BEGIN:VCALENDAR") else {
            throw Problem(message: "The link didn't return a calendar. Google may have switched private links off, or the link was reset.")
        }
        return text
    }

    /// Today's events from the calendar text, ready for HardStop.
    public static func events(on day: Date, in text: String, calendar: Calendar = .current) -> [HardStop.Event] {
        let blocks = parse(text)
        let owner = text.components(separatedBy: "\n").first { $0.hasPrefix("X-WR-CALNAME:") }
            .map { String($0.dropFirst("X-WR-CALNAME:".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        // One-off changes to a single repeat ("this event only") replace that occurrence.
        var overridden = Set<String>()
        var results: [HardStop.Event] = []
        for block in blocks where block.recurrenceID != nil {
            overridden.insert("\(block.uid)|\(Int(block.recurrenceID!.timeIntervalSince1970))")
            if let start = block.start, calendar.isDate(start, inSameDayAs: day), !block.cancelled {
                results.append(block.event(start: start, owner: owner))
            }
        }
        for block in blocks where block.recurrenceID == nil && !block.cancelled {
            guard let start = block.start else { continue }
            let occurrences = block.rule.map { occurrencesOn(day, rule: $0, start: start, exdates: block.exdates, calendar: calendar) }
                ?? (calendar.isDate(start, inSameDayAs: day) ? [start] : [])
            for occurrence in occurrences where !overridden.contains("\(block.uid)|\(Int(occurrence.timeIntervalSince1970))") {
                results.append(block.event(start: occurrence, owner: owner))
            }
        }
        return results
    }

    // MARK: Parsing

    struct Block {
        var uid = ""
        var summary = "Busy"
        var start: Date?
        var allDay = false
        var transparent = false
        var cancelled = false
        var rule: [String: String]?
        var exdates: Set<Int> = []
        var recurrenceID: Date?
        var declinedBy: [String] = []

        func event(start: Date, owner: String?) -> HardStop.Event {
            HardStop.Event(title: summary, start: start, busy: !transparent, allDay: allDay,
                           declined: owner.map { declinedBy.contains($0) } ?? false)
        }
    }

    static func parse(_ text: String) -> [Block] {
        // Long lines are folded onto the next line, starting with a space or tab.
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var blocks: [Block] = []
        var current: Block?
        for line in unfolded.components(separatedBy: "\n") {
            if line == "BEGIN:VEVENT" { current = Block(); continue }
            if line == "END:VEVENT" { if let c = current { blocks.append(c) }; current = nil; continue }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";").map(String.init)
            let name = parts.first ?? ""
            let params = Dictionary(parts.dropFirst().compactMap { p -> (String, String)? in
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0].uppercased(), kv[1].replacingOccurrences(of: "\"", with: "")) : nil
            }, uniquingKeysWith: { a, _ in a })
            switch name {
            case "UID": current!.uid = value
            case "SUMMARY": current!.summary = unescape(value)
            case "DTSTART":
                current!.allDay = params["VALUE"] == "DATE" || value.count == 8
                current!.start = date(value, tz: params["TZID"])
            case "TRANSP": current!.transparent = value == "TRANSPARENT"
            case "STATUS": current!.cancelled = value == "CANCELLED"
            case "RRULE":
                current!.rule = Dictionary(value.split(separator: ";").compactMap { p -> (String, String)? in
                    let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                    return kv.count == 2 ? (kv[0], kv[1]) : nil
                }, uniquingKeysWith: { a, _ in a })
            case "EXDATE":
                for v in value.split(separator: ",") {
                    if let d = date(String(v), tz: params["TZID"]) { current!.exdates.insert(Int(d.timeIntervalSince1970)) }
                }
            case "RECURRENCE-ID": current!.recurrenceID = date(value, tz: params["TZID"])
            case "ATTENDEE" where params["PARTSTAT"] == "DECLINED":
                current!.declinedBy.append(value.lowercased().replacingOccurrences(of: "mailto:", with: ""))
            default: break
            }
        }
        return blocks
    }

    /// "20261029T140000Z", "20261029T140000" with a TZID, or "20261029" for all-day.
    static func date(_ value: String, tz: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 {
            f.dateFormat = "yyyyMMdd"
            f.timeZone = .current
        } else if value.hasSuffix("Z") {
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
        } else {
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        }
        return f.date(from: value)
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Repeats

    static let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    /// The occurrences of a repeating event that fall on `day` (daily, weekly and monthly rules).
    static func occurrencesOn(_ day: Date, rule: [String: String], start: Date, exdates: Set<Int>, calendar: Calendar) -> [Date] {
        var cal = calendar
        cal.timeZone = .current
        guard day >= cal.startOfDay(for: start) else { return [] }
        let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)
        // The occurrence time on `day`: same wall-clock time as the first one.
        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        guard let occurrence = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) else { return [] }
        if let until = rule["UNTIL"].flatMap({ date($0, tz: nil) }), occurrence > until.addingTimeInterval(86_399) { return [] }

        let startDay = cal.startOfDay(for: start), thisDay = cal.startOfDay(for: day)
        let days = cal.dateComponents([.day], from: startDay, to: thisDay).day ?? 0
        let byDay = rule["BYDAY"].map { $0.split(separator: ",").compactMap { weekdayCodes[String($0.suffix(2))] } }
        let weekday = cal.component(.weekday, from: day)

        var matches: Bool
        switch rule["FREQ"] {
        case "DAILY":
            matches = days % interval == 0 && (byDay?.contains(weekday) ?? true)
        case "WEEKLY":
            let weeks = cal.dateComponents([.weekOfYear], from: cal.dateInterval(of: .weekOfYear, for: startDay)!.start,
                                           to: cal.dateInterval(of: .weekOfYear, for: thisDay)!.start).weekOfYear ?? 0
            matches = weeks % interval == 0 && (byDay ?? [cal.component(.weekday, from: start)]).contains(weekday)
        case "MONTHLY":
            let months = cal.dateComponents([.month], from: startDay, to: thisDay).month ?? 0
            matches = months % interval == 0 && cal.component(.day, from: day) == cal.component(.day, from: start)
        default:
            matches = false
        }
        guard matches, !exdates.contains(Int(occurrence.timeIntervalSince1970)) else { return [] }
        if let count = rule["COUNT"].flatMap(Int.init), count < 500 {
            // Count the occurrences up to this one.
            var seen = 0
            var cursor = startDay
            while cursor <= thisDay {
                if !occurrencesOnIgnoringCount(cursor, rule: rule, start: start, cal: cal).isEmpty { seen += 1 }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
            if seen > count { return [] }
        }
        return [occurrence]
    }

    private static func occurrencesOnIgnoringCount(_ day: Date, rule: [String: String], start: Date, cal: Calendar) -> [Date] {
        var withoutCount = rule
        withoutCount["COUNT"] = nil
        return occurrencesOn(day, rule: withoutCount, start: start, exdates: [], calendar: cal)
    }
}
