import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let factor = CGFloat(size) / 1024
    NSAffineTransform(scale: factor).concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.58, blue: 1, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.27, blue: 0.79, alpha: 1))!.draw(in: base, angle: -90)
    NSColor.white.withAlphaComponent(0.30).setStroke(); base.lineWidth = 2; base.stroke()
    NSColor(srgbRed: 0.98, green: 0.99, blue: 1, alpha: 0.94).setFill()
    NSBezierPath(roundedRect: NSRect(x: 252, y: 270, width: 246, height: 466), xRadius: 32, yRadius: 32).fill()
    NSBezierPath(roundedRect: NSRect(x: 526, y: 270, width: 246, height: 466), xRadius: 32, yRadius: 32).fill()
    NSColor(srgbRed: 0.35, green: 0.56, blue: 0.86, alpha: 1).setFill()
    for x in [CGFloat(304), CGFloat(578)] {
        for y in [CGFloat(560), CGFloat(624)] {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 142, height: 17), xRadius: 8, yRadius: 8).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
extension NSAffineTransform {
    convenience init(scale: CGFloat) { self.init(); self.scale(by: scale) }
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
