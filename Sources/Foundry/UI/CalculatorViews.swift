import Foundation
import SwiftUI

struct AnswerCard: View {
    let result: CommandResult
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }

    struct Side: Equatable {
        let value: String
        var caption: String?
    }

    struct Content: Equatable {
        let label: LocalizedStringKey
        let left: Side
        let right: Side
        let separator: String
        var note: String?
    }

    static func content(for result: CommandResult) -> Content {
        switch result.payload {
        case let .time(from, to):
            return Content(label: "Time", left: Side(value: from.time, caption: from.caption), right: Side(value: to.time, caption: to.caption),
                separator: "→")
        case let .date(from, to):
            return Content(label: "Date", left: Side(value: from.value, caption: from.caption), right: Side(value: to.value, caption: to.caption),
                separator: "→")
        case let .calculationConversion(expression, value):
            let note = result.subtitle.flatMap { $0.hasPrefix(expression + " · ") ? String($0.dropFirst(expression.count + 3)) : nil }
            return Content(label: "Conversion", left: split(expression), right: split(value), separator: "→", note: note)
        default:
            return Content(label: "Calculator", left: Side(value: result.subtitle ?? ""), right: Side(value: result.title), separator: "=")
        }
    }

    static func split(_ value: String) -> Side {
        guard let space = value.firstIndex(of: " ") else { return Side(value: value) }
        let caption = value[value.index(after: space)...]
        guard caption.contains(where: \.isNumber) == false else { return Side(value: value) }
        return Side(value: String(value[..<space]), caption: String(caption))
    }

    private var content: Content { Self.content(for: result) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            equation
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(content.label)
            Spacer()
            if let note = content.note {
                Text(note)
            }
        }
        .font(FoundryTheme.micro)
        .foregroundStyle(FoundryTheme.textQuaternary)
        .padding(.horizontal, 8)
    }

    private var equation: some View {
        HStack(spacing: 0) {
            AnswerPane(side: content.left)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(FoundryTheme.fillTint)
                    .frame(width: 1)

                Text(content.separator)
                    .font(FoundryTheme.title)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 72, height: 54)

                Rectangle()
                    .fill(FoundryTheme.fillTint)
                    .frame(width: 1)
            }

            AnswerPane(side: content.right, alternatives: alternatives, executeAlternative: executeAlternative)
        }
        .frame(height: FoundryTheme.Control.preview)
        .background(FoundryTheme.fillHover)
        .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                .stroke(FoundryTheme.fillTint, lineWidth: 1)
        )
    }
}

struct AnswerPane: View {
    let side: AnswerCard.Side
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Text(side.value)
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption = side.caption {
                if alternatives.isEmpty {
                    captionLabel(caption, showsChevron: false)
                } else {
                    Menu {
                        ForEach(alternatives, id: \.id) { alternative in
                            Button(AnswerCard.split(alternative.title).caption ?? alternative.title) {
                                withAnimation(reduceMotion ? nil : FoundryTheme.Motion.state) {
                                    if let code = currencyCode(in: alternative.title) {
                                        LocalStateStore.shared.set(\.preferredCurrencyQuote, code)
                                    }
                                    executeAlternative(alternative)
                                }
                            }
                        }
                    } label: {
                        captionLabel(caption, showsChevron: true)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }

    private func captionLabel(_ caption: String, showsChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Text(caption)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(FoundryTheme.Glyph.xs)
            }
        }
        .font(FoundryTheme.body)
        .foregroundStyle(FoundryTheme.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: FoundryTheme.Control.mini)
        .background(FoundryTheme.fillTint)
        .clipShape(Capsule())
    }

    private func currencyCode(in value: String) -> String? {
        guard let unit = AnswerCard.split(value).caption else { return nil }
        switch unit {
        case "US Dollar": return "USD"
        case "Euro": return "EUR"
        case "British Pound": return "GBP"
        case "Indian Rupee": return "INR"
        case "Japanese Yen": return "JPY"
        case "Canadian Dollar": return "CAD"
        case "Australian Dollar": return "AUD"
        case "Swiss Franc": return "CHF"
        case "Chinese Yuan": return "CNY"
        default: return nil
        }
    }
}

struct CalculatorUseWithHeader: View {
    let query: String

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Use “\(trimmedQuery)” with…")
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
