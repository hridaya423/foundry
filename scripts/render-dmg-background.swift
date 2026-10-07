#!/usr/bin/env swift
// Renders the Foundry DMG window background: warm foundry-dark gradient with a
// subtle ember arrow pointing from the app icon (left) to Applications (right).
// Layout contract: 540×360 pt window, icons at {130,150} and {410,150} — the
// same coordinates used by the Finder layout in scripts/package-dmg.sh.
// Output: Supporting/DMGBackground.png (@2x, 1080×720) and DMGBackground@1x.png.
// Usage: swift scripts/render-dmg-background.swift

import AppKit
import CoreGraphics
import Foundation

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

private func render(w: CGFloat, h: CGFloat, scale: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: w * scale, height: h * scale))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); fatalError("no ctx") }
    let s = scale
    let W = w * s, H = h * s

    // 1. Warm dark gradient — same family as the app icon background.
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0x24 / 255, 0x1e / 255, 0x19 / 255),
        rgb(0x15 / 255, 0x12 / 255, 0x0f / 255),
        rgb(0x0f / 255, 0x0d / 255, 0x0c / 255),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // 2. Soft ember bloom centered between the two icons.
    let cx = W * 0.5, cy = H - 150 * s // CG y-up: icon row sits 150pt from top
    let bloom = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.16),
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.05),
        rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.0),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: 120 * s, options: [])

    // 3. Arrow: rounded shaft + chevron head, spanning the gap between icons.
    // Icons (96pt) at centers {130,150} / {410,150}: app edge ~178, Apps edge ~362.
    let arrowY = H - 150 * s
    let x0 = 216 * s, x1 = 324 * s
    let lw = 2.5 * s
    ctx.setStrokeColor(rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.75))
    ctx.setFillColor(rgb(0xfa / 255, 0x64 / 255, 0x28 / 255, 0.75))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: x0, y: arrowY))
    shaft.addLine(to: CGPoint(x: x1, y: arrowY))
    ctx.addPath(shaft)
    ctx.strokePath()
    // Chevron head
    let head = CGMutablePath()
    head.move(to: CGPoint(x: x1 - 9 * s, y: arrowY + 7 * s))
    head.addLine(to: CGPoint(x: x1 + 2 * s, y: arrowY))
    head.addLine(to: CGPoint(x: x1 - 9 * s, y: arrowY - 7 * s))
    ctx.addPath(head)
    ctx.strokePath()

    // 4. Micro-label under the arrow.
    let label = "DRAG TO INSTALL" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10.5 * s, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 0.55),
        .kern: 2.4 * s,
    ]
    let size = label.size(withAttributes: attrs)
    label.draw(at: NSPoint(x: cx - size.width / 2, y: arrowY - 34 * s), withAttributes: attrs)

    img.unlockFocus()
    return img
}

private func writePNG(_ image: NSImage, to url: URL, points: NSSize) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        throw NSError(domain: "render-dmg-background", code: 1)
    }
    // Finder renders DMG backgrounds in points, honoring PNG DPI metadata.
    // Setting `size` to the logical pt dims writes a matching pHYs chunk so a
    // 1080×720 asset displays as 540×360 pt instead of cropping at 1px=1pt.
    rep.size = points
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-dmg-background", code: 1)
    }
    try png.write(to: url)
}

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Supporting")
try writePNG(render(w: 540, h: 360, scale: 2),
             to: outDir.appendingPathComponent("DMGBackground.png"),
             points: NSSize(width: 540, height: 360))
try writePNG(render(w: 540, h: 360, scale: 1),
             to: outDir.appendingPathComponent("DMGBackground@1x.png"),
             points: NSSize(width: 540, height: 360))
print("Wrote DMGBackground.png (1080×720 @144dpi) + DMGBackground@1x.png → \(outDir.path)")
