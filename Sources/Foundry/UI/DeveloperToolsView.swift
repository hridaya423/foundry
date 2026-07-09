import SwiftUI

struct DeveloperToolsView: View {
    @ObservedObject var state: DeveloperToolsState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            toolSwitcher

            if state.selectedTool == .base {
                baseTool
            } else {
                bitTool
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back")
                        .font(FoundryTheme.body(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(FoundryTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()

            VStack(alignment: .leading, spacing: 1) {
                Text("Developer Tools")
                    .font(FoundryTheme.body(size: 17, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text(state.selectedTool == .base ? "Base conversion" : "Bit operations")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }

            Spacer()
        }
    }

    private var toolSwitcher: some View {
        HStack(spacing: 8) {
            toolButton(.base, subtitle: "Hex, binary, octal")
            toolButton(.bitwise, subtitle: "AND, OR, XOR, shifts")
        }
    }

    private func toolButton(_ tool: DeveloperToolsState.Tool, subtitle: String) -> some View {
        Button(action: { state.selectedTool = tool }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.rawValue)
                    .font(FoundryTheme.body(size: 13.5, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text(subtitle)
                    .font(FoundryTheme.body(size: 11.5, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(state.selectedTool == tool ? 0.10 : 0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(state.selectedTool == tool ? 0.10 : 0), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var baseTool: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Base Conversion",
                subtitle: "Use 255, 0xff, 0b1010, or 16 ff. Results also work directly in normal search."
            )

            DeveloperInputField(title: "Input", placeholder: "255 or 0xff", text: $state.baseInput)

            if let error = state.baseError {
                DeveloperErrorText(message: error)
            } else {
                resultRows(state.baseRows)
            }
        }
        .padding(18)
        .modifier(DeveloperPanelSurface())
    }

    private var bitTool: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Bit Operations",
                subtitle: "Use decimal or prefixed inputs like 0xff. Search also supports 5 & 3, 5 << 1, and not 5 8."
            )

            HStack(spacing: 8) {
                ForEach(DeveloperToolsState.BitOperation.allCases) { operation in
                    DeveloperChip(
                        title: operation.rawValue,
                        isSelected: state.bitOperation == operation,
                        action: { state.bitOperation = operation }
                    )
                }
            }

            HStack(spacing: 12) {
                DeveloperInputField(title: "Left", placeholder: "5", text: $state.bitLeftInput)
                if state.bitOperation == .not {
                    DeveloperInputField(title: "Mask Width", placeholder: "8", text: $state.bitWidthInput)
                } else {
                    DeveloperInputField(title: state.bitOperation == .shiftLeft || state.bitOperation == .shiftRight ? "Shift" : "Right", placeholder: "3", text: $state.bitRightInput)
                }
            }

            if let error = state.bitError {
                DeveloperErrorText(message: error)
            } else {
                if state.bitExpression.isEmpty == false {
                    Text(state.bitExpression)
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                resultRows(state.bitRows)
            }
        }
        .padding(18)
        .modifier(DeveloperPanelSurface())
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FoundryTheme.body(size: 16, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
            Text(subtitle)
                .font(FoundryTheme.body(size: 12.5, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
        }
    }

    private func resultRows(_ rows: [DeveloperToolsState.OutputRow]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(FoundryTheme.body(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.faintText)
                            .tracking(0.4)
                        Text(row.value)
                            .font(FoundryTheme.body(size: 18, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }

                    Spacer()

                    Button(action: { state.copy(row.value) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Copy")
                                .font(FoundryTheme.body(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
                .padding(.horizontal, 14)
                .frame(height: 60)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct DeveloperPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct DeveloperChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FoundryTheme.body(size: 12.5, weight: .semibold))
                .foregroundStyle(isSelected ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

private struct DeveloperInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .tracking(0.5)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 15, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeveloperErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(FoundryTheme.body(size: 13, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.85))
            .padding(.horizontal, 2)
    }
}
