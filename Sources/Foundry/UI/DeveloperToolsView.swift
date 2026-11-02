import SwiftUI

struct DeveloperToolsView: View {
    @Bindable var state: DeveloperToolsState

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
        HStack(spacing: FoundryTheme.Spacing.xs) {
            ForEach(Array(DeveloperToolsState.Tool.allCases.enumerated()), id: \.element) { index, tool in
                DeveloperChip(title: String(localized: tool.chipTitle), isSelected: state.selectedTool == tool) { state.selectedTool = tool }
                    .accessibilityLabel(tool.rawValue)
                    .help("\(tool.rawValue) · ⌘\(index + 1)")
            }
        }
    }

    private var baseTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Type a decimal, hex (0x), octal (0o) or binary (0b) number.")
            DeveloperInputField(title: "Input", placeholder: "255 or 0xff", text: $state.baseInput)

            if let error = state.baseError {
                DeveloperErrorText(message: error)
            } else {
                resultGrid(state.baseRows)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var bitTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Use decimal or prefixed inputs like 0xff. Search also supports 5 & 3, 5 << 1, and not 5 8.")

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
                    DeveloperInputField(title: state.bitOperation == .shiftLeft || state.bitOperation == .shiftRight ? "Shift" : "Right",
                        placeholder: "3", text: $state.bitRightInput)
                }
            }

            if let error = state.bitError {
                DeveloperErrorText(message: error)
            } else {
                if state.bitExpression.isEmpty == false {
                    Text(state.bitExpression)
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textSecondary)
                }
                resultGrid(state.bitRows)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var base64Tool: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Encode plain text or decode a Base64 value.")
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
            hint("Paste JSON to validate and pretty-print it.")
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
            hint("Convert text into common identifier styles.")
            DeveloperInputField(title: "Input", placeholder: "hello world", text: $state.caseInput)
            resultGrid(state.caseRows)
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var timestampTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Convert Unix seconds, milliseconds, or ISO 8601 dates.")
            DeveloperInputField(title: "Input", placeholder: "1712345678", text: $state.timestampInput)
            if let error = state.timestampError {
                DeveloperErrorText(message: error)
            } else {
                resultGrid(state.timestampRows)
            }
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private var wordCountTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Count words, characters, lines, and paragraphs as you type.")
            DeveloperTextEditor(title: "Text", placeholder: "Paste or type text to inspect", text: $state.wordCountInput)
            resultGrid(state.wordCountRows)
        }
        .padding(14)
        .modifier(DeveloperPanelSurface())
    }

    private func hint(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(FoundryTheme.bodySecondary)
            .foregroundStyle(FoundryTheme.textTertiary)
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
                            .font(FoundryTheme.micro)
                            .foregroundStyle(FoundryTheme.textQuaternary)
                        Text(row.value)
                            .font(FoundryTheme.body)
                            .foregroundStyle(FoundryTheme.textPrimary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.value)
                    }

                    Spacer(minLength: 0)
                    compactCopyButton(value: row.value)
                }
                .padding(.horizontal, 10)
                .frame(height: FoundryTheme.Control.rowDouble)
                .background(FoundryTheme.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
            }
        }
    }

    private func compactCopyButton(value: String) -> some View {
        Button(action: { state.copy(value) }) {
            Image(systemName: "doc.on.doc")
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 28, height: 26)
                .background(FoundryTheme.fillTint)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy value")
        .help("Copy value")
    }

    private func textOutput(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                Spacer()
                Button {
                    state.copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .frame(width: 28, height: 26)
                        .background(FoundryTheme.fillTint)
                        .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(title)")
                .help("Copy \(title)")
            }
            ScrollView {
                Text(value)
                    .font(FoundryTheme.mono)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(height: FoundryTheme.Control.preview)
            .background(FoundryTheme.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
        }
    }
}

private struct DeveloperPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)
                    .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
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
                .font(FoundryTheme.micro)
                .foregroundStyle(isSelected ? FoundryTheme.textPrimary : FoundryTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: FoundryTheme.Control.mini)
                .background(isSelected ? FoundryTheme.fillSelected : FoundryTheme.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DeveloperInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textQuaternary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: FoundryTheme.Control.row)
                .background(
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                        .fill(FoundryTheme.fillHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                                .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
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
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textQuaternary)
            TextEditor(text: $text)
                .font(FoundryTheme.mono)
                .foregroundStyle(FoundryTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: FoundryTheme.Control.editor)
                .background(
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                        .fill(FoundryTheme.fillHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                                .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(FoundryTheme.mono)
                            .foregroundStyle(FoundryTheme.textQuaternary)
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
            .font(FoundryTheme.body)
            .foregroundStyle(FoundryTheme.destructive)
            .padding(.horizontal, 2)
    }
}
