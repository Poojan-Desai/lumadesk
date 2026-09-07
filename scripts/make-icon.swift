import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let shape = NSBezierPath(roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.25, green: 0.28, blue: 0.65, alpha: 1), ending: NSColor(red: 0.57, green: 0.49, blue: 0.93, alpha: 1))!.draw(in: shape, angle: 55)
    let star = NSBezierPath()
    star.move(to: NSPoint(x: 512, y: 778))
    star.curve(to: NSPoint(x: 778, y: 512), controlPoint1: NSPoint(x: 548, y: 583), controlPoint2: NSPoint(x: 583, y: 548))
    star.curve(to: NSPoint(x: 512, y: 246), controlPoint1: NSPoint(x: 583, y: 476), controlPoint2: NSPoint(x: 548, y: 441))
    star.curve(to: NSPoint(x: 246, y: 512), controlPoint1: NSPoint(x: 476, y: 441), controlPoint2: NSPoint(x: 441, y: 476))
    star.curve(to: NSPoint(x: 512, y: 778), controlPoint1: NSPoint(x: 441, y: 548), controlPoint2: NSPoint(x: 476, y: 583))
    NSColor.white.setFill(); star.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
