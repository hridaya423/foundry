import Foundation

enum WebSearch {
    private static let maximumResponseBytes = 1_048_576
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: WebSearchSessionDelegate(), delegateQueue: nil)
    }()

    static func search(_ query: String) async -> String {
        let results = await results(query)
        guard results.isEmpty == false else { return "No web results found for \"\(query)\"." }
        return formatted(results)
    }

    static func results(_ query: String) async -> [WebSearchResult] {
        let braveResults = await braveResults(query)
        if braveResults.isEmpty == false { return Array(braveResults.filter(WebSearchURLPolicy.isAllowed).prefix(4)) }

        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Foundry/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await boundedData(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, isHTMLResponse(response) else { return [] }
            return Array(WebSearchHTMLParser.parse(data).filter(WebSearchURLPolicy.isAllowed).prefix(4))
        } catch {
            return []
        }
    }

    static func enrichAll(_ results: [WebSearchResult], limit: Int) async -> [WebSearchEvidence] {
        let selected = Array(results.prefix(max(limit, 0)))
        return await withTaskGroup(of: WebSearchEvidence.self, returning: [WebSearchEvidence].self) { group in
            for result in selected {
                group.addTask { await enrich(result) }
            }
            var enriched: [WebSearchEvidence] = []
            for await evidence in group { enriched.append(evidence) }
            let order = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($1.url, $0) })
            return enriched.sorted { (order[$0.result.url] ?? .max) < (order[$1.result.url] ?? .max) }
        }
    }

    static func enrich(_ result: WebSearchResult) async -> WebSearchEvidence {
        guard WebSearchURLPolicy.isAllowed(result.url), let url = URL(string: result.url) else {
            return WebSearchEvidence(result: result, pageText: "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Foundry/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await boundedData(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, isHTMLResponse(response) else {
                return WebSearchEvidence(result: result, pageText: "")
            }
            let pageText = WebPageTextExtractor.extract(data: data, limit: 2400)
            return WebSearchEvidence(result: result, pageText: pageText)
        } catch {
            return WebSearchEvidence(result: result, pageText: "")
        }
    }

    static func formatted(_ evidence: [WebSearchEvidence], maxResults: Int = 8, summaryLimit: Int = 180, pageLimit: Int = 900) -> String {
        evidence.prefix(maxResults).enumerated().map { index, item in
            let result = item.result
            let title = String(result.title.prefix(160))
            let summary = String(result.summary.prefix(summaryLimit))
            let pageText = String(item.pageText.prefix(pageLimit))
            let pageSection = pageText.isEmpty ? "" : "\nPage excerpt: \(pageText)"
            return "\(index + 1). \(title)\n\(summary)\(pageSection)\nSource: \(result.url)"
        }.joined(separator: "\n\n")
    }

    private static func braveResults(_ query: String) async -> [WebSearchResult] {
        var components = URLComponents(string: "https://search.brave.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: "web")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await boundedData(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, isHTMLResponse(response) else { return [] }
            return BraveSearchHTMLParser.parse(data).filter(WebSearchURLPolicy.isAllowed)
        } catch {
            return []
        }
    }

    private static func boundedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(maximumResponseBytes, 64 * 1024))
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw WebSearchError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    private static func isHTMLResponse(_ response: URLResponse) -> Bool {
        guard let mimeType = response.mimeType?.lowercased() else { return true }
        return mimeType == "text/html" || mimeType == "application/xhtml+xml" || mimeType == "text/plain"
    }

    static func formatted(_ results: [WebSearchResult], maxResults: Int = 3, summaryLimit: Int = 320) -> String {
        results.prefix(maxResults).enumerated().map { index, result in
            let title = String(result.title.prefix(160))
            let summary = String(result.summary.prefix(summaryLimit))
            return "\(index + 1). \(title)\n\(summary)\nSource: \(result.url)"
        }.joined(separator: "\n\n")
    }
}

private enum WebSearchError: Error {
    case responseTooLarge
}

private final class WebSearchSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct WebSearchResult: Equatable {
    let title: String
    let url: String
    let summary: String
}

struct WebSearchEvidence: Equatable {
    let result: WebSearchResult
    let pageText: String
}

enum WebSearchURLPolicy {
    static func isAllowed(_ result: WebSearchResult) -> Bool {
        isAllowed(result.url)
    }

    static func isAllowed(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host?.lowercased() else { return false }
        guard host != "localhost", host.hasSuffix(".localhost") == false, host.hasSuffix(".local") == false else { return false }
        if let ipv4 = IPv4Address(host) {
            return ipv4.isPublic
        }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return false
        }
        return true
    }
}

private struct IPv4Address {
    let octets: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".")
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        self.octets = octets
    }

    var isPublic: Bool {
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (172, 16...31), (100, 64...127):
            return false
        default:
            return true
        }
    }
}

enum WebSearchQuerySet {
    static func validated(_ candidates: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate -> String? in
            let query = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.isEmpty == false, isURL(query) == false else { return nil }
            let normalized = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(normalized).inserted ? query : nil
        }.prefix(max(maxCount, 0)).map { $0 }
    }

    private static func isURL(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("http://") || normalized.hasPrefix("https://") || normalized.hasPrefix("www.")
    }
}

