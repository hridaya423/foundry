import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

struct FoundryBackdrop: View {
    var intensity: Double = 0.72
    var isOpaque = false

    @Environment(\.colorScheme) private var colorScheme

    private var panelWash: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.46 * intensity)
            : Color.white.opacity(0.26 * intensity)
    }

    var body: some View {
        ZStack {
            if isOpaque {
                Color(nsColor: .windowBackgroundColor)
                Color.black.opacity(0.42 * intensity)
                LinearGradient(
                    colors: [Color.primary.opacity(0.07 * intensity), Color.primary.opacity(0.016 * intensity), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            } else {
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    ZStack {
                        Color.clear
                            .glassEffect(.regular, in: FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75))
                        FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                            .fill(panelWash)
                    }
                } else {
                    legacyGlass
                }
                #else
                legacyGlass
                #endif
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var legacyGlass: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        panelWash
    }
}
