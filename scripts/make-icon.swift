#!/usr/bin/env swift
//
// make-icon.swift — render the Casette app icon at every macOS size.
//
// Draws a cassette tape (the "session tape" the calculator keeps) on a
// rounded-rect tile, then writes the PNGs into build/AppIcon.iconset/. The
// Makefile runs `iconutil -c icns` on that folder to produce AppIcon.icns.
//
// No assets, no dependencies — pure CoreGraphics so it runs in `swift`.

import AppKit

let iconsetDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true)

// (filename, pixel dimension) — the set iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func draw(into ctx: CGContext, size s: CGFloat) {
    // Background tile — rounded rect with a soft vertical gradient.
    let inset = s * 0.06
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = s * 0.20
    let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.18, green: 0.22, blue: 0.30, alpha: 1),
            CGColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Cassette body.
    let bodyW = tile.width * 0.66
    let bodyH = bodyW * 0.62
    let body = CGRect(
        x: tile.midX - bodyW / 2,
        y: tile.midY - bodyH / 2,
        width: bodyW, height: bodyH)
    let bodyPath = CGPath(
        roundedRect: body, cornerWidth: bodyH * 0.12, cornerHeight: bodyH * 0.12, transform: nil)
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1)) // warm tape label
    ctx.fillPath()

    // Label strip across the top third.
    let strip = CGRect(
        x: body.minX + body.width * 0.10,
        y: body.midY + body.height * 0.10,
        width: body.width * 0.80, height: body.height * 0.26)
    ctx.addPath(CGPath(roundedRect: strip, cornerWidth: strip.height * 0.25, cornerHeight: strip.height * 0.25, transform: nil))
    ctx.setFillColor(CGColor(red: 0.99, green: 0.95, blue: 0.86, alpha: 1))
    ctx.fillPath()

    // Two reels (windows) in the lower half.
    let reelR = body.height * 0.16
    let reelY = body.midY - body.height * 0.12
    for dx in [-1.0, 1.0] {
        let center = CGPoint(x: body.midX + CGFloat(dx) * body.width * 0.22, y: reelY)
        // dark window
        ctx.addEllipse(in: CGRect(
            x: center.x - reelR, y: center.y - reelR, width: reelR * 2, height: reelR * 2))
        ctx.setFillColor(CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1))
        ctx.fillPath()
        // hub
        let hub = reelR * 0.42
        ctx.addEllipse(in: CGRect(
            x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
        ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1))
        ctx.fillPath()
    }
}

for (name, px) in variants {
    let dim = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    draw(into: nsctx.cgContext, size: dim)
    nsctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("✗ failed to encode \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
}

print("✓ wrote \(variants.count) icons to \(iconsetDir)")
