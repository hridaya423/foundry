#!/usr/bin/env swift
// Renders the Foundry app icon (anvil mark on a warm foundry-dark squircle)
// into Supporting/AppIcon.iconset/*.png, then iconutil makes AppIcon.icns.
// Usage: swift scripts/render-icon.swift [outDir]   (default: Supporting/AppIcon.iconset)

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Brand palette — warm foundry dark, bone chalk, forge ember.
// Matches anvil/ site tokens: #0f0d0c, #211d19, #c6bbab, #f4ece2, #fa6428.
private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
private let ember = rgb(0xfa / 255, 0x64 / 255, 0x28 / 255)
private let emberSoft = rgb(0xfd / 255, 0x94 / 255, 0x5f / 255)

// macOS icon squircle: continuous-curvature approximation (Lamé n≈5 superellipse
// is closest; we use the standard Cocoa continuous-corner CG path).
private func squirclePath(in rect: CGRect, cornerRadius r: CGFloat) -> CGPath {
    // n≈5 superellipse via cubic segments per quadrant (kappa for n=5 ≈ 1.12)
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let w = rect.width / 2, h = rect.height / 2
    let k: CGFloat = 0.662 // tuned so curvature reads like Apple's continuous corner
    let samples = 64
    path.move(to: CGPoint(x: cx + w, y: cy))
    for i in 1...samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + w * (c < 0 ? -1 : 1) * pow(abs(c), 2 / 5.0)
        let y = cy + h * (s < 0 ? -1 : 1) * pow(abs(s), 2 / 5.0)
        path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    _ = k
    return path
}

private func anvilPath(size: CGFloat) -> CGPath {
    // Stylized anvil silhouette, drawn in a 0..1 box, y-up.
    // Chunky face band on top, horn tapering left, blocky waist, wide foot.
    let p = CGMutablePath()
    // Horn tip (left point) — sits near face level, slight droop
    p.move(to: CGPoint(x: 0.05, y: 0.655))
    // Horn upper edge curving up into the face's left corner
    p.addQuadCurve(to: CGPoint(x: 0.30, y: 0.72), control: CGPoint(x: 0.16, y: 0.755))
    // Face top edge → right heel corner
    p.addLine(to: CGPoint(x: 0.93, y: 0.72))
    // Face right edge down to the step
    p.addLine(to: CGPoint(x: 0.93, y: 0.605))
    // Step in to the waist column
    p.addLine(to: CGPoint(x: 0.645, y: 0.605))
    // Waist right side down
    p.addLine(to: CGPoint(x: 0.645, y: 0.435))
    // Foot flare right
    p.addLine(to: CGPoint(x: 0.90, y: 0.40))
    p.addLine(to: CGPoint(x: 0.90, y: 0.29))   // right foot edge down
    p.addLine(to: CGPoint(x: 0.28, y: 0.29))   // base bottom
    p.addLine(to: CGPoint(x: 0.28, y: 0.40))   // left foot edge up
    p.addLine(to: CGPoint(x: 0.47, y: 0.435))  // left waist flare
    p.addLine(to: CGPoint(x: 0.47, y: 0.545))  // left waist up
    // Under-face sweep back along the horn's lower edge to the tip
    p.addQuadCurve(to: CGPoint(x: 0.05, y: 0.655), control: CGPoint(x: 0.27, y: 0.545))
    p.closeSubpath()
    return p
}

private func renderIcon(px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); fatalError("no ctx") }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    // macOS squircle insets ~0 on the canvas (Apple full-bleed icon canvas).
    let clip = squirclePath(in: rect, cornerRadius: s * 0.2237)
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()

    // 1. Background: warm vertical gradient + ember pool glow.
    let bgGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0x26 / 255, 0x1f / 255, 0x19 / 255),  // warm top
        rgb(0x14 / 255, 0x11 / 255, 0x0e / 255),  // mid
        rgb(0x0f / 255, 0x0d / 255, 0x0c / 255),  // near-black bottom
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])

    // Ember pool: tight radial glow under the anvil, low center.
    let glowCenter = CGPoint(x: s * 0.5, y: s * 0.30)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.50),
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.14),
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.0),
    ] as CFArray, locations: [0, 0.40, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: s * 0.33, options: [.drawsBeforeStartLocation])

    // Faint top sheen so the dark reads as glass-dark, not flat.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(1, 1, 1, 0.10), rgb(1, 1, 1, 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: s * 0.62), options: [])

    // 2. Anvil: bone gradient, ember rim-light along the bottom edge.
    let box = CGRect(x: s * 0.15, y: s * 0.26, width: s * 0.70, height: s * 0.46)
    let anvil = anvilPath(size: s)
    var t = CGAffineTransform(scaleX: box.width, y: box.height)
    t = t.translatedBy(x: box.minX / box.width, y: box.minY / box.height)
    guard let anvilScaled = anvil.copy(using: &t) else { fatalError() }

    ctx.saveGState()
    ctx.addPath(anvilScaled)
    ctx.clip()
    let metal = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0xf4 / 255, 0xec / 255, 0xe2 / 255),  // bone face
        rgb(0xd6 / 255, 0xca / 255, 0xb8 / 255),
        rgb(0xa8 / 255, 0x9a / 255, 0x84 / 255),  // cooled base
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
    // Ember rim-light: orange wash rising only through the foot.
    let rim = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.0),
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.45),
    ] as CFArray, locations: [0.78, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY - s * 0.01), options: [])
    ctx.restoreGState()

    // Hot face edge: thin ember line along the anvil's top edge (the "still-glowing" detail).
    // Path space is 0..1: face top is at y=0.72 within the box.
    let faceTopY = box.minY + box.height * 0.72
    ctx.saveGState()
    let faceLine = CGMutablePath()
    faceLine.move(to: CGPoint(x: box.minX + box.width * 0.32, y: faceTopY - s * 0.004))
    faceLine.addLine(to: CGPoint(x: box.minX + box.width * 0.925, y: faceTopY - s * 0.004))
    ctx.setStrokeColor(emberSoft)
    ctx.setLineWidth(s * 0.005)
    ctx.setLineCap(.round)
    ctx.addPath(faceLine)
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Sparks: three small sharp ember dots drifting up off the face's right end.
    let sparkData: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [ // x, y, r, alpha
        (0.705, 0.758, 0.0090, 0.95),
        (0.748, 0.795, 0.0065, 0.75),
        (0.782, 0.764, 0.0045, 0.55),
    ]
    for (x, y, r, a) in sparkData {
        let c = CGPoint(x: s * x, y: s * y)
        let rr = s * r
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
            rgb(0xfd / 255, 0x94 / 255, 0x5f / 255, a),
            rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, a * 0.6),
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rr * 2.2, options: [.drawsBeforeStartLocation])
        ctx.setFillColor(rgb(0xff / 255, 0xd8 / 255, 0xb8 / 255, a))
        ctx.fillEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    }

    // 4. Inner edge highlight for depth on dark.
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.14))
    ctx.setLineWidth(max(1, s * 0.003))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()
    img.unlockFocus()
    return img
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-icon", code: 1)
    }
    try png.write(to: url)
}

// Main
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Supporting/AppIcon.iconset")
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
// Marketing/DMG master.
try writePNG(renderIcon(px: 1024), to: outDir.deletingLastPathComponent().appendingPathComponent("icon-1024.png"))
print("Wrote \(entries.count) icons + icon-1024.png → \(outDir.path)")
