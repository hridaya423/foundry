import Foundation

/// Resolves a user-typed place or abbreviation to an IANA `TimeZone`.
/// Curated names win over the derived city index; `TimeZone(abbreviation:)` is
/// intentionally never used for lookup because its table is incomplete and
/// ambiguous. Typing choices: IST is India, CST is US Central, BST is London.
///
/// Each curated zone carries standard/daylight abbreviations because Apple's
/// `abbreviation(for:)` only knows US-style names and falls back to "GMT+9"
/// for zones like Tokyo — the pair keeps labels like "JST"/"CEST" honest while
/// still reporting the abbreviation actually in effect on the date.
enum TimeZoneResolver {
    struct ResolvedZone: Equatable, Sendable {
        let zone: TimeZone
        let name: String
        let standardAbbrev: String?
        let daylightAbbrev: String?

        init(zone: TimeZone, name: String, standardAbbrev: String? = nil, daylightAbbrev: String? = nil) {
            self.zone = zone
            self.name = name
            self.standardAbbrev = standardAbbrev
            self.daylightAbbrev = daylightAbbrev
        }

        func abbreviation(for date: Date) -> String {
            if let standardAbbrev {
                if zone.isDaylightSavingTime(for: date), let daylightAbbrev { return daylightAbbrev }
                return standardAbbrev
            }
            return zone.abbreviation(for: date) ?? zone.identifier.split(separator: "/").last.map(String.init) ?? "GMT"
        }

        static func == (lhs: ResolvedZone, rhs: ResolvedZone) -> Bool {
            lhs.zone == rhs.zone && lhs.name == rhs.name
        }
    }

