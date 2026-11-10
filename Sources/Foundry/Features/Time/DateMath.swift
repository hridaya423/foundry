import Foundation

/// Date arithmetic for the launcher: an offset from a date ("30 days from now",
/// "today + 2 weeks", "3 months ago") or the distance to one ("days until
/// christmas", "weeks since jan 1"). A date with no year means its next
/// occurrence when counting forward and its last one when counting back.
enum DateMath {
    struct Side: Hashable, Sendable {
        let value: String
        let caption: String
    }

    struct Answer: Equatable {
        let from: Side
        let to: Side
        let copyText: String
        let isoText: String?
    }

    private enum Direction {
        case future, past, thisYear
    }

    private static let amount = #"(\d{1,5}|an?|one)"#
    private static let unit = "(day|week|month|year)s?"
    private static let fillers = ["how many ", "what is ", "what's ", "whats ", "what date is ", "what date was ", "the date "]

    private static let offsetAfter = try! NSRegularExpression(pattern: "^(?:in )?\(amount) \(unit) (from|after|before) (.+)$")
    private static let offsetIn = try! NSRegularExpression(pattern: "^in \(amount) \(unit)$")
    private static let offsetAgo = try! NSRegularExpression(pattern: "^\(amount) \(unit) ago$")
    private static let offsetSigned = try! NSRegularExpression(pattern: "^(.+?) ?(\\+|-|plus|minus) ?\(amount) \(unit)$")
    private static let countTo = try! NSRegularExpression(pattern: "^\(unit) (until|till|til|to|before|since|from|after) (.+)$")
    private static let countBetween = try! NSRegularExpression(pattern: "^\(unit) between (.+) and (.+)$")

    static func answer(for query: String, now: Date, calendar: Calendar) -> Answer? {
        var text = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        for filler in fillers where text.hasPrefix(filler) { text.removeFirst(filler.count) }
        let today = calendar.startOfDay(for: now)

        func groups(_ regex: NSRegularExpression) -> [String]? {
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
            return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        func offset(_ amount: String, _ unit: String, sign: Int, base: Date, caption: String) -> Answer? {
            let count = Int(amount) ?? 1
            guard let date = calendar.date(byAdding: component(unit), value: sign * count, to: base) else { return nil }
            return Answer(
                from: Side(value: plural(count, unit), caption: caption),
                to: Side(value: format(date, calendar), caption: weekday(date, calendar)),
                copyText: format(date, calendar),
                isoText: iso(date, calendar)
            )
        }
        func count(_ unit: String, from start: Date, to end: Date, anchor: Date, caption: String) -> Answer? {
            let span = distance(from: min(start, end), to: max(start, end), unit: unit, calendar: calendar)
            return Answer(
                from: Side(value: format(anchor, calendar), caption: weekday(anchor, calendar)),
                to: Side(value: span.text, caption: caption),
                copyText: span.count.map(String.init) ?? span.text,
                isoText: nil
            )
        }

        if let parts = groups(offsetIn) {
            return offset(parts[0], parts[1], sign: 1, base: today, caption: "from today")
        }
        if let parts = groups(offsetAgo) {
            return offset(parts[0], parts[1], sign: -1, base: today, caption: "ago")
        }
        if let parts = groups(offsetAfter), let base = date(parts[3], today: today, calendar: calendar, direction: .future) {
            let before = parts[2] == "before"
            let relation = base == today ? (before ? "before today" : "from today") : "\(before ? "before" : "after") \(format(base, calendar))"
            return offset(parts[0], parts[1], sign: before ? -1 : 1, base: base, caption: relation)
        }
        if let parts = groups(countBetween), let start = date(parts[1], today: today, calendar: calendar, direction: .thisYear),
           let end = date(parts[2], today: today, calendar: calendar, direction: .thisYear) {
            return count(parts[0], from: start, to: end, anchor: start, caption: "to \(format(end, calendar))")
        }
        if let parts = groups(countTo) {
            let back = ["since", "from", "after"].contains(parts[1])
            guard let target = date(parts[2], today: today, calendar: calendar, direction: back ? .past : .future), target != today
            else { return nil }
            return count(parts[0], from: today, to: target, anchor: target, caption: target < today ? "ago" : "from today")
        }
        if let parts = groups(offsetSigned), let base = date(parts[0], today: today, calendar: calendar, direction: .future) {
            let minus = ["-", "minus"].contains(parts[1])
            let relation = base == today ? (minus ? "before today" : "from today") : "\(minus ? "before" : "after") \(format(base, calendar))"
            return offset(parts[2], parts[3], sign: minus ? -1 : 1, base: base, caption: relation)
        }
        return nil
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let holidays: [String: (month: Int, day: Int)] = [
        "christmas": (12, 25), "christmas day": (12, 25), "xmas": (12, 25), "christmas eve": (12, 24), "boxing day": (12, 26),
        "new year": (1, 1), "new years": (1, 1), "new year's": (1, 1), "new years day": (1, 1), "new year's day": (1, 1),
        "new years eve": (12, 31), "new year's eve": (12, 31), "halloween": (10, 31), "valentines": (2, 14), "valentine's": (2, 14),
        "valentines day": (2, 14), "valentine's day": (2, 14)
    ]
    private static let isoDate = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})$"#)
    private static let namedDate = try! NSRegularExpression(
        pattern: #"^(?:(\d{1,2})(?:st|nd|rd|th)? )?([a-z]{3,9})\.?(?: (\d{1,2})(?:st|nd|rd|th)?)?(?:,? (\d{4}))?$"#
    )

