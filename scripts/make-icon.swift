#!/usr/bin/env swift

// Builds `res/main.icns`, `assets/icon.png` and the two DMG backgrounds from
// `res/icon-source.jpg`.
//
// The artwork is a single drawing of a sleeping cat on a plain white
// background. The cat's bounding box is measured, and the drawing is then
// centred on a drawn tile, so the cat always sits at the same optical size no
// matter how much empty canvas the drawing happens to have:
//
//   swift scripts/make-icon.swift
//
// Nothing is keyed out: the white is used for measuring only, and the artwork
// is composited with `.multiply`, so every white pixel — the background, and
// the eyes, muzzle and "zzz" *inside* the silhouette — takes the tile's colour
// and reads as a hole. That is why a JPEG's white background leaves no fringe.
//
// macOS only (AppKit + iconutil). Nothing here runs in CI.

import AppKit

let canvas: CGFloat = 1024
/// The standard macOS icon safe area: 824 of 1024, centred.
let contentSide: CGFloat = 824
let contentInset: CGFloat = 100
/// How much of the safe area's width the cat occupies. Wide drawings look
/// larger than they are, so this stays below 1.
let catWidthFraction: CGFloat = 0.86

// MARK: - Source artwork

let sourcePath = "res/icon-source.jpg"
guard let image = NSImage(contentsOfFile: sourcePath) else {
    print("cannot read \(sourcePath)")
    exit(1)
}

/// Redraws the artwork into a plain 8-bit RGBA bitmap. `NSBitmapImageRep(data:)`
/// keeps the JPEG's own colour space, and `colorAt` then fails on some
/// profiles ("Unknown number of components for colorspace model -1").
func normalized(_ image: NSImage) -> NSBitmapImageRep {
    let width = Int(image.size.width)
    let height = Int(image.size.height)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let raw = normalized(image)

/// The drawing's bounding box, found by treating anything darker than 90 %
/// luminance as ink.
///
/// Measurement only: no pixel is altered here. The cat is composited with
/// `.multiply` instead, which turns white into the tile colour for free and
/// avoids the fringe a hand-rolled alpha ramp leaves on a JPEG.
func measureDrawing(_ source: NSBitmapImageRep) -> CGRect {
    var minX = source.pixelsWide
    var maxX = 0
    var minY = source.pixelsHigh
    var maxY = 0
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide {
            guard let color = source.colorAt(x: x, y: y) else { continue }
            let luminance =
                0.2126 * color.redComponent + 0.7152 * color.greenComponent
                + 0.0722 * color.blueComponent
            guard luminance < 0.90 else { continue }
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = measureDrawing(raw)
guard bounds.width > 100, bounds.height > 100 else {
    print("could not find the drawing in \(sourcePath)")
    exit(1)
}
guard let catImage = raw.cgImage?.cropping(to: bounds) else {
    print("could not crop the drawing")
    exit(1)
}
print("artwork: \(Int(bounds.width))x\(Int(bounds.height)) at (\(Int(bounds.minX)),\(Int(bounds.minY)))")

// MARK: - Icon rendering

/// Draws the tile (rounded square, warm gradient) and the cat on top of it.
func drawIcon(in ctx: CGContext, rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: rect.width * 0.2245, cornerHeight: rect.width * 0.2245,
        transform: nil
    ))
    ctx.clip()

    let top = NSColor(srgbRed: 1.0, green: 0.976, blue: 0.949, alpha: 1)
    let bottom = NSColor(srgbRed: 1.0, green: 0.882, blue: 0.749, alpha: 1)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top.cgColor, bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    let drawWidth = rect.width * catWidthFraction
    let drawHeight = drawWidth * CGFloat(bounds.height) / CGFloat(bounds.width)
    let drawRect = CGRect(
        x: rect.midX - drawWidth / 2,
        y: rect.midY - drawHeight / 2,
        width: drawWidth,
        height: drawHeight
    )
    ctx.interpolationQuality = .high
    // Multiply, not src-over: the artwork's white background then *is* the tile
    // colour, so no keying is needed and the anti-aliased outline stays clean.
    ctx.setBlendMode(.multiply)
    ctx.draw(catImage, in: drawRect)
    ctx.setBlendMode(.normal)
    ctx.restoreGState()
}

func makeIcon(pixels: Int) -> NSBitmapImageRep {
    let scale = CGFloat(pixels) / canvas
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(
        in: ctx,
        rect: CGRect(
            x: contentInset * scale, y: contentInset * scale,
            width: contentSide * scale, height: contentSide * scale
        )
    )
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

// MARK: - Icon set → icns

let iconset = URL(fileURLWithPath: "res/main.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (file name, pixel size) — iconutil expects exactly these names.
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

var cache: [Int: NSBitmapImageRep] = [:]
for (file, pixels) in variants {
    let bitmap = cache[pixels] ?? makeIcon(pixels: pixels)
    cache[pixels] = bitmap
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent(file))
}

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        print("\(tool) failed with status \(process.terminationStatus)")
        exit(1)
    }
}

run("iconutil", ["-c", "icns", iconset.path, "-o", "res/main.icns"])
try? FileManager.default.removeItem(at: iconset)

// README artwork, from the same render so the two can never diverge.
try makeIcon(pixels: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "assets/icon.png"))

// MARK: - DMG window background

/// What `create-dmg` shows behind the app and the Applications link: the icon,
/// an arrow, nothing else. Text would need localizing, and the window explains
/// itself.
func makeDmgBackground(scale: CGFloat) -> NSBitmapImageRep {
    let width = 640 * scale
    let height = 480 * scale
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)

    let top = NSColor(srgbRed: 0.945, green: 0.898, blue: 0.808, alpha: 1)
    let bottom = NSColor(srgbRed: 0.886, green: 0.827, blue: 0.714, alpha: 1)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top.cgColor, bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 480),
        end: CGPoint(x: 640, y: 0),
        options: []
    )

    let iconSide: CGFloat = 132
    let iconRect = CGRect(x: 320 - iconSide / 2, y: 270, width: iconSide, height: iconSide)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -4), blur: 14,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.translateBy(x: iconRect.minX, y: iconRect.minY)
    ctx.scaleBy(x: iconSide / canvas, y: iconSide / canvas)
    drawIcon(
        in: ctx,
        rect: CGRect(x: contentInset, y: contentInset, width: contentSide, height: contentSide)
    )
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Arrow pointing at the Applications link.
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    let shaft = CGRect(x: 268, y: 128, width: 62, height: 13)
    ctx.addPath(CGPath(roundedRect: shaft, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.fillPath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 330, y: 149))
    head.addLine(to: CGPoint(x: 362, y: 134.5))
    head.addLine(to: CGPoint(x: 330, y: 120))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.drawPath(using: .fillStroke)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for (file, scale) in [("res/dmg/bg.png", 1.0), ("res/dmg/bg@2x.png", 2.0)] {
    let bitmap = makeDmgBackground(scale: CGFloat(scale))
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: file))
}

print("wrote res/main.icns, assets/icon.png, res/dmg/bg.png, res/dmg/bg@2x.png")
