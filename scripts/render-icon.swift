#!/usr/bin/env swift
// Renders the Foundry app icon into Supporting/AppIcon.iconset/*.png plus
// Supporting/icon-1024.png: the Split Mould mark from docs/brand/mark/mark.svg,
// two chalk mould halves around one orange cast, on ink.
// Sizes of 32 px and below draw docs/brand/mark/mark-16.svg, hinted to whole pixels.
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

private func mouldHalves(_ T: (CGFloat, CGFloat) -> CGPoint, unit k: CGFloat) -> [CGPath] {
    let r = 10 * k
    let left = CGMutablePath()
    left.move(to: T(20, 10)); left.addLine(to: T(55, 10)); left.addLine(to: T(55, 30)); left.addLine(to: T(40, 30))
    left.addLine(to: T(40, 110)); left.addLine(to: T(20, 110))
    left.addArc(tangent1End: T(10, 110), tangent2End: T(10, 100), radius: r)
    left.addLine(to: T(10, 20))
    left.addArc(tangent1End: T(10, 10), tangent2End: T(20, 10), radius: r)
    left.closeSubpath()
    let upper = CGMutablePath()
    upper.move(to: T(65, 10)); upper.addLine(to: T(100, 10))
    upper.addArc(tangent1End: T(110, 10), tangent2End: T(110, 20), radius: r)
    upper.addLine(to: T(110, 70)); upper.addLine(to: T(80, 70)); upper.addLine(to: T(80, 30)); upper.addLine(to: T(65, 30))
    upper.closeSubpath()
    let lower = CGMutablePath()
    lower.move(to: T(80, 80)); lower.addLine(to: T(110, 80)); lower.addLine(to: T(110, 100))
    lower.addArc(tangent1End: T(110, 110), tangent2End: T(100, 110), radius: r)
    lower.addLine(to: T(80, 110))
    lower.closeSubpath()
    return [left, upper, lower]
}

private func hintedPieces(_ T: (CGFloat, CGFloat) -> CGPoint, inset: Bool) -> (halves: [CGPath], cast: CGPath) {
    func poly(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { T($0.0, $0.1) })
        p.closeSubpath()
        return p
    }
    if inset {
        return ([
            poly([(2, 2), (7, 2), (7, 4), (5, 4), (5, 14), (2, 14)]),
            poly([(9, 2), (14, 2), (14, 8), (11, 8), (11, 4), (9, 4)]),
            poly([(11, 9), (14, 9), (14, 14), (11, 14)]),
        ], poly([(6, 6), (10, 6), (10, 13), (6, 13)]))
    }
    return ([
        poly([(1, 1), (7, 1), (7, 4), (5, 4), (5, 15), (1, 15)]),
        poly([(9, 1), (15, 1), (15, 9), (11, 9), (11, 4), (9, 4)]),
        poly([(11, 10), (15, 10), (15, 15), (11, 15)]),
    ], poly([(6, 6), (10, 6), (10, 14), (6, 14)]))
}

private func renderIcon(px: Int) -> CGImage {
    let s = CGFloat(px), u = s / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

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

    if px <= 32 {
        let full = px <= 16
        let unit = full ? s / 16 : max(1, (bodyRect.width * 0.62 / 16).rounded(.down))
        let origin = full ? 0 : ((s - unit * 16) / 2).rounded()
        func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin + x * unit, y: origin + y * unit) }
        if full {
            ctx.restoreGState()
            ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: 3 * unit, cornerHeight: 3 * unit, transform: nil))
            ctx.setFillColor(rgb(0x0f0d0c)); ctx.fillPath()
            ctx.saveGState()
        }
        let pieces = hintedPieces(T, inset: full)
        ctx.setShouldAntialias(false)
        for half in pieces.halves { ctx.addPath(half); ctx.setFillColor(rgb(0xeee7dd)); ctx.fillPath() }
        ctx.addPath(pieces.cast); ctx.setFillColor(rgb(0xfa6428)); ctx.fillPath()
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    let k = 480 * u / 120
    let o = 512 * u - 60 * k
    func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o + x * k, y: o + y * k) }

    func solid(_ path: CGPath, top: CGColor, bottom: CGColor) {
        let box = path.boundingBoxOfPath
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6 * u), blur: 14 * u, color: rgb(0, 0.55))
        ctx.addPath(path); ctx.setFillColor(bottom); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient([top, bottom], [0, 1]), start: CGPoint(x: box.minX, y: o + 10 * k),
                               end: CGPoint(x: box.minX, y: o + 110 * k), options: [])
        ctx.setLineWidth(3 * u)
        ctx.addPath(path); ctx.setStrokeColor(rgb(0xffffff, 0.22)); ctx.strokePath()
        ctx.restoreGState()
    }

    for half in mouldHalves(T, unit: k) {
        solid(half, top: rgb(0xf4ede2), bottom: rgb(0xd6cdbd))
    }
    let cast = CGPath(rect: CGRect(origin: T(50, 40), size: CGSize(width: 20 * k, height: 60 * k)), transform: nil)
    solid(cast, top: rgb(0xffa36c), bottom: rgb(0xf0672b))

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
