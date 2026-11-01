#!/usr/bin/env swift
// Renders the Foundry app icon into Supporting/AppIcon.iconset/*.png plus
// Supporting/icon-1024.png: the website's tiled "f" in chalk tiles, closed by
// the orange full stop the site ends its headlines with.
// The f outline is the one in anvil/scripts/build-foundry-tiles.mjs.
// Usage: swift scripts/render-icon.swift [outDir]   (default: Supporting/AppIcon.iconset)

import AppKit
import CoreGraphics

private let space = CGColorSpace(name: CGColorSpace.sRGB)!

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

private func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

private func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    for i in 0...360 {
        let t = Double(i) / 360 * 2 * .pi
        let x = rect.midX + rect.width / 2 * CGFloat(copysign(pow(abs(cos(t)), 0.4), cos(t)))
        let y = rect.midY + rect.height / 2 * CGFloat(copysign(pow(abs(sin(t)), 0.4), sin(t)))
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

private func letterF(_ T: (CGFloat, CGFloat) -> CGPoint) -> CGPath {
    let p = CGMutablePath()
    p.move(to: T(61, 181)); p.addLine(to: T(96, 181)); p.addLine(to: T(96, 156))
    p.addCurve(to: T(176, 94), control1: T(96, 111), control2: T(126, 94))
    p.addLine(to: T(228, 94)); p.addLine(to: T(228, 151)); p.addLine(to: T(195, 151))
    p.addCurve(to: T(168, 181), control1: T(171, 151), control2: T(168, 159))
    p.addLine(to: T(228, 181)); p.addLine(to: T(228, 238)); p.addLine(to: T(168, 238))
    p.addLine(to: T(168, 411)); p.addLine(to: T(96, 411)); p.addLine(to: T(96, 238))
    p.addLine(to: T(61, 238)); p.closeSubpath()
    return p
}

/// Splits [a, b] into n equal cells so tile edges land on the glyph's straight edges.
private func split(_ a: CGFloat, _ b: CGFloat, _ n: Int) -> [CGFloat] {
    (0...n).map { a + (b - a) * CGFloat($0) / CGFloat(n) }
}

private let rows = Array(split(94, 181, 3).dropLast()) + Array(split(181, 238, 2).dropLast()) + split(238, 411, 6)
private let columns: [CGFloat] = [61, 96, 132, 168, 198, 228]
private let stopX: CGFloat = 246, stopWidth: CGFloat = 72

private func renderIcon(px: Int) -> CGImage {
    let s = CGFloat(px), u = s / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // Apple's macOS grid: an 824 pt body centred on the 1024 canvas.
    let bodyRect = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let body = squircle(bodyRect)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10 * u), blur: 24 * u, color: rgb(0, 0.30))
    ctx.addPath(body); ctx.setFillColor(rgb(0x12100e)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x24211d), rgb(0x15130f), rgb(0x0d0c0a)], [0, 0.55, 1]),
                           start: CGPoint(x: 0, y: bodyRect.minY), end: CGPoint(x: 0, y: bodyRect.maxY), options: [])

    let markWidth = stopX + stopWidth - 61, markHeight: CGFloat = 411 - 94
    let k = 500 * u / markHeight
    let ox = 512 * u - markWidth * k / 2 - 61 * k + 4 * u
    let oy = 512 * u - markHeight * k / 2 - 94 * k
    func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }
    let glyph = letterF(T)
    let gap = 4 * k

    func tile(_ cell: CGRect, top: CGColor, bottom: CGColor, clip: CGPath?) {
        let rect = cell.insetBy(dx: gap / 2, dy: gap / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.08, cornerHeight: rect.width * 0.08, transform: nil)
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip() }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: rect.height * 0.08), blur: rect.height * 0.16, color: rgb(0, 0.55))
        ctx.addPath(path); ctx.setFillColor(bottom); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient([top, bottom], [0, 1]), start: CGPoint(x: rect.minX, y: rect.minY),
                               end: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY), options: [])
        ctx.saveGState()
        ctx.setBlendMode(.softLight)
        ctx.drawRadialGradient(gradient([rgb(0xffffff, 0.55), rgb(0xffffff, 0)], [0, 1]),
                               startCenter: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.25), startRadius: 0,
                               endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.9, options: [])
        ctx.restoreGState()
        ctx.setLineWidth(max(1, rect.width * 0.04))
        for (band, color) in [(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.35), rgb(0xffffff, 0.35)),
                              (CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.3, width: rect.width, height: rect.height * 0.3), rgb(0, 0.28))] {
            ctx.saveGState()
            ctx.clip(to: band)
            ctx.addPath(path); ctx.setStrokeColor(color); ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    for i in 0..<(rows.count - 1) {
        for j in 0..<(columns.count - 1) {
            let cell = CGRect(origin: T(columns[j], rows[i]),
                              size: CGSize(width: (columns[j + 1] - columns[j]) * k, height: (rows[i + 1] - rows[i]) * k))
            let cellPath = CGPath(rect: cell, transform: nil)
            guard cellPath.intersects(glyph) else { continue }
            let piece = cellPath.intersection(glyph).boundingBoxOfPath
            guard piece.width > cell.width * 0.4, piece.height > cell.height * 0.4 else { continue }
            tile(cell, top: rgb(0xebe5d8), bottom: rgb(0xc9bea9), clip: glyph)
        }
    }

    let rowHeight = rows[rows.count - 1] - rows[rows.count - 2]
    for column in 0..<2 {
        for row in 1...2 {
            let cell = CGRect(origin: T(stopX + CGFloat(column) * stopWidth / 2, 411 - rowHeight * CGFloat(row)),
                              size: CGSize(width: stopWidth / 2 * k, height: rowHeight * k))
            tile(cell, top: rgb(0xff7a3d), bottom: rgb(0xf04b10), clip: nil)
        }
    }

    ctx.addPath(body); ctx.setStrokeColor(rgb(0xffffff, 0.10)); ctx.setLineWidth(3 * u); ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-icon", code: 1)
    }
    try png.write(to: url)
}

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Supporting/AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in entries {
    try writePNG(renderIcon(px: px), to: outDir.appendingPathComponent(name))
}
try writePNG(renderIcon(px: 1024), to: outDir.deletingLastPathComponent().appendingPathComponent("icon-1024.png"))
print("Wrote \(entries.count) icons + icon-1024.png → \(outDir.path)")
