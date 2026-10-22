#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-app-icon.swift <input.png> <output.png>\n", stderr)
    exit(EXIT_FAILURE)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let provider = CGDataProvider(url: inputURL as CFURL),
      let source = CGImage(
        pngDataProviderSource: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
else {
    fputs("Unable to read input PNG.\n", stderr)
    exit(EXIT_FAILURE)
}

let sourceSide = min(source.width, source.height)
let cropInset = Int((Double(sourceSide) * 0.064).rounded())
let cropSide = sourceSide - cropInset * 2
let cropRect = CGRect(
    x: (source.width - cropSide) / 2,
    y: (source.height - cropSide) / 2,
    width: cropSide,
    height: cropSide
)

guard let cropped = source.cropping(to: cropRect) else {
    fputs("Unable to crop source icon.\n", stderr)
    exit(EXIT_FAILURE)
}

let canvasSize = 1_024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue

guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: canvasSize * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Unable to create icon canvas.\n", stderr)
    exit(EXIT_FAILURE)
}

let padding: CGFloat = 24
let targetRect = CGRect(
    x: padding,
    y: padding,
    width: CGFloat(canvasSize) - padding * 2,
    height: CGFloat(canvasSize) - padding * 2
)
let mask = CGPath(
    roundedRect: targetRect,
    cornerWidth: 218,
    cornerHeight: 218,
    transform: nil
)

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.addPath(mask)
context.clip()
context.interpolationQuality = .high
context.draw(cropped, in: targetRect)

guard let outputImage = context.makeImage() else {
    fputs("Unable to render icon image.\n", stderr)
    exit(EXIT_FAILURE)
}

let representation = NSBitmapImageRep(cgImage: outputImage)
guard let pngData = representation.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode output PNG.\n", stderr)
    exit(EXIT_FAILURE)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to write output PNG: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
