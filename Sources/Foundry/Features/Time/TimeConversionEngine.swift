import Foundation

/// Parses natural-language time queries into absolute instants and renders
/// zone conversions. Everything takes `now` and the user's `local` zone so
/// results are deterministic under test.
///
/// Supported forms:
///   now | time | current time                     -> local, UTC, unix rows
///   now in <zone> | time in <zone> | <zone> time | what time is it in <zone>
///   H[:MM][am|pm] [in] <zone> [today|tomorrow|yesterday|<weekday>] [to|in <zone>[,|and <zone>]*]
///   noon | midnight in place of a numeric time
///
/// A bare time with no zone words returns nothing — the zone is what makes the
/// intent unambiguous. Without an explicit modifier the instant is the *next*
/// occurrence of that wall time in the source zone, so conversions never point
/// into the past. `matchingPolicy: .nextTime` skips nonexistent wall times
/// (spring-forward gaps) forward and `.first` picks the first occurrence of
/// ambiguous ones (fall-back).
enum TimeConversionEngine {
    struct Conversion: Equatable {
        let title: String      // "9:00 AM" or "Fri 9:00 AM" when the target day differs from local today
        let subtitle: String   // "12:00 PM EDT in New York → Your time (PDT)"
        let copyText: String   // "9:00 AM PDT"
        let copyLine: String?  // "12:00 PM EDT → 9:00 AM PDT"; nil for current-time rows
        let isoText: String    // "2026-09-12T01:00:00Z"
    }

    static func recognizes(_ query: String) -> Bool {
        parse(query) != nil
    }

    static func conversions(for query: String, now: Date, local: TimeZone) -> [Conversion] {
        guard let parsed = parse(query) else { return [] }
        switch parsed {
        case let .now(zoneToken):
            return nowRows(zoneToken: zoneToken, now: now, local: local)
        case let .convert(spec):
            return convertRows(spec: spec, now: now, local: local)
        }
    }

    // MARK: - Parsing

    private enum ParsedQuery {
        case now(zoneToken: String?)
        case convert(TimeSpec)
    }

    private struct TimeSpec {
        var hour: Int
        var minute: Int
        var sourceToken: String
        var hasExplicitTargets = false
        var targetTokens: [String] = []
        var dayOffset: Int?
        var weekday: Int? // Calendar weekday: 1 = Sunday
    }

