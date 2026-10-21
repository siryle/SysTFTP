import AppKit

// Compile this script with swiftc, then run it from the repository root.
// Generate both resolutions and combine them into a Retina-aware TIFF.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/DMG")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvas = NSSize(width: 640, height: 440)
let image = NSImage(size: canvas)
let ink = NSColor(srgbRed: 0.14, green: 0.20, blue: 0.31, alpha: 1)

func drawText(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(at: NSPoint(x: (canvas.width - string.size().width) / 2, y: y))
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: canvas.height)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
    let circles: [(NSRect, NSColor)] = [
        (NSRect(x: -88, y: 88, width: 224, height: 224),
         NSColor(srgbRed: 0.97, green: 0.94, blue: 0.89, alpha: 0.50)),
        (NSRect(x: -84, y: 160, width: 464, height: 464),
         NSColor(srgbRed: 0.84, green: 0.93, blue: 0.97, alpha: 0.47)),
        (NSRect(x: 345, y: 130, width: 432, height: 432),
         NSColor(srgbRed: 0.98, green: 0.88, blue: 0.92, alpha: 0.43)),
        (NSRect(x: 453, y: 352, width: 252, height: 252),
         NSColor(srgbRed: 0.88, green: 0.94, blue: 0.89, alpha: 0.44))
    ]
    for (rect, color) in circles {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    // Text uses AppKit's normal coordinate system to keep glyphs upright.
    NSGraphicsContext.saveGraphicsState()
    let textTransform = NSAffineTransform()
    textTransform.translateX(by: 0, yBy: canvas.height)
    textTransform.scaleX(by: 1, yBy: -1)
    textTransform.concat()
    drawText("SysTFTP", y: 305, size: 48, weight: .semibold, color: ink)
    drawText("将 SysTFTP 拖入「应用程序」以完成安装", y: 269, size: 15, weight: .regular,
             color: NSColor(srgbRed: 0.38, green: 0.43, blue: 0.49, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 276, y: 285))
    arrow.line(to: NSPoint(x: 364, y: 285))
    arrow.move(to: NSPoint(x: 354, y: 276))
    arrow.line(to: NSPoint(x: 364, y: 285))
    arrow.line(to: NSPoint(x: 354, y: 294))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    ink.withAlphaComponent(0.78).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(name))
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation(using: .lzw, factor: 1)!.write(
    to: outputDirectory.appendingPathComponent("background.tiff")
)
