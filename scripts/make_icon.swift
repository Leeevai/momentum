// Draws the Momentum app icon and writes every size the macOS, iOS and watchOS asset catalogs need.
// Usage: swift scripts/make_icon.swift [preview.png]
// Writes Momentum/Assets.xcassets/AppIcon.appiconset (macOS),
// MomentumMobile/Assets.xcassets/AppIcon.appiconset (iOS: opaque as the App Store requires, plus
// the dark and tinted versions iOS 18 shows on a dark or tinted Home Screen) and
// MomentumWatch/Assets.xcassets/AppIcon.appiconset (watchOS, which masks it to a circle).
// It also draws the icons people can pick in Settings → App Icon (`Variant`): alternate app icons
// on iPhone (AppIcon-<Name>, with their dark and tinted versions), the Dock icon on the Mac
// (AppIconChoice-<Name>, shaped like a macOS icon), and a preview of each on iPhone.
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
let macCatalog = root.appendingPathComponent("Momentum/Assets.xcassets")
let mobileCatalog = root.appendingPathComponent("MomentumMobile/Assets.xcassets")

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

/// One look of the icon. Paper is the app's own; the others are the alternates people pick in
/// Settings. Each keeps the spiral and changes its ground and ribbon.
struct Variant {
    /// Its name in Settings, and in its asset names (AppIcon-<name>, AppIconChoice-<name>).
    var name: String
    /// The ground, top left to bottom right.
    var field: [UInt32]
    /// A soft white light from the top left over the ground.
    var light: CGFloat
    /// The ribbon from its heart to its head.
    var ribbon: [(CGFloat, UInt32)]
    /// The ribbon on iOS's own dark background, for the dark Home Screen.
    var darkRibbon: [(CGFloat, UInt32)]
    /// The glow under the ribbon, on its ground and on iOS's dark background.
    var glow: (color: UInt32, alpha: CGFloat, darkAlpha: CGFloat)
    /// The glow around the head's bright cap.
    var halo: UInt32

    static let colors: [(CGFloat, UInt32)] = [(0, 0x3B3BD6), (0.45, 0x7A3FE0), (0.75, 0xFF5A5F), (1, 0xFF8A3D)]
    static let silver: [(CGFloat, UInt32)] = [(0, 0x5A5A60), (1, 0xFFFFFF)]

    static let paper = Variant(name: "Paper", field: [0xFBF7F0, 0xF3ECE1, 0xE9DFD0], light: 0.6, ribbon: colors,
                               darkRibbon: colors, glow: (0xFF5A5F, 0.25, 0.5), halo: 0xFFB37A)
    /// Pure black, like dark mode.
    static let midnight = Variant(name: "Midnight", field: [0x000000, 0x000000, 0x000000], light: 0, ribbon: colors,
                                  darkRibbon: colors, glow: (0xFF5A5F, 0.5, 0.5), halo: 0xFFB37A)
    static let mono = Variant(name: "Mono", field: [0x000000, 0x000000, 0x000000], light: 0, ribbon: silver,
                              darkRibbon: silver, glow: (0xFFFFFF, 0.22, 0.22), halo: 0xFFFFFF)
    static let ink = Variant(name: "Ink", field: [0xFBF7F0, 0xF3ECE1, 0xE9DFD0], light: 0.6,
                             ribbon: [(0, 0xA49D92), (0.5, 0x5C5852), (1, 0x1C1C1E)],
                             darkRibbon: silver, glow: (0x000000, 0.12, 0.22), halo: 0x8A847A)
    static let all = [paper, midnight, mono, ink]
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

func renderIcon(pixels: Int, variant: Variant = .paper, style: Style = .standard) -> NSBitmapImageRep {
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

    // The ground, lit from the top left. The dark and tinted icons have none.
    if style == .standard {
        let background = CGGradient(colorsSpace: space, colors: variant.field.map { color($0) } as CFArray, locations: [0, 0.5, 1])!
        cg.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        if variant.light > 0 {
            let light = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: variant.light), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            let center = CGPoint(x: size * 0.2, y: size * 0.82)
            cg.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.7, options: [])
        }
    }

    // The ribbon, stamped as overlapping discs along the spiral, inside one layer so its glow is
    // a single shape. Paper's runs from indigo at the heart through violet and coral to orange at
    // the head; tinted, grey to white, so the tint deepens toward the head.
    let stops: [(CGFloat, UInt32)] = switch style {
    case .standard: variant.ribbon
    case .dark: variant.darkRibbon
    case .tinted: [(0, 0x6A6A6A), (1, 0xFFFFFF)]
    }
    let glow = tinted ? CGColor(gray: 1, alpha: 0.35) : color(variant.glow.color, style == .dark ? variant.glow.darkAlpha : variant.glow.alpha)
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
    cg.setShadow(offset: .zero, blur: headRadius * 1.6, color: tinted ? CGColor(gray: 1, alpha: 0.95) : color(variant.halo, 0.95))
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

