// Draws the Momentum app icon and writes every size the macOS, iOS and watchOS asset catalogs need.
// Usage: swift scripts/make_icon.swift [preview.png]
// Writes Momentum/Assets.xcassets/AppIcon.appiconset (macOS),
// MomentumMobile/Assets.xcassets/AppIcon.appiconset (iOS: opaque as the App Store requires, plus
// the dark and tinted versions iOS 18 shows on a dark or tinted Home Screen) and
// MomentumWatch/Assets.xcassets/AppIcon.appiconset (watchOS, which masks it to a circle).
//
// The design: a warm paper field and one spiral ribbon that opens out from a fine indigo thread at
// its heart, through violet and coral, to a bold orange head at the upper right. Small steps, compounding into momentum.
// `MomentumSpiral` in Shared/MomentumMark.swift draws the same spiral in the app: keep the two in
// step. Full-bleed, since macOS, iOS and watchOS apply their masks themselves.
import AppKit

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = root.appendingPathComponent("Momentum/Assets.xcassets/AppIcon.appiconset")
let mobileDirectory = root.appendingPathComponent("MomentumMobile/Assets.xcassets/AppIcon.appiconset")
let watchDirectory = root.appendingPathComponent("MomentumWatch/Assets.xcassets/AppIcon.appiconset")

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

/// The spiral, in a unit square with y up: a logarithmic spiral of 2.2 turns whose ribbon
/// thickens as it opens, centred on its own bounds.
enum Spiral {
    static let turns: CGFloat = 2.2
    static let innerRadius: CGFloat = 0.03
    static let outerRadius: CGFloat = 0.34
    static let total = turns * 2 * .pi
    static let growth = log(outerRadius / innerRadius) / total

    /// The ribbon's half-width at `t` (0 at the heart, 1 at the head).
    static func halfWidth(_ t: CGFloat) -> CGFloat { 0.004 + 0.058 * pow(t, 1.4) }

    /// The centre line at `t`, before centring.
    static func raw(_ t: CGFloat) -> CGPoint {
        let theta = total * t
        let r = innerRadius * exp(growth * theta)
        let angle = theta - total + .pi * 0.3
        return CGPoint(x: r * cos(angle), y: r * sin(angle))
    }

    static let samples: [(point: CGPoint, halfWidth: CGFloat, t: CGFloat)] = {
        let raw = (0...1400).map { i -> (CGPoint, CGFloat, CGFloat) in
            let t = CGFloat(i) / 1400
            return (Spiral.raw(t), halfWidth(t), t)
        }
        let minX = raw.map { $0.0.x - $0.1 }.min()!, maxX = raw.map { $0.0.x + $0.1 }.max()!
        let minY = raw.map { $0.0.y - $0.1 }.min()!, maxY = raw.map { $0.0.y + $0.1 }.max()!
        let dx = 0.5 - (minX + maxX) / 2, dy = 0.5 - (minY + maxY) / 2
        return raw.map { (CGPoint(x: $0.0.x + dx, y: $0.0.y + dy), $0.1, $0.2) }
    }()
}

/// The Home Screen appearances iOS draws an icon in.
enum Style {
    /// The full icon, on its paper field.
    case standard
    /// No field: iOS puts the mark on its own dark background.
    case dark
    /// Shades of white on nothing, which iOS colors with the user's tint.
    case tinted
}

func renderIcon(pixels: Int, style: Style = .standard) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("bitmap") }
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previous }
    let cg = context.cgContext
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let tinted = style == .tinted

    // Background: warm paper, lit from the top left. The dark and tinted icons have none.
    if style == .standard {
        let background = CGGradient(colorsSpace: space, colors: [color(0xFBF7F0), color(0xF3ECE1), color(0xE9DFD0)] as CFArray, locations: [0, 0.5, 1])!
        cg.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        let light = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        let center = CGPoint(x: size * 0.2, y: size * 0.82)
        cg.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.7, options: [])
    }

    // The ribbon, stamped as overlapping discs along the spiral, inside one layer so its glow is
    // a single shape. Indigo at the heart through violet and coral to orange at the head; tinted,
    // grey to white, so the tint deepens toward the head. The glow is stronger on the dark icon.
    let stops: [(CGFloat, UInt32)] = tinted
        ? [(0, 0x6A6A6A), (1, 0xFFFFFF)]
        : [(0, 0x3B3BD6), (0.45, 0x7A3FE0), (0.75, 0xFF5A5F), (1, 0xFF8A3D)]
    let glow = tinted ? CGColor(gray: 1, alpha: 0.35) : color(0xFF5A5F, style == .dark ? 0.5 : 0.25)
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: size * 0.05, color: glow)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    for sample in Spiral.samples {
        let r = sample.halfWidth * size
        cg.setFillColor(interpolate(stops, at: sample.t))
        cg.fillEllipse(in: CGRect(x: sample.point.x * size - r, y: sample.point.y * size - r, width: r * 2, height: r * 2))
    }
    cg.endTransparencyLayer()
    cg.restoreGState()

    // The head: a bright, glowing cap where the motion is.
    let head = Spiral.samples.last!
    let headRadius = head.halfWidth * size
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: headRadius * 1.6, color: tinted ? CGColor(gray: 1, alpha: 0.95) : color(0xFFB37A, 0.95))
    cg.setFillColor(CGColor(gray: 1, alpha: 1))
    cg.fillEllipse(in: CGRect(x: head.point.x * size - headRadius * 0.5, y: head.point.y * size - headRadius * 0.5,
                              width: headRadius, height: headRadius))
    cg.restoreGState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

/// The same image without an alpha channel: iOS and watchOS app icons must be opaque.
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

// Everything is drawn first and written last, each file atomically, so a failure leaves the
// catalogs as they were rather than with the icon half replaced.
var files: [(URL, Data)] = []
func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        files.append((outputDirectory.appendingPathComponent(filename), png(renderIcon(pixels: points * scale))))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
files.append((outputDirectory.appendingPathComponent("Contents.json"),
              try json(["images": images, "info": ["author": "xcode", "version": 1]])))

// iOS: one opaque 1024 image, which Xcode scales for every device, and its dark and tinted
// versions (these may be transparent: iOS draws its own background behind them).
let large = renderIcon(pixels: 1024)
files.append((mobileDirectory.appendingPathComponent("icon_1024.png"), opaquePNG(large)))
files.append((mobileDirectory.appendingPathComponent("icon_1024_dark.png"), png(renderIcon(pixels: 1024, style: .dark))))
files.append((mobileDirectory.appendingPathComponent("icon_1024_tinted.png"), png(renderIcon(pixels: 1024, style: .tinted))))
func appearance(_ value: String) -> [[String: String]] { [["appearance": "luminosity", "value": value]] }
files.append((mobileDirectory.appendingPathComponent("Contents.json"), try json([
    "images": [
        ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024.png"],
        ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024_dark.png", "appearances": appearance("dark")],
        ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024_tinted.png", "appearances": appearance("tinted")],
    ],
    "info": ["author": "xcode", "version": 1],
])))

// watchOS: one opaque 1024 image, which the watch masks to a circle (its Contents.json names it).
files.append((watchDirectory.appendingPathComponent("icon_1024.png"), opaquePNG(large)))

if arguments.count > 1 {
    files.append((URL(fileURLWithPath: arguments[1]), png(large)))
}
for directory in [outputDirectory, mobileDirectory, watchDirectory] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
for (url, data) in files {
    try data.write(to: url, options: .atomic)
}
print("Wrote \(images.count) macOS icon images, the iOS icon and the watch icon")
