import Foundation
import FoundryDomain

final class TimeConversionProvider: CommandProvider {
    let id = "foundry.time"

    private let now: @Sendable () -> Date
    private let localZone: @Sendable () -> TimeZone

    init(now: @escaping @Sendable () -> Date = { Date() }, localZone: @escaping @Sendable () -> TimeZone = { .current }) {
        self.now = now
        self.localZone = localZone
    }

    func isActive(for query: String) -> Bool {
        TimeConversionEngine.recognizes(query)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let conversions = TimeConversionEngine.conversions(for: request.query, now: now(), local: localZone())
        return conversions.enumerated().map { index, conversion in
            let resultID = "time.\(index).\(SearchScoring.normalize(request.query))"
            var actions: [CommandAction] = []
            if let copyLine = conversion.copyLine {
                actions.append(CommandAction(id: "\(resultID).copy-line", title: "Copy Conversion", kind: .copyToClipboard(copyLine)))
            }
            actions.append(CommandAction(id: "\(resultID).copy-iso", title: "Copy ISO 8601", kind: .copyToClipboard(conversion.isoText)))
            actions.append(CommandAction(id: "\(resultID).paste", title: "Paste", kind: .pasteText(conversion.copyText)))
            return CommandResult(
                id: resultID,
                title: conversion.title,
                subtitle: conversion.subtitle,
                icon: CommandIcon(fallback: "◷", systemName: "clock"),
                searchKeywords: [request.query],
                primaryAction: CommandAction(id: "\(resultID).copy", title: "Copy", kind: .copyToClipboard(conversion.copyText)),
                secondaryActions: actions
            )
        }
    }
}
