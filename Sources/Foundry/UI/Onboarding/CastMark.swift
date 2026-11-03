import AppKit
import SwiftUI

/// The app icon's mark, Split Mould, cast in front of the user: the three
/// chalk mould pieces close in and cool from hot, then the cast lands last and
/// stays hot. Geometry matches docs/brand/mark/mark.svg and scripts/render-icon.swift.
struct CastMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var settled = false

    var body: some View {
        TimelineView(.animation(paused: settled || reduceMotion)) { context in
            let elapsed = settled || reduceMotion ? .infinity : context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                MarkTiles.draw(in: &canvas, size: size, elapsed: elapsed)
            }
        }
        .aspectRatio(MarkTiles.bounds.width / MarkTiles.bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(MarkTiles.castDuration))
            settled = true
        }
    }
}

enum MarkTiles {
    struct Piece {
        let path: Path
        let delay: Double
        let travel: CGSize
        let isCast: Bool
    }

    static let bounds = CGRect(x: 10, y: 10, width: 100, height: 102)
    static let landDuration = 0.45
    static let castDelay = 0.6
    static let depth: CGFloat = 1.5
    static let castDuration = castDelay + landDuration + 0.1

    /// Corners as (x, y, radius) in the mark's 120-unit grid, y down.
    static func outline(_ corners: [(CGFloat, CGFloat, CGFloat)]) -> Path {
        var path = Path()
        let points = corners.map { CGPoint(x: $0.0, y: $0.1) }
        let last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for (index, corner) in corners.enumerated() {
            let next = points[(index + 1) % points.count]
            path.addArc(tangent1End: points[index], tangent2End: next, radius: corner.2)
        }
        path.closeSubpath()
        return path
    }

    static let pieces: [Piece] = [
        Piece(path: outline([(10, 10, 10), (55, 10, 0), (55, 30, 0), (40, 30, 0), (40, 110, 0), (10, 110, 10)]),
              delay: 0, travel: CGSize(width: -8, height: 0), isCast: false),
        Piece(path: outline([(65, 10, 0), (110, 10, 10), (110, 70, 0), (80, 70, 0), (80, 30, 0), (65, 30, 0)]),
              delay: 0.1, travel: CGSize(width: 8, height: 0), isCast: false),
        Piece(path: outline([(80, 80, 0), (110, 80, 0), (110, 110, 10), (80, 110, 0)]),
              delay: 0.2, travel: CGSize(width: 8, height: 0), isCast: false),
        Piece(path: Path(CGRect(x: 50, y: 40, width: 20, height: 60)),
              delay: castDelay, travel: CGSize(width: 0, height: -10), isCast: true),
    ]

    static func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: -bounds.minX, y: -bounds.minY)
        let heat = GraphicsContext.Shading.color(FoundryTheme.Brand.accent)
        for piece in pieces {
            let progress = max(0, min(1, (elapsed - piece.delay) / landDuration))
            guard progress > 0 else { continue }
            let landed = 1 - pow(1 - progress, 3)
            let box = piece.path.boundingRect
            var layer = canvas
            layer.opacity = min(1, progress * 2)
            layer.translateBy(x: piece.travel.width * (1 - landed), y: piece.travel.height * (1 - landed))
            var side = layer
            side.addFilter(.shadow(color: FoundryTheme.Brand.tileShadow, radius: 2, y: 1.5))
            side.fill(piece.path.offsetBy(dx: 0, dy: depth),
                      with: .color(piece.isCast ? FoundryTheme.Brand.accentSide : FoundryTheme.Brand.chalkSideBottom))
            let top = piece.isCast ? FoundryTheme.Brand.accent : FoundryTheme.Brand.chalkTop
            let bottom = piece.isCast ? FoundryTheme.Brand.accentDeep : FoundryTheme.Brand.chalkBottom
            layer.fill(piece.path, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                         startPoint: CGPoint(x: box.minX, y: box.minY),
                                                         endPoint: CGPoint(x: box.minX, y: box.maxY)))
            guard piece.isCast == false, progress < 1 else { continue }
            layer.opacity *= 1 - max(0, min(1, (progress - 0.2) / 0.8))
            layer.fill(piece.path, with: heat)
        }
    }
}

extension MarkTiles {
    /// The mark as a solid menu-bar template: tiles blur together at 14 pt,
    /// so the silhouette carries it.
    @MainActor static let menuBarImage: NSImage = {
        let pieces: [[(CGFloat, CGFloat)]] = [
            [(1, 1), (7, 1), (7, 4), (5, 4), (5, 15), (1, 15)],
            [(9, 1), (15, 1), (15, 9), (11, 9), (11, 4), (9, 4)],
            [(11, 10), (15, 10), (15, 15), (11, 15)],
            [(6, 6), (10, 6), (10, 14), (6, 14)],
        ]
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setShouldAntialias(false)
            for piece in pieces {
                context.addLines(between: piece.map { CGPoint(x: $0.0, y: $0.1) })
                context.closePath()
            }
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Foundry")
        return image
    }()
}