enum GroundedAnswerFormatter {
    static func format(answer: String, details: [String], sourceURLs: [String], results: [WebSearchResult], detailed: Bool) -> String {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let directAnswer = detailed ? trimmedAnswer : trimmedAnswer.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmedAnswer
        var sections = [directAnswer]
        if detailed {
            let supportedDetails = details
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false && $0 != directAnswer }
            if supportedDetails.isEmpty == false { sections.append(supportedDetails.map { "• \($0)" }.joined(separator: "\n")) }
        }
        let allowedURLs = Set(results.map(\.url))
        var sources = sourceURLs.filter { allowedURLs.contains($0) }
        if sources.isEmpty { sources = Array(results.prefix(2).map(\.url)) }
        sources = Array(sources.reduce(into: [String]()) { unique, source in
            if unique.contains(source) == false { unique.append(source) }
        }.prefix(3))
        if sources.isEmpty == false { sections.append("Sources:\n" + sources.map { "• \($0)" }.joined(separator: "\n")) }
        return sections.filter { $0.isEmpty == false }.joined(separator: "\n\n")
    }
}

struct GroundedListItem: Equatable {
    let name: String
    let sourceURL: String
}

enum GroundedListFormatter {
    static func format(items: [GroundedListItem], results: [WebSearchResult], requestedCount: Int, pageTextByURL: [String: String] = [:]) -> String {
        let resultsByURL = results.reduce(into: [String: WebSearchResult]()) { indexed, result in
            if indexed[result.url] == nil { indexed[result.url] = result }
        }
        let limit = min(max(requestedCount, 1), 5)
        var seenNames = Set<String>()
        let verified = items.compactMap { item -> GroundedListItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let result = resultsByURL[item.sourceURL], name.isEmpty == false else { return nil }
            let normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let evidence = "\(result.title) \(result.summary) \(pageTextByURL[result.url] ?? "")".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard evidence.contains(normalizedName), seenNames.insert(normalizedName).inserted else { return nil }
            return GroundedListItem(name: name, sourceURL: item.sourceURL)
        }.prefix(limit)

        guard verified.isEmpty == false else {
            return "I couldn't identify specific items explicitly named by the live search results."
        }
        let heading = verified.count < limit
            ? "I could only verify \(verified.count) of the requested \(limit) items:"
            : "Latest verified items (checked live):"
        let rows = verified.enumerated().map { index, item in
            let result = resultsByURL[item.sourceURL]
            let summary = result?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = summary.isEmpty ? "" : "\n   \(String(summary.prefix(240)))"
            return "\(index + 1). **\(item.name)**\(detail)\n   ([source](\(item.sourceURL)))"
        }
        return ([heading] + rows).joined(separator: "\n")
    }
}

enum GroundedWebFallbackFormatter {
    static func format(results: [WebSearchResult], wantsList: Bool, requestedItemCount: Int) -> String {
        let limit = wantsList ? min(max(requestedItemCount, 1), 5) : 1
        let selected = results.prefix(limit)
        guard selected.isEmpty == false else { return "I couldn't verify that with live web sources." }
        let heading = wantsList ? "I found these verified source results:" : "Closest verified source result:"
        let rows = selected.enumerated().map { index, result in
            let summary = String(result.summary.prefix(240))
            return "\(index + 1). **\(result.title)**\n\(summary) ([source](\(result.url)))"
        }
        return ([heading] + rows).joined(separator: "\n")
    }
}

enum WebSearchHTMLParser {
    static func parse(_ data: Data) -> [WebSearchResult] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let links = matches(#"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: html)
        let snippets = matches(#"class="result__snippet"[^>]*>(.*?)</(?:a|div)>"#, in: html)
        return links.enumerated().compactMap { index, fields in
            guard fields.count == 2, let url = destinationURL(fields[0]) else { return nil }
            return WebSearchResult(
                title: clean(fields[1]),
                url: url,
                summary: index < snippets.count ? clean(snippets[index].last ?? "") : ""
            )
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private static func destinationURL(_ rawValue: String) -> String? {
        let decoded = rawValue.replacingOccurrences(of: "&amp;", with: "&")
        let absolute = decoded.hasPrefix("//") ? "https:\(decoded)" : decoded
        guard let components = URLComponents(string: absolute) else { return nil }
        if let destination = components.queryItems?.first(where: { $0.name == "uddg" })?.value { return destination }
        guard components.host?.contains("duckduckgo.com") != true else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return components.url?.absoluteString
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BraveSearchHTMLParser {
    static func parse(_ data: Data) -> [WebSearchResult] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let pattern = #"\{title:\"((?:\\.|[^\"])*)\",url:\"((?:\\.|[^\"])*)\",full_title:(?:void 0|\"(?:\\.|[^\"])*\"),description:\"((?:\\.|[^\"])*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seenURLs = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges == 4,
                  let titleRange = Range(match.range(at: 1), in: html),
                  let urlRange = Range(match.range(at: 2), in: html),
                  let summaryRange = Range(match.range(at: 3), in: html),
                  let title = decode(String(html[titleRange])),
                  let url = decode(String(html[urlRange])),
                  let summary = decode(String(html[summaryRange])),
                   WebSearchURLPolicy.isAllowed(url),
                  seenURLs.insert(url).inserted else { return nil }
            return WebSearchResult(title: clean(title), url: url, summary: clean(summary))
        }
    }

    private static func decode(_ value: String) -> String? {
        guard let data = "\"\(value)\"".data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WebPageTextExtractor {
    static func extract(data: Data, limit: Int) -> String {
        guard let html = String(data: data, encoding: .utf8), limit > 0 else { return "" }
        let text = html
            .replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(limit))
    }
}
