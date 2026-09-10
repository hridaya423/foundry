import SwiftUI
import FoundryDomain

struct WindowLayoutPicker: View {
    let results: [CommandResult]
    let onSelect: (CommandResult) -> Void
    let onMore: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Window layouts")
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText.opacity(0.82))

                Spacer()

                Button(action: onMore) {
                    HStack(spacing: 4) {
                        Text("View all")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel("Show all window layouts")
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(results, id: \.id) { result in
                    CompactLayoutButton(result: result) {
                        onSelect(result)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct CompactLayoutButton: View {
    let result: CommandResult
    let action: () -> Void

    @State private var isHovering = false

    private var placement: FoundryDomain.WindowPlacement? {
        result.windowPlacement
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LayoutDiagram(placement: placement, isSelected: false)
                    .frame(width: 34, height: 24)

                Text(placement?.shortTitle ?? result.title)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(isHovering ? Color.primary.opacity(0.07) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.065), lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .pointerCursor()
        .help(result.title)
        .accessibilityLabel(result.title)
    }
}

struct WindowLayoutManager: View {
    let results: [CommandResult]
    let selectedResultID: String?
    let isLoading: Bool
    let onSelect: (CommandResult) -> Void
    let onHover: (CommandResult) -> Void

    @State private var family: SpatialLayoutFamily = .halves

    private var resultByPlacement: [FoundryDomain.WindowPlacement: CommandResult] {
        Dictionary(uniqueKeysWithValues: results.compactMap { result in
            result.windowPlacement.map { ($0, result) }
        })
    }

    private var selectedPlacement: FoundryDomain.WindowPlacement? {
        results.first { $0.id == selectedResultID }?.windowPlacement
    }

    var body: some View {
        VStack(spacing: 0) {
            managerHeader

            if results.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    spatialWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(Color.primary.opacity(0.075))
                        .frame(width: 1)
                        .padding(.vertical, 14)

                    utilityRail
                        .frame(width: 218)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .onAppear { ensureVisibleSelection() }
        .onChange(of: results.map(\.id)) { _, _ in
            ensureVisibleSelection()
        }
        .onChange(of: selectedResultID) { _, _ in
            revealFamily(for: selectedPlacement)
        }
    }

    private var managerHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.accentTint)
                .frame(width: 28, height: 28)
                .background(FoundryTheme.accentTint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Window management")
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)

                Text("Arrange the frontmost window")
                    .font(FoundryTheme.body(size: 11, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
    }

    private var spatialWorkspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(SpatialLayoutFamily.allCases, id: \.self) { option in
                    FamilyTab(title: option.title, isSelected: family == option) {
                        selectFamily(option)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30)

            SpatialLayoutGrid(
                results: family.placements.compactMap { resultByPlacement[$0] },
                family: family,
                selectedResultID: selectedResultID,
                onSelect: onSelect,
                onHover: onHover
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
        .padding(.trailing, 14)
    }

    private var utilityRail: some View {
        VStack(alignment: .leading, spacing: 11) {
            UtilitySection(title: "Window") {
                VStack(spacing: 3) {
                    UtilityActionButton(
                        result: resultByPlacement[.maximize],
                        title: "Maximize",
                        systemName: "arrow.up.left.and.arrow.down.right",
                        isSelected: selectedPlacement == .maximize,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                    UtilityActionButton(
                        result: resultByPlacement[.center],
                        title: "Center",
                        systemName: "rectangle.center.inset.filled",
                        isSelected: selectedPlacement == .center,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                    UtilityActionButton(
                        result: resultByPlacement[.restore],
                        title: "Restore previous frame",
                        systemName: "arrow.uturn.backward",
                        isSelected: selectedPlacement == .restore,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                }
            }

            UtilitySection(title: "Resize") {
                HStack(spacing: 5) {
                    UtilityIconButton(
                        result: resultByPlacement[.decreaseSize],
                        systemName: "minus",
                        label: "Shrink window",
                        isSelected: selectedPlacement == .decreaseSize,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                    UtilityIconButton(
                        result: resultByPlacement[.increaseSize],
                        systemName: "plus",
                        label: "Grow window",
                        isSelected: selectedPlacement == .increaseSize,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                }
            }

            UtilitySection(title: "Nudge") {
                HStack(spacing: 5) {
                    utilityIcon(.nudgeLeft, "arrow.left", "Nudge left")
                    utilityIcon(.nudgeUp, "arrow.up", "Nudge up")
                    utilityIcon(.nudgeDown, "arrow.down", "Nudge down")
                    utilityIcon(.nudgeRight, "arrow.right", "Nudge right")
                }
            }

            UtilitySection(title: "Display") {
                HStack(spacing: 5) {
                    UtilityIconButton(
                        result: resultByPlacement[.previousDisplay],
                        systemName: "chevron.left",
                        label: "Previous display",
                        isSelected: selectedPlacement == .previousDisplay,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                    UtilityIconButton(
                        result: resultByPlacement[.nextDisplay],
                        systemName: "chevron.right",
                        label: "Next display",
                        isSelected: selectedPlacement == .nextDisplay,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.top, 13)
    }

    private func utilityIcon(_ placement: FoundryDomain.WindowPlacement, _ systemName: String, _ label: String) -> some View {
        UtilityIconButton(
            result: resultByPlacement[placement],
            systemName: systemName,
            label: label,
            isSelected: selectedPlacement == placement,
            onSelect: onSelect,
            onHover: onHover
        )
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(FoundryTheme.secondaryText)
                Text("Loading layouts…")
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
            } else {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                Text("No window layouts available")
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureVisibleSelection() {
        if selectedPlacement != nil {
            revealFamily(for: selectedPlacement)
        } else if let firstResult = resultByPlacement[.leftHalf] ?? results.first {
            onHover(firstResult)
        }
    }

    private func selectFamily(_ option: SpatialLayoutFamily) {
        family = option
        if let firstResult = option.placements.compactMap({ resultByPlacement[$0] }).first {
            onHover(firstResult)
        }
    }

    private func revealFamily(for placement: FoundryDomain.WindowPlacement?) {
        guard let placement, let matching = SpatialLayoutFamily.allCases.first(where: { $0.placements.contains(placement) }) else { return }
        family = matching
    }
}

private enum SpatialLayoutFamily: String, CaseIterable, Hashable {
    case halves
    case quarters
    case thirds

    var title: String {
        switch self {
        case .halves: return "Halves"
        case .quarters: return "Quarters"
        case .thirds: return "Thirds"
        }
    }

    var placements: [FoundryDomain.WindowPlacement] {
        switch self {
        case .halves: return [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
        case .quarters: return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .thirds: return [.leftThird, .centerThird, .rightThird]
        }
    }
}

private struct FamilyTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(isSelected ? Color.primary.opacity(0.10) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerCursor()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SpatialLayoutGrid: View {
    let results: [CommandResult]
    let family: SpatialLayoutFamily
    let selectedResultID: String?
    let onSelect: (CommandResult) -> Void
    let onHover: (CommandResult) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: family == .thirds ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(results, id: \.id) { result in
                SpatialLayoutButton(
                    result: result,
                    isSelected: selectedResultID == result.id,
                    isWide: family == .thirds,
                    onSelect: { onSelect(result) },
                    onHover: { onHover(result) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SpatialLayoutButton: View {
    let result: CommandResult
    let isSelected: Bool
    let isWide: Bool
    let onSelect: () -> Void
    let onHover: () -> Void

    @State private var isHovering = false
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed

    private var placement: FoundryDomain.WindowPlacement? {
        result.windowPlacement
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if isWide {
                    HStack(spacing: 12) {
                        LayoutDiagram(placement: placement, isSelected: isSelected)
                            .frame(width: 116, height: 58)
                        titleRow
                    }
                } else {
                    VStack(spacing: 7) {
                        LayoutDiagram(placement: placement, isSelected: isSelected)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        titleRow
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: isWide ? 78 : 104, maxHeight: isWide ? 82 : 124)
            .background(tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tileBorder, lineWidth: isSelected ? 1.25 : 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            isHovering = hovering
            if hovering && hoverHighlightsArmed { onHover() }
        }
        .pointerCursor()
        .help(result.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.title)
        .accessibilityHint(result.subtitle ?? "Arrange the frontmost window")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(placement?.shortTitle ?? result.title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Text("↵")
                    .font(FoundryTheme.body(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryTheme.accentTint)
            }
        }
    }

    private var tileBackground: Color {
        if isSelected { return FoundryTheme.accentTint.opacity(0.085) }
        if isHovering && hoverHighlightsArmed { return Color.primary.opacity(0.06) }
        return Color.primary.opacity(0.028)
    }

    private var tileBorder: Color {
        if isSelected { return FoundryTheme.accentTint.opacity(0.66) }
        if isHovering && hoverHighlightsArmed { return Color.primary.opacity(0.15) }
        return Color.primary.opacity(0.065)
    }
}

private struct UtilitySection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(FoundryTheme.body(size: 9, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
            content
        }
    }
}

private struct UtilityActionButton: View {
    let result: CommandResult?
    let title: String
    let systemName: String
    let isSelected: Bool
    let onSelect: (CommandResult) -> Void
    let onHover: (CommandResult) -> Void

    @State private var isHovering = false
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed

    var body: some View {
        Button {
            if let result { onSelect(result) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? FoundryTheme.accentTint : FoundryTheme.secondaryText)
                    .frame(width: 16)

                Text(title)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Text("↵")
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(FoundryTheme.accentTint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
            .background(controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(result == nil)
        .onHover { hovering in
            isHovering = hovering
            if hovering, hoverHighlightsArmed, let result { onHover(result) }
        }
        .pointerCursor()
        .accessibilityLabel(title)
    }

    private var controlBackground: Color {
        if isSelected { return FoundryTheme.accentTint.opacity(0.09) }
        if isHovering && hoverHighlightsArmed { return Color.primary.opacity(0.06) }
        return Color.clear
    }
}

private struct UtilityIconButton: View {
    let result: CommandResult?
    let systemName: String
    let label: String
    let isSelected: Bool
    let onSelect: (CommandResult) -> Void
    let onHover: (CommandResult) -> Void

    @State private var isHovering = false
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed

    var body: some View {
        Button {
            if let result { onSelect(result) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? FoundryTheme.accentTint : FoundryTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovering ? 0.12 : 0.055), lineWidth: 1)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(result == nil)
        .onHover { hovering in
            isHovering = hovering
            if hovering, hoverHighlightsArmed, let result { onHover(result) }
        }
        .pointerCursor()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var controlBackground: Color {
        if isSelected { return FoundryTheme.accentTint.opacity(0.09) }
        if isHovering && hoverHighlightsArmed { return Color.primary.opacity(0.06) }
        return Color.primary.opacity(0.025)
    }
}

private struct LayoutDiagram: View {
    let placement: FoundryDomain.WindowPlacement?
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 1, dy: 1)
            let inset = max(min(bounds.width, bounds.height) * 0.08, 2)
            let content = bounds.insetBy(dx: inset, dy: inset)

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(isSelected ? 0.22 : 0.14), lineWidth: 1)
                    }

                ForEach(Array((placement?.previewWindows(in: content) ?? []).enumerated()), id: \.offset) { _, window in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(window.isActive ? Color(red: 0.38, green: 0.51, blue: 0.72).opacity(0.88) : Color.primary.opacity(0.24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.primary.opacity(window.isActive ? 0.14 : 0.10), lineWidth: 1)
                        }
                        .frame(width: window.frame.width, height: window.frame.height)
                        .position(x: window.frame.midX, y: window.frame.midY)
                }
            }
        }
    }
}

private struct LayoutPreviewWindow {
    let frame: CGRect
    let isActive: Bool
}

private extension CommandResult {
    var windowPlacement: FoundryDomain.WindowPlacement? {
        guard case let .tileWindow(placement) = primaryAction.kind else { return nil }
        return placement
    }
}

private extension FoundryDomain.WindowPlacement {
    var shortTitle: String {
        switch self {
        case .leftHalf: return "Left"
        case .rightHalf: return "Right"
        case .topHalf: return "Top"
        case .bottomHalf: return "Bottom"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        case .leftThird: return "Left third"
        case .centerThird: return "Center third"
        case .rightThird: return "Right third"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .increaseSize: return "Grow"
        case .decreaseSize: return "Shrink"
        case .nudgeLeft: return "Nudge left"
        case .nudgeRight: return "Nudge right"
        case .nudgeUp: return "Nudge up"
        case .nudgeDown: return "Nudge down"
        case .nextDisplay: return "Next display"
        case .previousDisplay: return "Previous display"
        case .restore: return "Restore"
        }
    }

    func previewWindows(in frame: CGRect) -> [LayoutPreviewWindow] {
        let gap = max(min(frame.width, frame.height) * 0.045, 1)
        let halfWidth = frame.width / 2 - gap / 2
        let halfHeight = frame.height / 2 - gap / 2
        let thirdWidth = frame.width / 3 - gap * 2 / 3

        switch self {
        case .leftHalf:
            return [
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.minY, width: halfWidth, height: frame.height), isActive: true),
                LayoutPreviewWindow(frame: CGRect(x: frame.midX + gap / 2, y: frame.minY, width: halfWidth, height: frame.height), isActive: false)
            ]
        case .rightHalf:
            return [
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.minY, width: halfWidth, height: frame.height), isActive: false),
                LayoutPreviewWindow(frame: CGRect(x: frame.midX + gap / 2, y: frame.minY, width: halfWidth, height: frame.height), isActive: true)
            ]
        case .topHalf:
            return [
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: halfHeight), isActive: true),
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.midY + gap / 2, width: frame.width, height: halfHeight), isActive: false)
            ]
        case .bottomHalf:
            return [
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: halfHeight), isActive: false),
                LayoutPreviewWindow(frame: CGRect(x: frame.minX, y: frame.midY + gap / 2, width: frame.width, height: halfHeight), isActive: true)
            ]
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let frames = [
                CGRect(x: frame.minX, y: frame.minY, width: halfWidth, height: halfHeight),
                CGRect(x: frame.midX + gap / 2, y: frame.minY, width: halfWidth, height: halfHeight),
                CGRect(x: frame.minX, y: frame.midY + gap / 2, width: halfWidth, height: halfHeight),
                CGRect(x: frame.midX + gap / 2, y: frame.midY + gap / 2, width: halfWidth, height: halfHeight)
            ]
            let activeIndex: Int
            switch self {
            case .topLeft: activeIndex = 0
            case .topRight: activeIndex = 1
            case .bottomLeft: activeIndex = 2
            case .bottomRight: activeIndex = 3
            default: activeIndex = 0
            }
            return frames.enumerated().map { index, frame in
                LayoutPreviewWindow(frame: frame, isActive: index == activeIndex)
            }
        case .leftThird, .centerThird, .rightThird:
            let frames = [
                CGRect(x: frame.minX, y: frame.minY, width: thirdWidth, height: frame.height),
                CGRect(x: frame.minX + frame.width / 3 + gap / 3, y: frame.minY, width: thirdWidth, height: frame.height),
                CGRect(x: frame.maxX - frame.width / 3 + gap / 3, y: frame.minY, width: thirdWidth, height: frame.height)
            ]
            let activeIndex: Int
            switch self {
            case .leftThird: activeIndex = 0
            case .centerThird: activeIndex = 1
            case .rightThird: activeIndex = 2
            default: activeIndex = 0
            }
            return frames.enumerated().map { index, frame in
                LayoutPreviewWindow(frame: frame, isActive: index == activeIndex)
            }
        case .maximize:
            return [LayoutPreviewWindow(frame: frame, isActive: true)]
        case .center:
            return [LayoutPreviewWindow(frame: frame.insetBy(dx: frame.width * 0.22, dy: frame.height * 0.20), isActive: true)]
        case .restore:
            return [LayoutPreviewWindow(frame: frame.insetBy(dx: frame.width * 0.25, dy: frame.height * 0.23), isActive: true)]
        case .increaseSize, .decreaseSize, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .nextDisplay, .previousDisplay:
            return []
        }
    }
}
