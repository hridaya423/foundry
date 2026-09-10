import Foundation
import SwiftUI
import FoundryDomain

struct CalculatorResultCard: View {
    let result: CommandResult
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }

    private var expression: String {
        result.subtitle ?? "Calculation"
    }

    private var separator: String {
        "→"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            equation
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Calculator")
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var equation: some View {
        HStack(spacing: 0) {
            CalculatorValuePane(value: expression)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                Text(separator)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 72, height: 54)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }

            CalculatorValuePane(value: result.title, alternatives: alternatives, executeAlternative: executeAlternative)
        }
        .frame(height: 112)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct CalculatorValuePane: View {
    let value: String
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var splitValue: (amount: String, unit: String?) {
        split(value)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(splitValue.amount)
                .font(FoundryTheme.display(size: 36, weight: .bold))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            if let unit = splitValue.unit {
                Menu {
                    ForEach(alternatives, id: \.id) { alternative in
                        Button(split(alternative.title).unit ?? alternative.title) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                if let code = currencyCode(in: alternative.title) {
                                    UserDefaults.standard.set(code, forKey: "preferredCurrencyQuote")
                                }
                                executeAlternative(alternative)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(unit)
                        if alternatives.isEmpty == false {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }

    private func split(_ value: String) -> (amount: String, unit: String?) {
        guard let space = value.firstIndex(of: " ") else { return (value, nil) }
        return (String(value[..<space]), String(value[value.index(after: space)...]))
    }

    private func currencyCode(in value: String) -> String? {
        guard let unit = split(value).unit else { return nil }
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
            Text("Use \"\(trimmedQuery)\" with...")
                .font(FoundryTheme.body(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.mutedText)

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
