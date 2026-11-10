import Foundation

/// Parses natural-language time queries into absolute instants and renders
/// zone conversions. Everything takes `now` and the user's `local` zone so
/// results are deterministic under test.
///
/// Supported forms (filler such as "what's the", "right now" and "?" is ignored):
///   now | current time | what time is it | utc      -> local time in UTC, unix row
///   time in <zone> | time <zone> | <zone> time | <zone> now | now in <zone>
///   <zone> to <zone>[, <zone>]                      -> the current time, converted
///   H[:MM][am|pm] [in] <zone> [to|in <zone>[,|and <zone>]*]
///   <zone> H[:MM]am|pm [to|in <zone>…]
///   noon | midnight in place of a numeric time
///   today | tomorrow | yesterday | <weekday> anywhere after the time
///
/// A bare time with no zone words returns nothing — the zone is what makes the
/// intent unambiguous. Without a day word the time is read on the source
/// zone's current day. A weekday means its next occurrence. `matchingPolicy:
/// .nextTime` skips nonexistent wall times (spring-forward gaps) forward and
/// `.first` picks the first occurrence of ambiguous ones (fall-back).
enum TimeConversionEngine {
    struct Reading: Hashable, Sendable {
        let time: String
        let place: String
        let abbreviation: String?
        let day: String?

        var caption: String {
            ([place] + [abbreviation == place ? nil : abbreviation, day].compactMap { $0 }).joined(separator: " · ")
        }
    }

    struct Conversion: Equatable {
        let source: Reading
        let target: Reading
        let subtitle: String   // "12:00 PM EDT in Eastern Time → Your time (PDT)"
        let copyText: String   // "9:00 AM PDT"
        let copyLine: String?  // "12:00 PM EDT → 9:00 AM PDT"; nil for current-time rows
        let isoText: String    // "2026-09-12T01:00:00Z"

        var title: String { target.time }
    }

    static func recognizes(_ query: String) -> Bool {
        parse(query) != nil
    }

    static func conversions(for query: String, now: Date, local: TimeZone) -> [Conversion] {
        guard let parsed = parse(query) else { return [] }
        let here = TimeZoneResolver.labelled(local, name: "Your time")
        switch parsed {
        case let .now(sourceToken, targetTokens):
            return nowRows(sourceToken: sourceToken, targetTokens: targetTokens, now: now, here: here)
        case let .convert(spec):
            return convertRows(spec: spec, now: now, here: here)
        }
    }

    // MARK: - Parsing

    private enum ParsedQuery {
        case now(sourceToken: String?, targetTokens: [String])
        case convert(TimeSpec)
    }

    private struct TimeSpec {
        var hour: Int
        var minute: Int
        var sourceToken: String
        var targetTokens: [String] = []
        var dayOffset: Int?
        var weekday: Int? // Calendar weekday: 1 = Sunday
    }

