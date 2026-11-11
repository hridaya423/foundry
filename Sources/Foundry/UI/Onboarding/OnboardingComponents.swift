import SwiftUI

private typealias Brand = FoundryTheme.Brand

/// Display lines closed by the website's orange full stop.
struct BrandHeadline: View {
    let lines: [LocalizedStringKey]
    var lead: LocalizedStringKey?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 16 : 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    (Text(lines[index]).foregroundStyle(Brand.text)
                        + Text(index == lines.count - 1 ? "." : "").foregroundStyle(Brand.accent))
                        .font(large ? Brand.displayLarge : Brand.display)
                        .tracking(large ? Brand.displayLargeTracking : Brand.displayTracking)
                        .lineSpacing(0)
                        .frame(height: large ? 52 : 44)
                }
            }
            if let lead {
                Text(lead)
                    .font(Brand.lead)
                    .tracking(Brand.bodyTracking)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The orange call to action with its Return keycap. Until the step's task
/// is done it waits as a quiet outline, and Return doesn't press it.
struct BrandPrimaryButtonStyle: ButtonStyle {
    static let height: CGFloat = 44
    var ready = true
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
        HStack(spacing: 12) {
            configuration.label
            if ready {
                Image(systemName: "return")
                    .font(FoundryTheme.Glyph.xs.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .background(Brand.accentChip, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous))
            }
        }
        .font(Brand.button)
        .tracking(Brand.bodyTracking)
        .foregroundStyle(ready ? Brand.ink : Brand.text)
        .padding(.horizontal, 16)
        // One width on every step, so Back never moves.
        .frame(minWidth: 172, minHeight: Self.height)
        .background(shape.fill(ready ? Brand.accent : Brand.rowTop))
        .overlay(shape.strokeBorder(Brand.line, lineWidth: 1).opacity(ready ? 0 : 1))
        .animation(Brand.Motion.state, value: ready)
        .brightness(hovering && configuration.isPressed == false ? 0.04 : 0)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(configuration.isPressed ? Brand.Motion.press : Brand.Motion.release, value: configuration.isPressed)
        .animation(Brand.Motion.state, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// The website's row surface as a button.
struct BrandSecondaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.quiet)
            .tracking(Brand.bodyTracking)
            .foregroundStyle(Brand.text)
            .padding(.horizontal, 16)
            .frame(height: FoundryTheme.Control.row)
            .background(BrandRowSurface(radius: 6, lifted: hovering))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(configuration.isPressed ? Brand.Motion.press : Brand.Motion.release, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct BrandQuietButtonStyle: ButtonStyle {
    /// For ways out the user rarely needs, like skipping setup.
    var dim = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.quiet)
            .tracking(Brand.bodyTracking)
            .foregroundStyle(hovering ? Brand.text : (dim ? Brand.faint : Brand.muted))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? FoundryTheme.Alpha.pressed : 1)
            .animation(Brand.Motion.state, value: hovering)
            .onHover { hovering = $0 }
    }
}

struct BrandRowSurface: View {
    var radius: CGFloat = 6
    var lifted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Brand.rowTop)
            .brightness(lifted ? 0.03 : 0)
            .overlay(shape.strokeBorder(Brand.line, lineWidth: 1))
            .animation(Brand.Motion.state, value: lifted)
    }
}

/// A squared switch, shaped like the website's tiles.
struct BrandToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 16) {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous)
                        .fill(configuration.isOn ? Brand.accent : Brand.tileIdle)
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous)
                        .fill(Brand.text)
                        .frame(width: 18, height: 18)
                        .shadow(color: Brand.tileShadow, radius: 1, y: 1)
                        .padding(2)
                }
                .frame(width: 38, height: 22)
                .animation(Brand.Motion.state, value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// Rows stacked into one bordered group, the way the website lists commands.
/// Separate rows with `BrandDivider`.
struct BrandList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(BrandRowSurface())
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous))
    }
}

struct BrandDivider: View {
    var body: some View {
        Rectangle().fill(Brand.line).frame(height: FoundryTheme.hairline)
    }
}

struct BrandRowText: View {
    let title: LocalizedStringKey
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Brand.rowTitle)
                .tracking(Brand.bodyTracking)
                .foregroundStyle(Brand.text)
            if let detail {
                Text(detail)
                    .font(Brand.rowDetail)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The website's kbd chip: a hairline key with a heavier bottom edge.
struct BrandKbd: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Brand.kbd)
            .foregroundStyle(Brand.text)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 24)
            .background {
                let shape = RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous)
                shape.fill(Brand.line)
                    .overlay(shape.fill(Brand.rowTop).padding(.bottom, 2).padding([.horizontal, .top], 1))
            }
    }
}

/// One tile per step: done ones dim, the current one orange.
struct ProgressTiles: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.tile, style: .continuous)
                    .fill(index == current ? Brand.accent : (index < current ? Brand.tileDone : Brand.tileIdle))
                    .frame(width: 10, height: 10)
            }
        }
        .animation(Brand.Motion.state, value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Staggered entrance for a step's pieces.
struct Reveal<Content: View>: View {
    let index: Int
    var after: Double = 0
    @ViewBuilder var content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Brand.Motion.rise)
            .onAppear {
                withAnimation(Brand.Motion.enter.delay(after + Double(index) * Brand.Motion.stagger)) {
                    shown = true
                }
            }
    }
}
