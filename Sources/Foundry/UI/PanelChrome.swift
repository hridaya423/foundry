import AppKit
import SwiftUI
import FoundryDomain

struct FoundrySmoothedRectangle: InsettableShape {
    var cornerRadius: CGFloat
    var smoothing: CGFloat = 0.75
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        guard radius > 0 else { return Path(rect) }

        var path = Path()
        let exponent = 2 + (min(max(smoothing, 0), 1) * 2.5)
        let segments = 48

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), startAngle: -.pi / 2, exponent: exponent,
            radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), startAngle: 0, exponent: exponent,
            radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), startAngle: .pi / 2, exponent: exponent,
            radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), startAngle: .pi, exponent: exponent,
            radius: radius, segments: segments)
        path.closeSubpath()
        return path
    }

    private func addSuperellipseCorner(to path: inout Path, center: CGPoint, startAngle: CGFloat, exponent: CGFloat, radius: CGFloat, segments: Int) {
        for index in 1...segments {
            let angle = startAngle + (CGFloat(index) / CGFloat(segments) * .pi / 2)
            let x = copysign(pow(abs(cos(angle)), 2 / exponent), cos(angle)) * radius
            let y = copysign(pow(abs(sin(angle)), 2 / exponent), sin(angle)) * radius
            path.addLine(to: CGPoint(x: center.x + x, y: center.y + y))
        }
    }
}

struct ActionRow: View {
    let action: CommandAction
    let shortcut: String?
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FoundryTheme.fillTint)
                .overlay(
                    Image(systemName: iconName)
                        .font(FoundryTheme.Glyph.sm)
                        .foregroundStyle(FoundryTheme.textSecondary)
                )
                .frame(width: 28, height: 28)
                .scaleEffect(isSelected ? 1.04 : 1)

            Text(action.title)
                .font(FoundryTheme.rowTitle)
                .foregroundStyle(action.isDestructive ? FoundryTheme.destructive : FoundryTheme.textPrimary)

            Spacer()

            if let shortcut {
                KeycapHint(text: shortcut)
                    .accessibilityLabel("Shortcut \(HotkeyFormatter.spoken(shortcut))")
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: 40)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { isHovering = $0 }
    }

    private var iconName: String {
        action.behavior.icon ?? "bolt"
    }
}

struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTab: () -> Void
    let onReturn: () -> Void
    var onJump: (CommandPanelState.SelectionJump) -> Void = { _ in }

    func makeNSView(context: Context) -> LauncherSearchTextField {
        let field = LauncherSearchTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: LauncherSearchTextField.pointSize, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onTab = onTab
        field.onReturn = onReturn
        return field
    }

    func updateNSView(_ nsView: LauncherSearchTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.toolTip = text.isEmpty ? nil : text
        nsView.onTab = onTab
        nsView.onReturn = onReturn
        nsView.delegate = context.coordinator
        context.coordinator.text = $text
        context.coordinator.onTab = onTab
        context.coordinator.onReturn = onReturn
        context.coordinator.onJump = onJump
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, onTab: onTab, onReturn: onReturn)
        coordinator.onJump = onJump
        return coordinator
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onTab: (() -> Void)?
        var onReturn: (() -> Void)?
        var onJump: ((CommandPanelState.SelectionJump) -> Void)?

        init(text: Binding<String>, onTab: (() -> Void)? = nil, onReturn: (() -> Void)? = nil) {
            self.text = text
            self.onTab = onTab
            self.onReturn = onReturn
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                onTab?()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                return true
            case #selector(NSResponder.moveToBeginningOfDocument(_:)):
                onJump?(.first)
                return true
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                onJump?(.last)
                return true
            case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
                onJump?(.pageUp)
                return true
            case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
                onJump?(.pageDown)
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                onReturn?()
                return true
            default:
                return false
            }
        }
    }
}

final class LauncherSearchTextField: NSTextField {
    static let pointSize: CGFloat = 20

    var onTab: (() -> Void)?
    var onReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48, event.modifierFlags.contains(.shift) == false {
            onTab?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48 where event.modifierFlags.contains(.shift) == false:
            onTab?()
        case 36:
            onReturn?()
        default:
            super.keyDown(with: event)
        }
    }
}

struct LoadingHairline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Rectangle()
            .fill(FoundryTheme.accent)
            .frame(height: 1)
            .opacity(dimmed ? FoundryTheme.Alpha.subtle : FoundryTheme.Alpha.half)
            .accessibilityHidden(true)
            .onAppear {
                guard reduceMotion == false else { return }
                withAnimation(FoundryTheme.Motion.pulse.repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

struct HomeSkeleton: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous)
                        .frame(width: 24, height: 24)
                    Capsule()
                        .frame(width: [180, 140, 210, 120, 160][index], height: 9)
                    Spacer()
                }
                .padding(.horizontal, FoundryTheme.Spacing.sm)
                .frame(height: 40)
            }
            Spacer()
        }
        .foregroundStyle(FoundryTheme.fillTint)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel("Loading")
    }
}
