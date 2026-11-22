import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_icon.swift <output.png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))

image.lockFocus()
guard let context = NSGraphicsContext.current else {
    fputs("could not create graphics context\n", stderr)
    exit(1)
}
context.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

let backgroundRect = NSRect(x: 62, y: 62, width: canvas - 124, height: canvas - 124)
let background = NSBezierPath(
    roundedRect: backgroundRect,
    xRadius: 210,
    yRadius: 210
)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.white.setFill()
background.fill()

NSGraphicsContext.current?.saveGraphicsState()
NSShadow().set()
NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
background.lineWidth = 7
background.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

let colors: [NSColor] = [
    NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.04, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),
    NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.58, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.18, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.19, green: 0.84, blue: 0.78, alpha: 1)
]

let square: CGFloat = 142
let gap: CGFloat = 54
let gridSize = square * 3 + gap * 2
let gridOrigin = (canvas - gridSize) / 2

for index in 0..<9 {
    let column = CGFloat(index % 3)
    let rowFromTop = CGFloat(index / 3)
    let x = gridOrigin + column * (square + gap)
    let y = gridOrigin + (2 - rowFromTop) * (square + gap)
    let rect = NSRect(x: x, y: y, width: square, height: square)
    let path = NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36)

    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
    tileShadow.shadowBlurRadius = 8
    tileShadow.shadowOffset = NSSize(width: 0, height: -3)
    tileShadow.set()
    colors[index].setFill()
    path.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    fputs("could not encode png\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
