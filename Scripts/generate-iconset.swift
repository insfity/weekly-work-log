import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("用法：swift generate-iconset.swift <source.png> <output.iconset>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("无法读取图标源文件：\(sourceURL.path)\n", stderr)
    exit(1)
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for variant in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("无法创建 \(variant.pixels)px 位图\n", stderr)
        exit(1)
    }

    bitmap.size = NSSize(width: variant.pixels, height: variant.pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels).fill()
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("无法编码 \(variant.name)\n", stderr)
        exit(1)
    }
    try png.write(to: outputURL.appendingPathComponent(variant.name), options: .atomic)
}
