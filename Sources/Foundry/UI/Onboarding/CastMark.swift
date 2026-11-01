import AppKit
import SwiftUI

/// The app icon's mark, "f." in chalk keycap tiles, cast in front of the
/// user: tiles fill the mould bottom-up, land hot and cool to chalk, and the
/// full stop lands last and stays hot. Geometry matches scripts/render-icon.swift.
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
    struct Tile {
        let path: Path
        let bounds: CGRect
        let delay: Double
        let isStop: Bool
    }

    static let bounds = CGRect(x: 61, y: 94, width: 257, height: 317)
    static let landDuration = 0.45
    static let stopDelay = 0.75
    /// Keycap depth, in mark units: the same chalk side the keyboard keys show.
    static let depth: CGFloat = 3
    static let castDuration = stopDelay + 0.15 + landDuration + 0.1

    /// The website's "f" outline, in mark units (y down).
    static let glyph: Path = {
        var glyph = Path()
        glyph.move(to: CGPoint(x: 61, y: 181)); glyph.addLine(to: CGPoint(x: 96, y: 181)); glyph.addLine(to: CGPoint(x: 96, y: 156))
        glyph.addCurve(to: CGPoint(x: 176, y: 94), control1: CGPoint(x: 96, y: 111), control2: CGPoint(x: 126, y: 94))
        glyph.addLine(to: CGPoint(x: 228, y: 94)); glyph.addLine(to: CGPoint(x: 228, y: 151)); glyph.addLine(to: CGPoint(x: 195, y: 151))
        glyph.addCurve(to: CGPoint(x: 168, y: 181), control1: CGPoint(x: 171, y: 151), control2: CGPoint(x: 168, y: 159))
        glyph.addLine(to: CGPoint(x: 228, y: 181)); glyph.addLine(to: CGPoint(x: 228, y: 238)); glyph.addLine(to: CGPoint(x: 168, y: 238))
        glyph.addLine(to: CGPoint(x: 168, y: 411)); glyph.addLine(to: CGPoint(x: 96, y: 411)); glyph.addLine(to: CGPoint(x: 96, y: 238))
        glyph.addLine(to: CGPoint(x: 61, y: 238)); glyph.closeSubpath()
        return glyph
    }()

    static let tiles: [Tile] = {
        func split(_ a: CGFloat, _ b: CGFloat, _ n: Int) -> [CGFloat] { (0...n).map { a + (b - a) * CGFloat($0) / CGFloat(n) } }
        let rows = Array(split(94, 181, 3).dropLast()) + Array(split(181, 238, 2).dropLast()) + split(238, 411, 6)
        let columns: [CGFloat] = [61, 96, 132, 168, 198, 228]
        let gap: CGFloat = 4

        func tile(_ cell: CGRect) -> Path {
            Path(roundedRect: cell.insetBy(dx: gap / 2, dy: gap / 2), cornerRadius: 3, style: .continuous)
        }
        var tiles: [Tile] = []
        for i in 0..<(rows.count - 1) {
            for j in 0..<(columns.count - 1) {
                let cell = CGRect(x: columns[j], y: rows[i], width: columns[j + 1] - columns[j], height: rows[i + 1] - rows[i])
                let piece = tile(cell).intersection(glyph)
                let covered = piece.boundingRect
                guard covered.width > cell.width * 0.4, covered.height > cell.height * 0.4 else { continue }
                // Metal fills a mould from the bottom; neighbours stay out of lockstep.
                let jitter = (Double(tiles.count) * 0.618_034).truncatingRemainder(dividingBy: 1)
                let delay = Double((411 - cell.maxY) / 317) * 0.55 + jitter * 0.08
                tiles.append(Tile(path: piece, bounds: cell, delay: delay, isStop: false))
            }
        }
        let rowHeight = rows[rows.count - 1] - rows[rows.count - 2]
        for (index, (column, row)) in [(0, 2), (1, 2), (0, 1), (1, 1)].enumerated() {
            let cell = CGRect(x: 246 + CGFloat(column) * 36, y: 411 - rowHeight * CGFloat(row), width: 36, height: rowHeight)
            tiles.append(Tile(path: tile(cell), bounds: cell, delay: stopDelay + Double(index) * 0.05, isStop: true))
        }
        return tiles
    }()

    static func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: -bounds.minX, y: -bounds.minY)
        let heat = GraphicsContext.Shading.color(FoundryTheme.Brand.accent)
        for tile in tiles {
            let progress = max(0, min(1, (elapsed - tile.delay) / landDuration))
            guard progress > 0 else { continue }
            let landed = 1 - pow(1 - progress, 3)
            var layer = canvas
            layer.opacity = min(1, progress * 2)
            layer.translateBy(x: 0, y: -(1 - landed) * 6)
            var side = layer
            side.addFilter(.shadow(color: FoundryTheme.Brand.tileShadow, radius: 5, y: 4))
            side.fill(tile.path.offsetBy(dx: 0, dy: depth),
                      with: .color(tile.isStop ? FoundryTheme.Brand.accentSide : FoundryTheme.Brand.chalkSideBottom))
            let top = tile.isStop ? FoundryTheme.Brand.accent : FoundryTheme.Brand.chalkTop
            let bottom = tile.isStop ? FoundryTheme.Brand.accentDeep : FoundryTheme.Brand.chalkBottom
            layer.fill(tile.path, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                        startPoint: CGPoint(x: tile.bounds.minX, y: tile.bounds.minY),
                                                        endPoint: CGPoint(x: tile.bounds.minX + tile.bounds.width * 0.3, y: tile.bounds.maxY)))
            guard tile.isStop == false, progress < 1 else { continue }
            layer.opacity *= 1 - max(0, min(1, (progress - 0.2) / 0.8))
            layer.fill(tile.path, with: heat)
        }
    }
}

extension MarkTiles {
    /// The mark as a solid menu-bar template: tiles blur together at 14 pt,
    /// so the silhouette carries it.
    @MainActor static let menuBarImage: NSImage = {
        let height: CGFloat = 14
        let scale = height / bounds.height
        let image = NSImage(size: CGSize(width: (bounds.width * scale).rounded(.up), height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.addPath(glyph.cgPath)
            context.addPath(CGPath(roundedRect: CGRect(x: 248, y: 355, width: 68, height: 54), cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Foundry")
        return image
    }()
}