    static func resolve(_ raw: String) -> ResolvedZone? {
        let key = normalize(raw)
        guard key.isEmpty == false else { return nil }

        if let match = named[key], let zone = TimeZone(identifier: match.identifier) {
            return ResolvedZone(zone: zone, name: match.name, standardAbbrev: match.std, daylightAbbrev: match.dst)
        }
        if let match = cityIndex[key], let zone = TimeZone(identifier: match.identifier) {
            return ResolvedZone(zone: zone, name: match.name)
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: .whitespaces)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Curated aliases and abbreviations

    private struct NamedZone {
        let identifier: String
        let name: String
        let std: String
        let dst: String?
    }

    private static let named: [String: NamedZone] = {
        var table: [String: NamedZone] = [:]
        func add(_ identifier: String, _ name: String, _ std: String, _ dst: String? = nil, _ keys: [String]) {
            for key in keys { table[normalize(key)] = NamedZone(identifier: identifier, name: name, std: std, dst: dst) }
        }

        // US / Canada zones and common cities
        add("America/New_York", "Eastern Time", "EST", "EDT", ["et", "est", "edt", "eastern", "eastern time"])
        add("America/Chicago", "Central Time", "CST", "CDT", ["ct", "cst", "cdt", "central", "central time"])
        add("America/Denver", "Mountain Time", "MST", "MDT", ["mt", "mst", "mdt", "mountain", "mountain time"])
        add("America/Los_Angeles", "Pacific Time", "PST", "PDT", ["pt", "pst", "pdt", "pacific", "pacific time"])
        add("America/Anchorage", "Alaska Time", "AKST", "AKDT", ["akst", "akdt", "alaska"])
        add("Pacific/Honolulu", "Hawaii", "HST", nil, ["hst", "hawaii", "honolulu"])
        add("America/Phoenix", "Phoenix", "MST", nil, ["phoenix", "arizona"])

        add("America/Los_Angeles", "San Francisco", "PST", "PDT", ["sf", "san francisco", "bay area", "silicon valley", "san jose", "oakland"])
        add("America/Los_Angeles", "Los Angeles", "PST", "PDT", ["la", "los angeles"])
        add("America/Los_Angeles", "Seattle", "PST", "PDT", ["seattle", "portland"])
        add("America/Los_Angeles", "Vancouver", "PST", "PDT", ["vancouver"])
        add("America/New_York", "New York", "EST", "EDT", ["ny", "nyc", "new york", "new york city", "manhattan", "brooklyn"])
        add("America/New_York", "Boston", "EST", "EDT", ["boston"])
        add("America/New_York", "Washington DC", "EST", "EDT", ["dc", "washington", "washington dc"])
        add("America/New_York", "Miami", "EST", "EDT", ["miami"])
        add("America/New_York", "Atlanta", "EST", "EDT", ["atlanta"])
        add("America/Toronto", "Toronto", "EST", "EDT", ["toronto"])
        add("America/Toronto", "Montreal", "EST", "EDT", ["montreal"])
        add("America/Chicago", "Chicago", "CST", "CDT", ["chicago"])
        add("America/Chicago", "Austin", "CST", "CDT", ["austin", "dallas", "houston", "san antonio"])
        add("America/Chicago", "Minneapolis", "CST", "CDT", ["minneapolis"])
        add("America/Mexico_City", "Mexico City", "CST", nil, ["mexico city", "cdmx"])
        add("America/Denver", "Denver", "MST", "MDT", ["denver", "boulder", "salt lake city"])
        add("America/Sao_Paulo", "São Paulo", "BRT", nil, ["sao paulo", "brazil"])
        add("America/Argentina/Buenos_Aires", "Buenos Aires", "GMT-3", nil, ["buenos aires", "argentina"])
        add("America/Santiago", "Santiago", "CLT", "CLST", ["santiago", "chile"])
        add("America/Bogota", "Bogotá", "GMT-5", nil, ["bogota", "colombia"])
        add("America/Lima", "Lima", "GMT-5", nil, ["lima", "peru"])

        // Europe
        add("Europe/London", "London", "GMT", "BST", ["london", "uk", "britain", "england", "bst"])
        add("Europe/Dublin", "Dublin", "GMT", "IST", ["dublin", "ireland"])
        add("Europe/Lisbon", "Lisbon", "WET", "WEST", ["lisbon", "wet", "west", "portugal"])
        add("Europe/Paris", "Paris", "CET", "CEST", ["paris", "france", "cet", "cest", "central europe"])
        add("Europe/Berlin", "Berlin", "CET", "CEST", ["berlin", "germany"])
        add("Europe/Amsterdam", "Amsterdam", "CET", "CEST", ["amsterdam", "netherlands"])
        add("Europe/Madrid", "Madrid", "CET", "CEST", ["madrid", "spain", "barcelona"])
        add("Europe/Rome", "Rome", "CET", "CEST", ["rome", "italy", "milan"])
        add("Europe/Zurich", "Zurich", "CET", "CEST", ["zurich", "geneva", "switzerland"])
        add("Europe/Stockholm", "Stockholm", "CET", "CEST", ["stockholm", "sweden"])
        add("Europe/Oslo", "Oslo", "CET", "CEST", ["oslo", "norway"])
        add("Europe/Copenhagen", "Copenhagen", "CET", "CEST", ["copenhagen", "denmark"])
        add("Europe/Vienna", "Vienna", "CET", "CEST", ["vienna", "austria"])
        add("Europe/Prague", "Prague", "CET", "CEST", ["prague", "czech"])
        add("Europe/Warsaw", "Warsaw", "CET", "CEST", ["warsaw", "poland"])
        add("Europe/Helsinki", "Helsinki", "EET", "EEST", ["helsinki", "finland", "eet", "eest"])
        add("Europe/Athens", "Athens", "EET", "EEST", ["athens", "greece"])
        add("Europe/Istanbul", "Istanbul", "GMT+3", nil, ["istanbul", "turkey"])
        add("Europe/Moscow", "Moscow", "MSK", nil, ["moscow", "msk"])

        // Asia / Middle East
        add("Asia/Tokyo", "Tokyo", "JST", nil, ["tokyo", "japan", "jst"])
        add("Asia/Seoul", "Seoul", "KST", nil, ["seoul", "korea", "kst"])
        add("Asia/Shanghai", "Beijing", "CST", nil, ["beijing", "shanghai", "china"])
        add("Asia/Hong_Kong", "Hong Kong", "HKT", nil, ["hong kong", "hongkong", "hkt"])
        add("Asia/Taipei", "Taipei", "CST", nil, ["taipei", "taiwan"])
        add("Asia/Singapore", "Singapore", "SGT", nil, ["singapore", "sgt"])
        add("Asia/Kolkata", "India", "IST", nil, ["india", "ist", "mumbai", "delhi", "bangalore", "bengaluru", "hyderabad", "chennai"])
        add("Asia/Dubai", "Dubai", "GST", nil, ["dubai", "uae", "abu dhabi"])
        add("Asia/Bangkok", "Bangkok", "ICT", nil, ["bangkok", "thailand"])
        add("Asia/Jakarta", "Jakarta", "WIB", nil, ["jakarta", "wib"])
        add("Asia/Manila", "Manila", "PHT", nil, ["manila", "philippines", "pht"])
        add("Asia/Jerusalem", "Tel Aviv", "IST", "IDT", ["tel aviv", "jerusalem", "israel"])
        add("Asia/Riyadh", "Riyadh", "GMT+3", nil, ["riyadh", "saudi arabia"])

        // Oceania / Africa
        add("Australia/Sydney", "Sydney", "AEST", "AEDT", ["sydney", "aest", "aedt", "melbourne", "canberra"])
        add("Australia/Brisbane", "Brisbane", "AEST", nil, ["brisbane"])
        add("Australia/Adelaide", "Adelaide", "ACST", "ACDT", ["adelaide", "acst", "acdt"])
        add("Australia/Perth", "Perth", "AWST", nil, ["perth", "awst"])
        add("Pacific/Auckland", "Auckland", "NZST", "NZDT", ["auckland", "new zealand", "nzst", "nzdt", "wellington"])
        add("Pacific/Fiji", "Fiji", "FJT", nil, ["fiji"])
        add("Africa/Cairo", "Cairo", "EET", "EEST", ["cairo", "egypt"])
        add("Africa/Lagos", "Lagos", "WAT", nil, ["lagos", "nigeria", "wat"])
        add("Africa/Nairobi", "Nairobi", "EAT", nil, ["nairobi", "kenya", "eat"])
        add("Africa/Johannesburg", "Johannesburg", "SAST", nil, ["johannesburg", "cape town", "south africa", "sast"])

        // Fixed reference zones
        add("Etc/UTC", "UTC", "UTC", nil, ["utc", "gmt", "zulu"])
        return table
    }()

    // MARK: - Derived IANA city index ("los angeles" -> America/Los_Angeles)

    private static let cityIndex: [String: (identifier: String, name: String)] = {
        var index: [String: (String, String)] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers.sorted() {
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = String(city).replacingOccurrences(of: "_", with: " ")
            let key = normalize(String(city))
            if key.isEmpty == false, index[key] == nil {
                index[key] = (identifier, name)
            }
            index[normalize(identifier)] = (identifier, name)
        }
        return index
    }()
}
