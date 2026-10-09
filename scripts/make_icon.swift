// Draws the Momentum app icon and writes every size the macOS and iOS asset catalogs need.
// Usage: swift scripts/make_icon.swift [preview.png]
// Writes Momentum/Assets.xcassets/AppIcon.appiconset (macOS) and
// MomentumMobile/Assets.xcassets/AppIcon.appiconset (iOS, opaque as the App Store requires).
//
// The design: a deep indigo field, one bold ring swept from amber to violet with a glowing head
// (momentum), around a frosted glass disc holding an upward arrow. Full-bleed, since macOS and
// iOS apply the rounded mask themselves.
import AppKit

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = root.appendingPathComponent("Momentum/Assets.xcassets/AppIcon.appiconset")
let mobileDirectory = root.appendingPathComponent("MomentumMobile/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func interpolate(_ stops: [(CGFloat, UInt32)], at t: CGFloat) -> CGColor {
    func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }
    let upper = stops.firstIndex { $0.0 >= t } ?? stops.count - 1
    let lower = max(0, upper - 1)
    let span = max(0.0001, stops[upper].0 - stops[lower].0)
    let f = min(1, max(0, (t - stops[lower].0) / span))
    let a = components(stops[lower].1)
    let b = components(stops[upper].1)
    return CGColor(srgbRed: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: 1)
}

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("bitmap") }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let center = CGPoint(x: size / 2, y: size / 2)

    // Background: indigo to violet, lit from the top left.
    let background = CGGradient(colorsSpace: space, colors: [color(0x2A1B6E), color(0x14103A), color(0x0B0A24)] as CFArray, locations: [0, 0.55, 1])!
    cg.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0x7B4DFF, 0.55), color(0x7B4DFF, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: size * 0.25, y: size * 0.82), startRadius: 0,
                          endCenter: CGPoint(x: size * 0.25, y: size * 0.82), endRadius: size * 0.75, options: [])
    let warm = CGGradient(colorsSpace: space, colors: [color(0xFF4F8B, 0.28), color(0xFF4F8B, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(warm, startCenter: CGPoint(x: size * 0.85, y: size * 0.12), startRadius: 0,
                          endCenter: CGPoint(x: size * 0.85, y: size * 0.12), endRadius: size * 0.6, options: [])

    let radius = size * 0.315
    let width = size * 0.105
    let start = CGFloat.pi / 2              // 12 o'clock
    let sweep = CGFloat.pi * 2 * 0.82       // most of the way round
    let end = start - sweep

    // Track.
    cg.setLineWidth(width)
    cg.setLineCap(.round)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    // The ring: a stroked arc filled with a conic sweep, with a soft glow under it.
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    let stroke = arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: size * 0.06, color: color(0xFF5C8A, 0.7))
    cg.addPath(stroke)
    cg.setFillColor(color(0xFF6A7A))
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(stroke)
    cg.clip()
    // A conic sweep, drawn as thin wedges: violet at the tail (12 o'clock) to amber at the head.
    let stops: [(CGFloat, UInt32)] = [(0, 0x8A5CFF), (0.25, 0xD94BD0), (0.5, 0xFF5C8A), (0.75, 0xFF8A4C), (1, 0xFFC94A)]
    let wedges = 720
    for index in 0..<wedges {
        let t0 = CGFloat(index) / CGFloat(wedges)
        let t1 = CGFloat(index + 1) / CGFloat(wedges)
        let a0 = start - sweep * t0 + 0.004
        let a1 = start - sweep * t1 - 0.004
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius + width, startAngle: a0, endAngle: a1, clockwise: true)
        wedge.closeSubpath()
        cg.addPath(wedge)
        cg.setFillColor(interpolate(stops, at: t0))
        cg.fillPath()
    }
    // The round cap at the tail sits before the sweep starts: give it the tail color.
    cg.setFillColor(color(0x8A5CFF))
    let tail = CGMutablePath()
    tail.move(to: center)
    tail.addArc(center: center, radius: radius + width, startAngle: start + 0.5, endAngle: start, clockwise: true)
    cg.addPath(tail)
    cg.fillPath()
    cg.restoreGState()

    // The ring's head: a bright, glowing cap where the motion is.
    let head = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: size * 0.05, color: color(0xFFE08A, 0.95))
    cg.setFillColor(color(0xFFE9A8))
    cg.fillEllipse(in: CGRect(x: head.x - width * 0.42, y: head.y - width * 0.42, width: width * 0.84, height: width * 0.84))
    cg.restoreGState()

    // Glass highlight along the top of the ring.
    cg.saveGState()
    cg.addPath(stroke)
    cg.clip()
    let shine = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.45), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(shine, start: CGPoint(x: center.x, y: center.y + radius + width / 2), end: CGPoint(x: center.x, y: center.y + radius - width * 0.1), options: [])
    cg.restoreGState()

    // Frosted glass disc in the middle.
    let discRadius = radius - width * 0.95
    let disc = CGRect(x: center.x - discRadius, y: center.y - discRadius, width: discRadius * 2, height: discRadius * 2)
    cg.saveGState()
    cg.addEllipse(in: disc)
    cg.clip()
    let frost = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0.06)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(frost, start: CGPoint(x: center.x, y: disc.maxY), end: CGPoint(x: center.x, y: disc.minY), options: [])
    cg.restoreGState()
    cg.setLineWidth(size * 0.006)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
    cg.strokeEllipse(in: disc.insetBy(dx: size * 0.003, dy: size * 0.003))

    // An upward arrow: momentum.
    let arrowWidth = size * 0.052
    cg.setLineWidth(arrowWidth)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02, color: CGColor(gray: 0, alpha: 0.35))
    let tip = CGPoint(x: center.x + discRadius * 0.34, y: center.y + discRadius * 0.34)
    cg.move(to: CGPoint(x: center.x - discRadius * 0.36, y: center.y - discRadius * 0.36))
    cg.addLine(to: tip)
    cg.move(to: CGPoint(x: tip.x - discRadius * 0.42, y: tip.y))
    cg.addLine(to: tip)
    cg.addLine(to: CGPoint(x: tip.x, y: tip.y - discRadius * 0.42))
    cg.strokePath()
    cg.restoreGState()

    NSGraphicsContext.current = nil
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

/// The same image without an alpha channel: iOS app icons must be opaque.
func opaquePNG(_ rep: NSBitmapImageRep) -> Data {
    guard let image = rep.cgImage,
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("opaque context") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flattened = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: flattened).representation(using: .png, properties: [:]) else { fatalError("opaque png") }
    return data
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try png(renderIcon(pixels: points * scale)).write(to: outputDirectory.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outputDirectory.appendingPathComponent("Contents.json"))

// iOS: one opaque 1024 image, which Xcode scales for every device.
let large = renderIcon(pixels: 1024)
try FileManager.default.createDirectory(at: mobileDirectory, withIntermediateDirectories: true)
try opaquePNG(large).write(to: mobileDirectory.appendingPathComponent("icon_1024.png"))
let mobileContents: [String: Any] = [
    "images": [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024.png"]],
    "info": ["author": "xcode", "version": 1],
]
try JSONSerialization.data(withJSONObject: mobileContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: mobileDirectory.appendingPathComponent("Contents.json"))
if arguments.count > 1 {
    try png(large).write(to: URL(fileURLWithPath: arguments[1]))
}
print("Wrote \(images.count) macOS icon images and the iOS icon")
