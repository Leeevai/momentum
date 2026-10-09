// Draws the Momentum app icon and writes every size the macOS asset catalog needs.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create a \(pixels)px bitmap")
    }
    NSGraphicsContext.current = context
    let cg = context.cgContext

    // Full-bleed background; macOS applies the rounded icon mask itself.
    let colors = [
        CGColor(srgbRed: 1.00, green: 0.55, blue: 0.20, alpha: 1),
        CGColor(srgbRed: 0.93, green: 0.22, blue: 0.42, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.30
    let lineWidth = size * 0.085

    // Faint full track, then a bright 75% progress arc starting at 12 o'clock.
    cg.setLineCap(.round)
    cg.setLineWidth(lineWidth)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()
    cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
    cg.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.5, clockwise: true)
    cg.strokePath()

    // A check mark in the middle.
    cg.setLineWidth(lineWidth * 0.8)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.02))
    cg.addLine(to: CGPoint(x: center.x - radius * 0.10, y: center.y - radius * 0.30))
    cg.addLine(to: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.32))
    cg.strokePath()

    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode a \(pixels)px PNG")
    }
    return png
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try renderIcon(pixels: pixels).write(to: outputDirectory.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(outputDirectory.path)")