/// The icon shaped as macOS draws app icons: a rounded square inset in its canvas, with a soft
/// shadow under it. For the Dock icon the Mac app sets while it runs.
func macShaped(_ icon: NSBitmapImageRep, pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep), let image = icon.cgImage else { fatalError("bitmap") }
    let cg = context.cgContext
    // Apple's grid: an 824-point square at 100 points in, with 185-point corners, in 1024.
    let shape = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
    let path = CGPath(roundedRect: shape, cornerWidth: size * 185 / 1024, cornerHeight: size * 185 / 1024, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 10 / 1024), blur: size * 24 / 1024, color: CGColor(gray: 0, alpha: 0.3))
    cg.addPath(path)
    cg.setFillColor(CGColor(gray: 0, alpha: 1))
    cg.fillPath()
    cg.restoreGState()
    cg.addPath(path)
    cg.clip()
    cg.draw(image, in: shape)
    return rep
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

// The icons people can pick. On iPhone, every one but Paper is an alternate app icon set with its
// dark and tinted versions (the iPhone target lists them in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES),
// and every one has a square preview for the picker. On the Mac, each is the Dock icon, already
// shaped, which the picker shows too.
var newDirectories: [URL] = []
func imageSet(_ catalog: URL, _ name: String, _ data: Data) throws {
    let directory = catalog.appendingPathComponent("\(name).imageset")
    newDirectories.append(directory)
    files.append((directory.appendingPathComponent("\(name).png"), data))
    files.append((directory.appendingPathComponent("Contents.json"), try json([
        "images": [["idiom": "universal", "filename": "\(name).png"]],
        "info": ["author": "xcode", "version": 1],
    ])))
}
for variant in Variant.all {
    let icon = renderIcon(pixels: 1024, variant: variant)
    try imageSet(mobileCatalog, "AppIconChoice-\(variant.name)", opaquePNG(renderIcon(pixels: 240, variant: variant)))
    try imageSet(macCatalog, "AppIconChoice-\(variant.name)", png(macShaped(icon, pixels: 512)))
    guard variant.name != Variant.paper.name else { continue }
    let directory = mobileCatalog.appendingPathComponent("AppIcon-\(variant.name).appiconset")
    newDirectories.append(directory)
    files.append((directory.appendingPathComponent("icon_1024.png"), opaquePNG(icon)))
    files.append((directory.appendingPathComponent("icon_1024_dark.png"), png(renderIcon(pixels: 1024, variant: variant, style: .dark))))
    files.append((directory.appendingPathComponent("icon_1024_tinted.png"), png(renderIcon(pixels: 1024, variant: variant, style: .tinted))))
    files.append((directory.appendingPathComponent("Contents.json"), try json([
        "images": [
            ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024.png"],
            ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024_dark.png", "appearances": appearance("dark")],
            ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024_tinted.png", "appearances": appearance("tinted")],
        ],
        "info": ["author": "xcode", "version": 1],
    ])))
}

if arguments.count > 1 {
    files.append((URL(fileURLWithPath: arguments[1]), png(large)))
}
for directory in [outputDirectory, mobileDirectory, watchDirectory] + newDirectories {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
for (url, data) in files {
    try data.write(to: url, options: .atomic)
}
print("Wrote \(images.count) macOS icon images, the iOS icon, the watch icon and \(Variant.all.count) icon choices")