    private static func date(_ text: String, today: Date, calendar: Calendar, direction: Direction) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces)
        switch text {
        case "now", "today": return today
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }

        let name = text.hasPrefix("next ") ? String(text.dropFirst(5)) : text
        if let index = weekdays.firstIndex(where: { $0 == name || (name.count >= 3 && $0.hasPrefix(name) && name.count <= 4) }) {
            let ahead = (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
            return calendar.date(byAdding: .day, value: direction == .past ? ahead - 7 : (ahead == 0 ? 7 : ahead), to: today)
        }

        func resolve(year: Int?, month: Int, day: Int) -> Date? {
            var components = DateComponents(year: year ?? calendar.component(.year, from: today), month: month, day: day)
            func valid() -> Date? {
                guard let date = calendar.date(from: components), calendar.component(.month, from: date) == month,
                      calendar.component(.day, from: date) == day else { return nil }
                return date
            }
            guard year == nil, let date = valid() else { return valid() }
            if direction == .future, date < today { components.year! += 1 }
            if direction == .past, date > today { components.year! -= 1 }
            return valid()
        }

        if let holiday = holidays[text] { return resolve(year: nil, month: holiday.month, day: holiday.day) }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        if let match = isoDate.firstMatch(in: text, range: whole),
           let year = group(match, 1).flatMap(Int.init), let month = group(match, 2).flatMap(Int.init), let day = group(match, 3).flatMap(Int.init) {
            return resolve(year: year, month: month, day: day)
        }
        if let match = namedDate.firstMatch(in: text, range: whole), let word = group(match, 2),
           let month = months.firstIndex(where: { word.hasPrefix($0) && (word.count == 3 || monthNames[$0] == word) }),
           let day = (group(match, 1) ?? group(match, 3)).flatMap(Int.init), (group(match, 1) == nil) != (group(match, 3) == nil) {
            return resolve(year: group(match, 4).flatMap(Int.init), month: month + 1, day: day)
        }
        return nil
    }

    private static let monthNames = [
        "jan": "january", "feb": "february", "mar": "march", "apr": "april", "may": "may", "jun": "june", "jul": "july", "aug": "august",
        "sep": "september", "oct": "october", "nov": "november", "dec": "december"
    ]

    private static func component(_ unit: String) -> Calendar.Component {
        switch unit {
        case "week": .weekOfYear
        case "month": .month
        case "year": .year
        default: .day
        }
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }

    private static func distance(from start: Date, to end: Date, unit: String, calendar: Calendar) -> (count: Int?, text: String) {
        let fields: Set<Calendar.Component> = switch unit {
        case "week": [.weekOfYear, .day]
        case "month": [.month, .day]
        case "year": [.year, .month, .day]
        default: [.day]
        }
        let parts = calendar.dateComponents(fields, from: start, to: end)
        let pieces = [(parts.year, "year"), (parts.month, "month"), (parts.weekOfYear, "week"), (parts.day, "day")]
            .compactMap { piece in piece.0.map { ($0, piece.1) } }.filter { $0.0 > 0 }
        guard let first = pieces.first else { return (0, plural(0, unit)) }
        return (pieces.count == 1 ? first.0 : nil, pieces.map { plural($0.0, $0.1) }.joined(separator: " "))
    }

    private static func format(_ date: Date, _ calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: calendar.locale ?? .current, calendar: calendar,
            timeZone: calendar.timeZone))
    }

    private static func weekday(_ date: Date, _ calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
    }

    private static func iso(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
