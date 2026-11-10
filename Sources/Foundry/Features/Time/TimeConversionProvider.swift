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
        TimeConversionEngine.recognizes(query) || dateAnswer(for: query) != nil
    }

    private func dateAnswer(for query: String) -> DateMath.Answer? {
        var calendar = Calendar.current
        calendar.timeZone = localZone()
        return DateMath.answer(for: query, now: now(), calendar: calendar)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        if let answer = dateAnswer(for: request.query) {
            let resultID = "date.\(SearchScoring.normalize(request.query))"
            return [CommandResult(
                id: resultID,
                title: answer.to.value,
                subtitle: "\(answer.from.value) \(answer.from.caption)",
                icon: CommandIcon(fallback: "▦", systemName: "calendar"),
                searchKeywords: [request.query],
                payload: .date(from: answer.from, to: answer.to),
                primaryAction: CommandAction(id: "\(resultID).copy", title: "Copy", behavior: CopyToClipboardAction(answer.copyText)),
                secondaryActions: [
                    answer.isoText.map { CommandAction(id: "\(resultID).copy-iso", title: "Copy ISO Date", behavior: CopyToClipboardAction($0)) },
                    CommandAction(id: "\(resultID).paste", title: "Paste", behavior: PasteTextAction(answer.copyText))
                ].compactMap { $0 }
            )]
        }
        let conversions = TimeConversionEngine.conversions(for: request.query, now: now(), local: localZone())
        return conversions.enumerated().map { index, conversion in
            let resultID = "time.\(index).\(SearchScoring.normalize(request.query))"
            var actions: [CommandAction] = []
            if let copyLine = conversion.copyLine {
                actions.append(CommandAction(id: "\(resultID).copy-line", title: "Copy Conversion", behavior: CopyToClipboardAction(copyLine)))
            }
            actions.append(CommandAction(id: "\(resultID).copy-iso", title: "Copy ISO 8601", behavior: CopyToClipboardAction(conversion.isoText)))
            actions.append(CommandAction(id: "\(resultID).paste", title: "Paste", behavior: PasteTextAction(conversion.copyText)))
            return CommandResult(
                id: resultID,
                title: conversion.title,
                subtitle: conversion.subtitle,
                icon: CommandIcon(fallback: "◷", systemName: "clock"),
                searchKeywords: [request.query],
                payload: .time(from: conversion.source, to: conversion.target),
                primaryAction: CommandAction(id: "\(resultID).copy", title: "Copy", behavior: CopyToClipboardAction(conversion.copyText)),
                secondaryActions: actions
            )
        }
    }
}