    private static let nowWords: Set<String> = [
        "now", "time", "the time", "current time", "what time is it",
        "what time is it now", "what time is it right now", "what's the time"
    ]
    private static let nowPrefixes = [
        "now in ", "time in ", "current time in ", "the time in ", "what time is it in "
    ]
    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7
    ]

    private static let timeSpecRegex = try? NSRegularExpression(
        pattern: #"^(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+(.+)$"#
    )
    private static let clockRegex = try? NSRegularExpression(
        pattern: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#
    )
    private static let dayModifierRegex = try? NSRegularExpression(
        pattern: #"\s+(today|tomorrow|yesterday|sunday|monday|tuesday|wednesday|thursday|friday|saturday)$"#
    )

    private static func parse(_ raw: String) -> ParsedQuery? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        text = text.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        text = text.components(separatedBy: .whitespaces).filter { $0.isEmpty == false }.joined(separator: " ")

        if nowWords.contains(text) { return .now(zoneToken: nil) }
        for prefix in nowPrefixes where text.hasPrefix(prefix) {
            let token = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return token.isEmpty ? nil : .now(zoneToken: token)
        }
        if text.hasPrefix("at ") { text = String(text.dropFirst(3)) }
        if text.hasSuffix(" time") {
            let token = String(text.dropLast(5)).trimmingCharacters(in: .whitespaces)
            if token.isEmpty == false { return .now(zoneToken: token) }
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = timeSpecRegex?.firstMatch(in: text, range: fullRange),
              let timeRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text),
              let (hour, minute) = clockTime(String(text[timeRange])) else { return nil }

        var spec = TimeSpec(hour: hour, minute: minute, sourceToken: "")
        var rest = String(text[restRange]).trimmingCharacters(in: .whitespaces)

        // A trailing day/weekday modifies the source regardless of position.
        if let modMatch = dayModifierRegex?.firstMatch(in: rest, range: NSRange(rest.startIndex..<rest.endIndex, in: rest)),
           let modRange = Range(modMatch.range(at: 1), in: rest),
           let stripRange = Range(modMatch.range, in: rest) {
            let word = String(rest[modRange])
            switch word {
            case "today": spec.dayOffset = 0
            case "tomorrow": spec.dayOffset = 1
            case "yesterday": spec.dayOffset = -1
            default: spec.weekday = weekdays[word]
            }
            rest = String(rest[..<stripRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        if rest.hasPrefix("in ") { rest = String(rest.dropFirst(3)) }
        while rest.hasSuffix(" to") || rest.hasSuffix(" in") || rest.hasSuffix(",") {
            rest = String(rest.dropLast(rest.hasSuffix(",") ? 1 : 3)).trimmingCharacters(in: .whitespaces)
        }

        if let split = rest.range(of: " to ") ?? rest.range(of: " in ") {
            spec.sourceToken = String(rest[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
            spec.hasExplicitTargets = true
            spec.targetTokens = rest[split.upperBound...]
                .replacingOccurrences(of: " and ", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.isEmpty == false }
        } else {
            spec.sourceToken = rest
        }
        return .convert(spec)
    }

    private static func clockTime(_ token: String) -> (Int, Int)? {
        if token == "noon" { return (12, 0) }
        if token == "midnight" { return (0, 0) }
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = clockRegex?.firstMatch(in: token, range: range) else { return nil }
        guard let hour = Int(String(token[Range(match.range(at: 1), in: token)!])) else { return nil }
        let minute = Range(match.range(at: 2), in: token).flatMap { Int(String(token[$0])) } ?? 0
        guard minute <= 59 else { return nil }
        if let meridiemRange = Range(match.range(at: 3), in: token) {
            let meridiem = token[meridiemRange]
            guard (1...12).contains(hour) else { return nil }
            let base = hour % 12
            return meridiem == "pm" ? (base + 12, minute) : (base, minute)
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
        } else if let offset = spec.dayOffset {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { return nil }
            anchor = day.addingTimeInterval(-1)
        } else {
            anchor = now
        }
        return calendar.nextDate(after: anchor, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    // MARK: - Rendering

    private static func convertRows(spec: TimeSpec, now: Date, local: TimeZone) -> [Conversion] {
        let source: TimeZoneResolver.ResolvedZone
        if spec.sourceToken.isEmpty {
            source = TimeZoneResolver.ResolvedZone(zone: local, name: "Your time")
        } else {
            guard let resolved = TimeZoneResolver.resolve(spec.sourceToken) else { return [] }
            source = resolved
        }

        let targets: [TimeZoneResolver.ResolvedZone]
        if spec.hasExplicitTargets {
            let resolved = spec.targetTokens.compactMap(TimeZoneResolver.resolve)
            guard resolved.isEmpty == false else { return [] }
            targets = resolved
        } else {
            var list = [TimeZoneResolver.ResolvedZone(zone: local, name: "Your time")]
            if local != utcZone { list.append(TimeZoneResolver.ResolvedZone(zone: utcZone, name: "UTC")) }
            targets = list
        }

        guard let instant = instant(for: spec, in: source.zone, after: now) else { return [] }
        return targets.map { render(instant: instant, source: source, target: $0, now: now, local: local) }
    }

    private static func nowRows(zoneToken: String?, now: Date, local: TimeZone) -> [Conversion] {
        guard let token = zoneToken else {
            var rows = [
                renderNow(instant: now, zone: TimeZoneResolver.ResolvedZone(zone: local, name: "Your time"), now: now, local: local),
                renderNow(instant: now, zone: TimeZoneResolver.ResolvedZone(zone: utcZone, name: "UTC"), now: now, local: local)
            ]
            rows.append(Conversion(
                title: String(Int(now.timeIntervalSince1970)),
                subtitle: "Unix timestamp",
                copyText: String(Int(now.timeIntervalSince1970)),
                copyLine: nil,
                isoText: isoString(now)
            ))
            return rows
        }
        guard let zone = TimeZoneResolver.resolve(token) else { return [] }
        return [renderNow(instant: now, zone: zone, now: now, local: local)]
    }

    private static func renderNow(instant: Date, zone: TimeZoneResolver.ResolvedZone, now: Date, local: TimeZone) -> Conversion {
        let time = timeString(instant, in: zone.zone)
        let prefix = dayPrefix(instant: instant, zone: zone.zone, now: now, local: local)
        let abbreviation = zone.abbreviation(for: instant)
        return Conversion(
            title: prefix + time,
            subtitle: "\(zone.name) (\(abbreviation)) · \(offsetDescription(of: zone.zone, at: instant, relativeTo: local))",
            copyText: "\(time) \(abbreviation)",
            copyLine: nil,
            isoText: isoString(instant)
        )
    }

    private static func render(
        instant: Date, source: TimeZoneResolver.ResolvedZone, target: TimeZoneResolver.ResolvedZone, now: Date, local: TimeZone
    ) -> Conversion {
        let sourceTime = timeString(instant, in: source.zone)
        let targetTime = timeString(instant, in: target.zone)
        let sourceAbbrev = source.abbreviation(for: instant)
        let targetAbbrev = target.abbreviation(for: instant)

        let sourcePrefix = dayPrefix(instant: instant, zone: source.zone, now: now, local: local)
        let left = source.zone == local
            ? "\(sourcePrefix)\(sourceTime) \(sourceAbbrev)"
            : "\(sourcePrefix)\(sourceTime) \(sourceAbbrev) in \(source.name)"
        let right = target.zone == local ? "Your time (\(targetAbbrev))" : "\(target.name) (\(targetAbbrev))"

        return Conversion(
            title: dayPrefix(instant: instant, zone: target.zone, now: now, local: local) + targetTime,
            subtitle: "\(left) → \(right)",
            copyText: "\(targetTime) \(targetAbbrev)",
            copyLine: "\(sourcePrefix)\(sourceTime) \(sourceAbbrev) → \(targetTime) \(targetAbbrev)",
            isoText: isoString(instant)
        )
    }

    // MARK: - Formatters (created per call: DateFormatter is not Sendable)

    private static let utcZone = TimeZone(identifier: "Etc/UTC")!

    private static func timeString(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func dayText(_ date: Date, in zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "Fri " when the instant's day in `zone` differs from local today, else "".
    private static func dayPrefix(instant: Date, zone: TimeZone, now: Date, local: TimeZone) -> String {
        guard dayText(instant, in: zone, format: "yyyy-MM-dd") != dayText(now, in: local, format: "yyyy-MM-dd") else { return "" }
        return dayText(instant, in: zone, format: "EEE") + " "
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
