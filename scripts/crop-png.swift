import AppKit
import Foundation

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 7 else {
    fail("Usage: crop-png.swift <input> <output> <x> <y> <width> <height>")
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let x = Int(CommandLine.arguments[3]),
      let y = Int(CommandLine.arguments[4]),
      let width = Int(CommandLine.arguments[5]),
      let height = Int(CommandLine.arguments[6]) else {
    fail("Crop coordinates must be integers")
}

guard let image = NSImage(contentsOfFile: inputPath) else {
    fail("Unable to read image: \(inputPath)")
}

var proposedRect = NSRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fail("Unable to decode image: \(inputPath)")
}

let cropRect = CGRect(x: x, y: y, width: width, height: height)
guard cropRect.minX >= 0,
      cropRect.minY >= 0,
      cropRect.maxX <= CGFloat(cgImage.width),
      cropRect.maxY <= CGFloat(cgImage.height) else {
    fail("Crop rectangle is outside image bounds")
}

guard let cropped = cgImage.cropping(to: cropRect) else {
    fail("Unable to crop image")
}

let bitmap = NSBitmapImageRep(cgImage: cropped)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fail("Unable to encode PNG")
}

try data.write(to: URL(fileURLWithPath: outputPath))
