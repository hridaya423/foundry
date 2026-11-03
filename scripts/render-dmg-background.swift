#!/usr/bin/env swift
// Renders the Foundry DMG window background in the website's language, inverted:
// Finder draws icon labels in black, so the ground is the site's chalk. A row of
// tiles darkens toward Applications and ends in the orange full stop, under one
// Geist line closed by an orange period.
// Layout contract: 540×360 pt window, icons at {130,150} and {410,150}, the
// same coordinates used by the Finder layout in scripts/package-dmg.sh.
// Output: Supporting/DMGBackground.png (@2x, 1080×720) and DMGBackground@1x.png.
// Usage: swift scripts/render-dmg-background.swift

import AppKit
import CoreText

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let fonts = root.appendingPathComponent("Sources/Foundry/Resources/Onboarding")
CTFontManagerRegisterFontURLs([fonts.appendingPathComponent("Geist-Regular.ttf")] as CFArray, .process, true, nil)

private let chalk = rgb(0.910, 0.886, 0.851)
private let chalkGlow = rgb(0.957, 0.941, 0.914)
private let tileIdle = (r: 0.835, g: 0.804, b: 0.761)
private let tileDone = (r: 0.600, g: 0.561, b: 0.514)
private let accent = rgb(0.980, 0.392, 0.157)

private func render(scale s: CGFloat) -> NSBitmapImageRep {
    let w: CGFloat = 540, h: CGFloat = 360
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * s), pixelsHigh: Int(h * s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    // Work top-down like Finder does.
    ctx.translateBy(x: 0, y: h)
    ctx.scaleBy(x: 1, y: -1)

    ctx.setFillColor(chalk)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [chalkGlow, chalk] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 270, y: 150), startRadius: 0,
                           endCenter: CGPoint(x: 270, y: 150), endRadius: 300, options: [.drawsAfterEndLocation])

    // Seven tiles between the icons, warming toward Applications, the last one orange.
    let tile: CGFloat = 8, gap: CGFloat = 8, count = 7
    let x0 = 270 - (CGFloat(count) * tile + CGFloat(count - 1) * gap) / 2
    for i in 0..<count {
        let rect = CGRect(x: x0 + CGFloat(i) * (tile + gap), y: 150 - tile / 2 - 8, width: tile, height: tile)
        let t = CGFloat(i) / CGFloat(count - 2)
        let color = i == count - 1 ? accent : rgb(tileIdle.r + (tileDone.r - tileIdle.r) * t,
                                                  tileIdle.g + (tileDone.g - tileIdle.g) * t,
                                                  tileIdle.b + (tileDone.b - tileIdle.b) * t)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()
    }

    // "Drag Foundry into Applications." in Geist, period in orange.
    let font = NSFont(name: "Geist-Regular", size: 14)!
    let line = NSMutableAttributedString(string: "Drag Foundry into Applications", attributes: [
        .font: font, .kern: -0.14, .foregroundColor: NSColor(srgbRed: 0.329, green: 0.298, blue: 0.267, alpha: 1),
    ])
    line.append(NSAttributedString(string: ".", attributes: [.font: font, .foregroundColor: NSColor(cgColor: accent)!]))
    let size = line.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    line.draw(at: NSPoint(x: (w - size.width) / 2, y: 268))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    // Finder honours PNG DPI: a 1080×720 asset at 540×360 pt displays at Retina.
    rep.size = NSSize(width: w, height: h)
    return rep
}

let out = root.appendingPathComponent("Supporting")
try render(scale: 2).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("DMGBackground.png"))
try render(scale: 1).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("DMGBackground@1x.png"))
print("Wrote DMGBackground.png and DMGBackground@1x.png to \(out.path)")