    private static let nowWords: Set<String> = [
        "now", "time now", "current time", "the time", "what time is it", "what's the time", "whats the time", "what is the time",
        "utc", "gmt", "unix time"
    ]
    private static let leadingFiller = ["what's the ", "whats the ", "what is the ", "what ", "the ", "current ", "local ", "at "]
    private static let trailingFiller = ["?", " right now", " now", " currently", " at the moment", " please"]
    private static let localTokens: Set<String> = ["my time", "local", "local time", "here", "me", "mine"]
    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7
    ]

    private static let clockPattern = #"noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?"#
    private static let strictClockPattern = #"noon|midnight|\d{1,2}:\d{2}\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm)"#
    private static let timeFirstRegex = try? NSRegularExpression(pattern: "^(\(clockPattern))\\s+(.+)$")
    private static let zoneFirstRegex = try? NSRegularExpression(pattern: "^(.+?)\\s+(\(strictClockPattern))(?:\\s+(.+))?$")
    private static let nowInRegex = try? NSRegularExpression(pattern: #"^(?:now|time(?: is it)?) (?:in|at|for) (.+)$"#)
    private static let clockRegex = try? NSRegularExpression(pattern: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#)
    private static let dayWordRegex = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:on )?(today|tomorrow|yesterday|sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?=\s|$)"#
    )

    private static func groups(_ regex: NSRegularExpression?, in text: String) -> [String?]? {
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    private static func parse(_ raw: String) -> ParsedQuery? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        text = text.components(separatedBy: .whitespaces).filter { $0.isEmpty == false }.joined(separator: " ")
        guard text.isEmpty == false else { return nil }

        var saidNow = false
        while nowWords.contains(text) == false, let filler = trailingFiller.first(where: { text.hasSuffix($0) && text.count > $0.count }) {
            text = String(text.dropLast(filler.count)).trimmingCharacters(in: .whitespaces)
            saidNow = saidNow || filler != "?"
        }
        if nowWords.contains(text) {
            return .now(sourceToken: nil, targetTokens: ["utc", "gmt"].contains(text) ? ["utc"] : [])
        }
        while let filler = leadingFiller.first(where: text.hasPrefix) {
            text = String(text.dropFirst(filler.count))
        }

        if let zone = groups(nowInRegex, in: text)?[1] {
            return .now(sourceToken: nil, targetTokens: [zone])
        }
        if text.hasPrefix("time "), isZone(String(text.dropFirst(5))) {
            return .now(sourceToken: nil, targetTokens: [String(text.dropFirst(5))])
        }
        if text.hasSuffix(" time") || saidNow, isZone(text) {
            return .now(sourceToken: nil, targetTokens: [text])
        }

        if let parts = groups(timeFirstRegex, in: text), let clock = parts[1].flatMap(clockTime), let rest = parts[2] {
            return .convert(spec(hour: clock.0, minute: clock.1, zones: rest))
        }
        if let parts = groups(zoneFirstRegex, in: text), let zone = parts[1], let clock = parts[2].flatMap(clockTime) {
            return .convert(spec(hour: clock.0, minute: clock.1, zones: [zone, parts[3]].compactMap { $0 }.joined(separator: " ")))
        }
        if text.rangeOfCharacter(from: .decimalDigits) == nil, let split = text.range(of: " to ") ?? text.range(of: " in ") {
            let source = String(text[..<split.lowerBound])
            let targets = targetTokens(String(text[split.upperBound...]))
            if isZone(source), targets.contains(where: isZone) {
                return .now(sourceToken: source, targetTokens: targets)
            }
        }
        return nil
    }

    private static func isZone(_ token: String) -> Bool {
        localTokens.contains(token) || resolve(token) != nil
    }

    private static func resolve(_ token: String) -> TimeZoneResolver.ResolvedZone? {
        TimeZoneResolver.resolve(token) ?? (token.hasSuffix(" time") ? TimeZoneResolver.resolve(String(token.dropLast(5))) : nil)
    }

    private static func targetTokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
    }

    private static func spec(hour: Int, minute: Int, zones: String) -> TimeSpec {
        var spec = TimeSpec(hour: hour, minute: minute, sourceToken: "")
        var rest = zones
        if let match = dayWordRegex?.firstMatch(in: rest, range: NSRange(rest.startIndex..<rest.endIndex, in: rest)),
           let wordRange = Range(match.range(at: 1), in: rest), let whole = Range(match.range, in: rest) {
            switch String(rest[wordRange]) {
            case "today": spec.dayOffset = 0
            case "tomorrow": spec.dayOffset = 1
            case "yesterday": spec.dayOffset = -1
            case let word: spec.weekday = weekdays[word]
            }
            rest.replaceSubrange(whole, with: " ")
            rest = rest.components(separatedBy: .whitespaces).filter { $0.isEmpty == false }.joined(separator: " ")
        }

        if rest.hasPrefix("in ") { rest = String(rest.dropFirst(3)) }
        while rest.hasSuffix(" to") || rest.hasSuffix(" in") || rest.hasSuffix(",") {
            rest = String(rest.dropLast(rest.hasSuffix(",") ? 1 : 3)).trimmingCharacters(in: .whitespaces)
        }
        if rest.hasPrefix("to ") {
            spec.targetTokens = targetTokens(String(rest.dropFirst(3)))
        } else if let split = rest.range(of: " to ") ?? rest.range(of: " in ") {
            spec.sourceToken = String(rest[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
            spec.targetTokens = targetTokens(String(rest[split.upperBound...]))
        } else {
            spec.sourceToken = rest
        }
        return spec
    }

    private static func clockTime(_ token: String) -> (Int, Int)? {
        if token == "noon" { return (12, 0) }
        if token == "midnight" { return (0, 0) }
        guard let parts = groups(clockRegex, in: token), let hour = parts[1].flatMap(Int.init) else { return nil }
        let minute = parts[2].flatMap(Int.init) ?? 0
        guard minute <= 59 else { return nil }
        if let meridiem = parts[3] {
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12 + (meridiem == "pm" ? 12 : 0), minute)
        }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }

    // MARK: - Instant math

    private static func instant(for spec: TimeSpec, in source: TimeZone, after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        var components = DateComponents(hour: spec.hour, minute: spec.minute)
        let anchor: Date
        if let weekday = spec.weekday {
            components.weekday = weekday
            anchor = now
        } else {
            guard let day = calendar.date(byAdding: .day, value: spec.dayOffset ?? 0, to: calendar.startOfDay(for: now)) else { return nil }
            anchor = day.addingTimeInterval(-1)
        }
        return calendar.nextDate(after: anchor, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    // MARK: - Rendering

    private static func zone(_ token: String, here: TimeZoneResolver.ResolvedZone) -> TimeZoneResolver.ResolvedZone? {
        localTokens.contains(token) ? here : resolve(token)
    }

    private static func targets(
        _ tokens: [String], source: TimeZoneResolver.ResolvedZone, here: TimeZoneResolver.ResolvedZone, at instant: Date
    ) -> [TimeZoneResolver.ResolvedZone] {
        guard tokens.isEmpty else { return tokens.compactMap { zone($0, here: here) } }
        let utc = TimeZoneResolver.labelled(utcZone, name: "UTC")
        var offsets: Set = [source.zone.secondsFromGMT(for: instant)]
        let defaults = [here, utc].filter { offsets.insert($0.zone.secondsFromGMT(for: instant)).inserted }
        return defaults.isEmpty ? [utc] : defaults
    }

    private static func convertRows(spec: TimeSpec, now: Date, here: TimeZoneResolver.ResolvedZone) -> [Conversion] {
        guard let source = spec.sourceToken.isEmpty ? here : zone(spec.sourceToken, here: here),
              let instant = instant(for: spec, in: source.zone, after: now) else { return [] }
        let namesDay = spec.weekday != nil || spec.dayOffset != nil
        return targets(spec.targetTokens, source: source, here: here, at: instant).map {
            render(instant: instant, source: source, target: $0, here: here, namesDay: namesDay, isNow: false)
        }
    }

    private static func nowRows(sourceToken: String?, targetTokens: [String], now: Date, here: TimeZoneResolver.ResolvedZone) -> [Conversion] {
        guard let source = sourceToken.map({ zone($0, here: here) }) ?? here else { return [] }
        var rows = targets(targetTokens, source: source, here: here, at: now).map {
            render(instant: now, source: source, target: $0, here: here, namesDay: false, isNow: sourceToken == nil)
        }
        if sourceToken == nil, targetTokens.isEmpty {
            let stamp = String(Int(now.timeIntervalSince1970))
            rows.append(Conversion(
                source: reading(now, in: here, day: nil),
                target: Reading(time: stamp, place: "Unix timestamp", abbreviation: nil, day: nil),
                subtitle: "Unix timestamp",
                copyText: stamp,
                copyLine: nil,
                isoText: isoString(now)
            ))
        }
        return rows
    }

    private static func reading(_ instant: Date, in zone: TimeZoneResolver.ResolvedZone, day: String?) -> Reading {
        Reading(time: timeString(instant, in: zone.zone), place: zone.name, abbreviation: zone.abbreviation(for: instant), day: day)
    }

    private static func render(
        instant: Date, source: TimeZoneResolver.ResolvedZone, target: TimeZoneResolver.ResolvedZone, here: TimeZoneResolver.ResolvedZone,
        namesDay: Bool, isNow: Bool
    ) -> Conversion {
        let sourceDay = dayText(instant, in: source.zone, format: "yyyy-MM-dd")
        let targetDay = dayText(instant, in: target.zone, format: "yyyy-MM-dd")
        var sourceLabel: String?
        var targetLabel: String?
        if namesDay {
            sourceLabel = dayText(instant, in: source.zone, format: "EEE")
            targetLabel = dayText(instant, in: target.zone, format: "EEE")
        } else if targetDay != sourceDay {
            let later = targetDay > sourceDay
            targetLabel = isNow ? (later ? "tomorrow" : "yesterday") : (later ? "next day" : "previous day")
        }

        let from = reading(instant, in: source, day: sourceLabel)
        let to = reading(instant, in: target, day: targetLabel)
        let fromText = [sourceLabel, from.time, from.abbreviation].compactMap { $0 }.joined(separator: " ")
        let toText = [to.time, to.abbreviation].compactMap { $0 }.joined(separator: " ")
        let dayNote = targetLabel.map { " · \($0)" } ?? ""

        let subtitle: String
        if isNow {
            subtitle = "\(target.name) (\(to.abbreviation ?? "")) · \(offsetDescription(of: target.zone, at: instant, relativeTo: here.zone))\(dayNote)"
        } else {
            let left = source.zone == here.zone ? fromText : "\(fromText) in \(source.name)"
            let right = target.zone == here.zone ? "Your time (\(to.abbreviation ?? ""))" : "\(target.name) (\(to.abbreviation ?? ""))"
            subtitle = "\(left) → \(right)\(dayNote)"
        }
        return Conversion(
            source: from,
            target: to,
            subtitle: subtitle,
            copyText: toText,
            copyLine: isNow ? nil : "\(fromText) → \(toText)",
            isoText: isoString(instant)
        )
    }

    // MARK: - Formatters (created per call: DateFormatter is not Sendable)

    private static let utcZone = TimeZone(identifier: "Etc/UTC")!

    private static func timeString(_ date: Date, in zone: TimeZone) -> String {
        dayText(date, in: zone, format: "h:mm a")
    }

    private static func dayText(_ date: Date, in zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func offsetDescription(of zone: TimeZone, at instant: Date, relativeTo local: TimeZone) -> String {
        let delta = zone.secondsFromGMT(for: instant) - local.secondsFromGMT(for: instant)
        guard delta != 0 else { return "same time as you" }
        let absDelta = abs(delta)
        let hours = absDelta / 3600
        let minutes = (absDelta % 3600) / 60
        let amount = minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        return delta > 0 ? "\(amount) ahead of you" : "\(amount) behind you"
    }

    private static func isoString(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
