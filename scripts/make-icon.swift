#!/usr/bin/env swift  // Draws the app icon (a pulse line on a dark squircle) and writes the  // AppIcon set. Re-run after changing the drawing:  //   scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func gradient(_ colors: [NSColor]) -> CGGradient {
    guard
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])
    else { fatalError("gradient") }
    return gradient
}

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("no bitmap context") }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let unit = size / 1024

    // macOS icon grid: 824 pt body centred on a 1024 canvas.
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit,
        color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(shape)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(shape)
    cg.clip()
    let background = gradient([
        NSColor(red: 0.13, green: 0.16, blue: 0.21, alpha: 1), NSColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1),
    ])
    cg.drawLinearGradient(background, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    let glow = gradient([
        NSColor(red: 0.36, green: 0.87, blue: 0.55, alpha: 0.30), NSColor(red: 0.36, green: 0.87, blue: 0.55, alpha: 0),
    ])
    cg.drawRadialGradient(
        glow, startCenter: CGPoint(x: 512 * unit, y: 512 * unit), startRadius: 0,
        endCenter: CGPoint(x: 512 * unit, y: 512 * unit), endRadius: 420 * unit, options: [])

    // Heartbeat bars along the bottom, like Kuma's beat bar.
    let green = NSColor(red: 0.36, green: 0.87, blue: 0.55, alpha: 1)
    for index in 0..<10 {
        let x = (196 + CGFloat(index) * 66) * unit
        let bar = CGRect(x: x, y: 214 * unit, width: 36 * unit, height: 92 * unit)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: 18 * unit, cornerHeight: 18 * unit, transform: nil))
        cg.setFillColor(
            (index == 7 ? NSColor(red: 0.86, green: 0.21, blue: 0.27, alpha: 1) : green.withAlphaComponent(0.9)).cgColor
        )
        cg.fillPath()
    }

    // Pulse line.
    let points: [(CGFloat, CGFloat)] = [
        (170, 560), (360, 560), (420, 470), (500, 760), (580, 400), (640, 560), (854, 560),
    ]
    let line = CGMutablePath()
    line.move(to: CGPoint(x: points[0].0 * unit, y: points[0].1 * unit))
    for point in points.dropFirst() { line.addLine(to: CGPoint(x: point.0 * unit, y: point.1 * unit)) }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setShadow(offset: .zero, blur: 40 * unit, color: green.withAlphaComponent(0.9).cgColor)
    cg.addPath(line)
    cg.setStrokeColor(green.cgColor)
    cg.setLineWidth(46 * unit)
    cg.strokePath()
    cg.restoreGState()

    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    return png
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try (String(decoding: json, as: UTF8.self) + "\n").write(
    to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) images to \(output.path)")
