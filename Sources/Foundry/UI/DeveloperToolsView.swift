import SwiftUI

struct DeveloperToolsView: View {
    @ObservedObject var state: DeveloperToolsState

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                toolSwitcher

                switch state.selectedTool {
                case .base:
                    baseTool
                case .bitwise:
                    bitTool
                case .base64:
                    base64Tool
                case .json:
                    jsonTool
                case .textCase:
                    caseTool
                case .timestamp:
                    timestampTool
                case .wordCount:
                    wordCountTool
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toolSwitcher: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            ForEach(DeveloperToolsState.Tool.allCases) { tool in
                toolButton(tool)
            }
        }
    }

    private func toolButton(_ tool: DeveloperToolsState.Tool) -> some View {
        Button(action: { state.selectedTool = tool }) {
            Text(tool.rawValue)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(state.selectedTool == tool ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(state.selectedTool == tool ? 0.10 : 0.045))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var baseTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeveloperInputField(title: "Input", placeholder: "255 or 0xff", text: $state.baseInput)

            if let error = state.baseError {
                DeveloperErrorText(message: error)
            } else {
                resultGrid(state.baseRows)
            }
        }
        .padding(.top, 4)
    }

    private var bitTool: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                resultGrid(state.bitRows)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var base64Tool: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Base64", subtitle: "Encode plain text or decode a Base64 value.")
            HStack(spacing: 8) {
                ForEach(DeveloperToolsState.Base64Operation.allCases) { operation in
                    DeveloperChip(title: operation.rawValue, isSelected: state.base64Operation == operation) {
                        state.base64Operation = operation
                    }
                }
            }
            DeveloperTextEditor(title: "Input", placeholder: state.base64Operation == .encode ? "Text to encode" : "Base64 to decode", text: $state.base64Input)
            if let error = state.base64Error {
                DeveloperErrorText(message: error)
            } else if state.base64Output.isEmpty == false {
                textOutput(title: "Result", value: state.base64Output)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var jsonTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Format JSON", subtitle: "Paste JSON to validate and pretty-print it.")
            DeveloperTextEditor(title: "JSON Input", placeholder: "{\"name\": \"Foundry\"}", text: $state.jsonInput)
            if let error = state.jsonError {
                DeveloperErrorText(message: error)
            } else if state.jsonOutput.isEmpty == false {
                textOutput(title: "Formatted JSON", value: state.jsonOutput)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var caseTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Change Case", subtitle: "Convert text into common identifier styles.")
            DeveloperInputField(title: "Input", placeholder: "hello world", text: $state.caseInput)
            resultGrid(state.caseRows)
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var timestampTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Unix Timestamp", subtitle: "Convert Unix seconds, milliseconds, or ISO 8601 dates.")
            DeveloperInputField(title: "Input", placeholder: "1712345678", text: $state.timestampInput)
            resultGrid(state.timestampRows)
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var wordCountTool: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Word Count", subtitle: "Count words, characters, lines, and paragraphs as you type.")
            DeveloperTextEditor(title: "Text", placeholder: "Paste or type text to inspect", text: $state.wordCountInput)
            resultGrid(state.wordCountRows)
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

    private func resultGrid(_ rows: [DeveloperToolsState.OutputRow]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(FoundryTheme.body(size: 10, weight: .semibold))
                            .foregroundStyle(FoundryTheme.faintText)
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Text(row.value)
                            .font(FoundryTheme.body(size: 16, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }

                    Spacer(minLength: 0)
                    compactCopyButton(value: row.value)
                }
                .padding(.horizontal, 10)
                .frame(height: 52)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func compactCopyButton(value: String) -> some View {
        Button(action: { state.copy(value) }) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 28, height: 26)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func textOutput(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .tracking(0.5)
                Spacer()
                Button {
                    state.copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                    .buttonStyle(.plain)
                    .pointerCursor()
            }
            ScrollView {
                Text(value)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(height: 112)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .font(FoundryTheme.body(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 26)
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

private struct DeveloperTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .tracking(0.5)
            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(FoundryTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(FoundryTheme.faintText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
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
