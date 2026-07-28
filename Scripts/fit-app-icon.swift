import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let scale = Double(CommandLine.arguments[3]),
      scale > 0,
      scale <= 1 else {
    fputs("用法：swift fit-app-icon.swift <source.png> <output.png> <scale 0...1>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let canvasPixels = 1024

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasPixels,
        pixelsHigh: canvasPixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
    fputs("无法读取源图标或创建输出画布。\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: canvasPixels, height: canvasPixels)
let fittedSize = CGFloat(canvasPixels) * scale
let origin = (CGFloat(canvasPixels) - fittedSize) / 2

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvasPixels, height: canvasPixels).fill()
sourceImage.draw(
    in: NSRect(x: origin, y: origin, width: fittedSize, height: fittedSize),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法编码输出 PNG。\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
