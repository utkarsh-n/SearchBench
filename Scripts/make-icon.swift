import AppKit

let edge = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: edge, pixelsHigh: edge,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: edge * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.025, green: 0.065, blue: 0.07, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: edge, height: edge)).fill()
let panel = NSBezierPath(roundedRect: NSRect(x: 168, y: 140, width: 688, height: 744), xRadius: 84, yRadius: 84)
NSColor(srgbRed: 0.075, green: 0.13, blue: 0.14, alpha: 1).setFill()
panel.fill()
NSColor(srgbRed: 0.24, green: 0.38, blue: 0.39, alpha: 1).setStroke()
panel.lineWidth = 5
panel.stroke()
for (index, width) in [320.0, 414.0, 265.0].enumerated() {
    let path = NSBezierPath(roundedRect: NSRect(x: 270, y: 286 + Double(index) * 88,
                                              width: width, height: 22), xRadius: 11, yRadius: 11)
    NSColor(srgbRed: 0.21, green: 0.79, blue: 0.86, alpha: 0.45).setFill()
    path.fill()
}
let ring = NSBezierPath(ovalIn: NSRect(x: 325, y: 424, width: 300, height: 300))
NSColor(srgbRed: 0.70, green: 0.94, blue: 0.97, alpha: 1).setStroke()
ring.lineWidth = 43
ring.stroke()
let handle = NSBezierPath()
handle.move(to: NSPoint(x: 578, y: 465))
handle.line(to: NSPoint(x: 705, y: 338))
handle.lineWidth = 48
handle.lineCapStyle = .round
handle.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
