// Renders the app icon (a green gem on a dark tile) into an .iconset folder.
// Usage: swift makeicon.swift OUT.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.11, alpha: 1)])!
        .draw(in: tilePath, angle: -90)

    let cx = s / 2, top = s * 0.80, mid = s * 0.52, bottom = s * 0.20, w = s * 0.20
    let light = NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.45, alpha: 1)
    let dark = NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.22, alpha: 1)
    func facet(_ pts: [NSPoint], _ c: NSColor) {
        let p = NSBezierPath()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.line(to: $0) }
        p.close()
        c.setFill()
        p.fill()
    }
    facet([NSPoint(x: cx, y: top), NSPoint(x: cx - w, y: mid), NSPoint(x: cx, y: mid)], light)
    facet([NSPoint(x: cx, y: top), NSPoint(x: cx + w, y: mid), NSPoint(x: cx, y: mid)], light.blended(withFraction: 0.25, of: dark)!)
    facet([NSPoint(x: cx, y: bottom), NSPoint(x: cx - w, y: mid), NSPoint(x: cx, y: mid)], dark.blended(withFraction: 0.2, of: light)!)
    facet([NSPoint(x: cx, y: bottom), NSPoint(x: cx + w, y: mid), NSPoint(x: cx, y: mid)], dark)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
