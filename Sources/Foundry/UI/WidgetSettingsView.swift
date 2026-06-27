import AppKit
import SwiftUI

struct WidgetSettingsView: View {
    @ObservedObject var board: WidgetBoardState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                activeSection
                configSection
                availableSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "On the Board")

            if board.config.enabled.isEmpty {
                Text("No widgets yet. Add some below.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            } else {
                Text("Showing up to \(WidgetBoardConfig.maxEnabled) widgets on Home.")
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 4)

                ForEach(Array(board.config.enabled.enumerated()), id: \.element) { index, kind in
                    ActiveWidgetRow(
                        kind: kind,
                        isFirst: index == 0,
                        isLast: index == board.config.enabled.count - 1,
                        moveUp: { board.moveUp(kind) },
                        moveDown: { board.moveDown(kind) },
                        remove: { board.remove(kind) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var configSection: some View {
        if board.config.enabled.contains(.weather) || board.config.enabled.contains(.stock) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader(title: "Widget Options")

                if board.config.enabled.contains(.weather) {
                    ConfigFieldRow(
                        symbol: "cloud.sun",
                        title: "Weather City",
                        placeholder: "City name",
                        initialValue: board.config.weatherCity,
                        commit: { board.setWeatherCity($0) }
                    )
                }

                if board.config.enabled.contains(.stock) {
                    ConfigFieldRow(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Stock Ticker",
                        placeholder: "e.g. AAPL",
                        initialValue: board.config.stockSymbol,
                        commit: { board.setStockSymbol($0) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        if board.config.available.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader(title: "Available")

                if board.isFull {
                    Text("Remove a widget to add another.")
                        .font(FoundryTheme.body(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                } else {
                    ForEach(board.config.available) { kind in
                        AvailableWidgetRow(kind: kind, add: { board.add(kind) })
                    }
                }
            }
        }
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(FoundryTheme.body(size: 11, weight: .semibold))
            .foregroundStyle(FoundryTheme.faintText)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }
}

private struct WidgetGlyph: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(width: 34, height: 34)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
            )
    }
}

private struct ActiveWidgetRow: View {
    let kind: WidgetKind
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            WidgetGlyph(symbol: kind.symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text(kind.summary)
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                IconButton(symbol: "chevron.up", action: moveUp)
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)
                IconButton(symbol: "chevron.down", action: moveDown)
                    .disabled(isLast)
                    .opacity(isLast ? 0.3 : 1)
                IconButton(symbol: "minus", action: remove, tint: Color.red.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0.04))
        )
        .onHover { isHovering = $0 }
    }
}

private struct AvailableWidgetRow: View {
    let kind: WidgetKind
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 12) {
                WidgetGlyph(symbol: kind.symbol)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(kind.summary)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.06 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let action: () -> Void
    var tint: Color = FoundryTheme.secondaryText

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ConfigFieldRow: View {
    let symbol: String
    let title: String
    let placeholder: String
    let initialValue: String
    let commit: (String) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            WidgetGlyph(symbol: symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .onSubmit { commit(text) }
            }

            Spacer()

            Button(action: { commit(text) }) {
                Text("Save")
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .onAppear { text = initialValue }
    }
}
