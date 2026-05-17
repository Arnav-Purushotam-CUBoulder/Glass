import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Glass.icns")
let fileManager = FileManager.default
let workURL = outputURL.deletingLastPathComponent()
    .appendingPathComponent("Glass.iconset", isDirectory: true)

try? fileManager.removeItem(at: workURL)
try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for icon in sizes {
    let pixels = icon.points * icon.scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSGraphicsContext.current?.imageInterpolation = .high

    let radius = CGFloat(pixels) * 0.225
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(pixels) * 0.04, dy: CGFloat(pixels) * 0.04), xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.075, alpha: 1).setFill()
    background.fill()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.54, green: 0.95, blue: 1.0, alpha: 0.92),
        NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.82, alpha: 0.92),
        NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.14, alpha: 0.96)
    ])!
    gradient.draw(in: background, angle: 135)

    let glassRect = rect.insetBy(dx: CGFloat(pixels) * 0.18, dy: CGFloat(pixels) * 0.17)
    let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: CGFloat(pixels) * 0.16, yRadius: CGFloat(pixels) * 0.16)
    NSColor.white.withAlphaComponent(0.16).setFill()
    glassPath.fill()

    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: glassRect.minX + CGFloat(pixels) * 0.09, y: glassRect.maxY - CGFloat(pixels) * 0.14))
    highlight.curve(
        to: NSPoint(x: glassRect.maxX - CGFloat(pixels) * 0.13, y: glassRect.maxY - CGFloat(pixels) * 0.25),
        controlPoint1: NSPoint(x: glassRect.midX - CGFloat(pixels) * 0.1, y: glassRect.maxY + CGFloat(pixels) * 0.04),
        controlPoint2: NSPoint(x: glassRect.midX + CGFloat(pixels) * 0.18, y: glassRect.maxY - CGFloat(pixels) * 0.02)
    )
    NSColor.white.withAlphaComponent(0.42).setStroke()
    highlight.lineWidth = max(2, CGFloat(pixels) * 0.025)
    highlight.lineCapStyle = .round
    highlight.stroke()

    let inset = CGFloat(pixels) * 0.29
    let gRect = rect.insetBy(dx: inset, dy: inset)
    let gPath = NSBezierPath()
    gPath.appendArc(
        withCenter: NSPoint(x: gRect.midX, y: gRect.midY),
        radius: gRect.width * 0.48,
        startAngle: 35,
        endAngle: 330,
        clockwise: false
    )
    NSColor.white.withAlphaComponent(0.92).setStroke()
    gPath.lineWidth = max(4, CGFloat(pixels) * 0.074)
    gPath.lineCapStyle = .round
    gPath.stroke()

    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: gRect.midX + gRect.width * 0.02, y: gRect.midY))
    bar.line(to: NSPoint(x: gRect.maxX, y: gRect.midY))
    NSColor.white.withAlphaComponent(0.92).setStroke()
    bar.lineWidth = max(4, CGFloat(pixels) * 0.074)
    bar.lineCapStyle = .round
    bar.stroke()

    let bottomGlow = NSGradient(colors: [
        NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.95, alpha: 0.36),
        NSColor.clear
    ])!
    bottomGlow.draw(in: background, relativeCenterPosition: NSPoint(x: 0, y: -0.45))

    NSColor.white.withAlphaComponent(0.32).setStroke()
    background.lineWidth = max(1, CGFloat(pixels) * 0.012)
    background.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render \(icon.name)")
    }

    try png.write(to: workURL.appendingPathComponent(icon.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", workURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

try? fileManager.removeItem(at: workURL)
