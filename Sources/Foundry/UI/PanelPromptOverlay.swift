import SwiftUI

/// ConfirmBar + PanelForm in one overlay: renders a `PanelPromptSpec` —
/// title, optional message, optional image, labeled fields, an option
/// picker, and Confirm/Cancel actions — then resolves the pending prompt.
struct PanelPromptOverlay: View {
    let spec: PanelPromptSpec
    let resolve: (PanelPromptResult) -> Void

    @State private var texts: [String]
    @State private var selection: Int
    @FocusState private var focusedField: Int?

    init(spec: PanelPromptSpec, resolve: @escaping (PanelPromptResult) -> Void) {
        self.spec = spec
        self.resolve = resolve
        _texts = State(initialValue: spec.fields.map(\.initial))
        _selection = State(initialValue: spec.picker?.selected ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.title)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                if let message = spec.message {
                    Text(message)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let image = spec.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .frame(maxWidth: .infinity)
            }

            ForEach(Array(spec.fields.enumerated()), id: \.element.id) { index, field in
                Group {
                    if field.isSecure {
                        SecureField(String(localized: field.placeholder), text: $texts[index])
                    } else {
                        TextField(String(localized: field.placeholder), text: $texts[index])
                    }
                }
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(FoundryTheme.fillSubtle, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                .focused($focusedField, equals: index)
                .onSubmit(confirm)
            }

            if let picker = spec.picker {
                HStack(spacing: 4) {
                    ForEach(Array(picker.options.enumerated()), id: \.offset) { index, option in
                        Button { selection = index } label: {
                            Text(String(localized: option))
                                .font(FoundryTheme.bodySecondary)
                                .foregroundStyle(selection == index ? FoundryTheme.textPrimary : FoundryTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                                        .fill(selection == index ? FoundryTheme.fillTint : FoundryTheme.fillSubtle)
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                if let cancelLabel = spec.cancelLabel {
                    Button { resolve(.cancelled) } label: {
                        Text(String(localized: cancelLabel))
                            .font(FoundryTheme.bodySecondary)
                            .foregroundStyle(FoundryTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .contentShape(.rect)
                    }
                    .buttonStyle(FoundryQuietButtonStyle())
                }
                Spacer()
                Button(action: confirm) {
                    Text(String(localized: spec.confirmLabel))
                        .font(FoundryTheme.body)
                        .foregroundStyle(spec.isDestructive ? FoundryTheme.destructive : FoundryTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: FoundryTheme.Control.compact)
                        .background(FoundryTheme.fillTint, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                        .contentShape(.rect)
                }
                    .buttonStyle(PressableButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { focusedField = spec.fields.isEmpty ? nil : 0 }
    }

    private func confirm() {
        resolve(PanelPromptResult(confirmed: true, texts: texts, selection: selection))
    }
}
