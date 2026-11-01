#!/usr/bin/env swift
// Original ATPlayer brand artwork. CC0 1.0 Universal.
// Produces matching vector SVG and opaque sRGB PNG from the same geometry.
import Foundation
import CoreGraphics
import ImageIO

let width = 5244
let height = 2950
let center = CGPoint(x: 2622, y: 1475)
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let canvas = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Cannot create opaque RGB canvas") }
canvas.translateBy(x: 0, y: CGFloat(height))
canvas.scaleBy(x: 1, y: -1)
canvas.setShouldAntialias(true)
var definitions: [String] = []
var elements: [String] = []

func number(_ value: CGFloat) -> String { String(format: "%.3f", Double(value)) }
func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: colorSpace, components: [
        CGFloat((value >> 16) & 255) / 255,
        CGFloat((value >> 8) & 255) / 255,
        CGFloat(value & 255) / 255, alpha
    ])!
}
func gradient(_ colors: [CGColor], _ positions: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: positions)!
}
func linearFill(_ id: String, rect: CGRect, start: CGPoint, end: CGPoint,
                first: String, last: String, ellipse: Bool = false) {
    definitions.append("<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(number(start.x))\" y1=\"\(number(start.y))\" x2=\"\(number(end.x))\" y2=\"\(number(end.y))\"><stop stop-color=\"\(first)\"/><stop offset=\"1\" stop-color=\"\(last)\"/></linearGradient>")
    canvas.saveGState()
    if ellipse {
        canvas.addEllipse(in: rect)
        elements.append("<ellipse cx=\"\(number(rect.midX))\" cy=\"\(number(rect.midY))\" rx=\"\(number(rect.width / 2))\" ry=\"\(number(rect.height / 2))\" fill=\"url(#\(id))\"/>")
    } else {
        canvas.addRect(rect)
        elements.append("<rect x=\"\(number(rect.minX))\" y=\"\(number(rect.minY))\" width=\"\(number(rect.width))\" height=\"\(number(rect.height))\" fill=\"url(#\(id))\"/>")
    }
    canvas.clip()
    canvas.drawLinearGradient(gradient([color(first), color(last)], [0, 1]), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    canvas.restoreGState()
}
func glow(_ id: String, at point: CGPoint, radius: CGFloat, hex: String, opacity: CGFloat) {
    definitions.append("<radialGradient id=\"\(id)\"><stop stop-color=\"\(hex)\" stop-opacity=\"\(number(opacity))\"/><stop offset=\"1\" stop-color=\"\(hex)\" stop-opacity=\"0\"/></radialGradient>")
    elements.append("<circle cx=\"\(number(point.x))\" cy=\"\(number(point.y))\" r=\"\(number(radius))\" fill=\"url(#\(id))\"/>")
    canvas.drawRadialGradient(gradient([color(hex, opacity), color(hex, 0)], [0, 1]), startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
}
func circle(at point: CGPoint, radius: CGFloat, hex: String, opacity: CGFloat, lineWidth: CGFloat) {
    elements.append("<circle cx=\"\(number(point.x))\" cy=\"\(number(point.y))\" r=\"\(number(radius))\" fill=\"none\" stroke=\"\(hex)\" stroke-opacity=\"\(number(opacity))\" stroke-width=\"\(number(lineWidth))\"/>")
    canvas.setStrokeColor(color(hex, opacity))
    canvas.setLineWidth(lineWidth)
    canvas.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}
func line(from start: CGPoint, to end: CGPoint, hex: String, opacity: CGFloat, lineWidth: CGFloat) {
    elements.append("<path d=\"M\(number(start.x)) \(number(start.y))L\(number(end.x)) \(number(end.y))\" fill=\"none\" stroke=\"\(hex)\" stroke-opacity=\"\(number(opacity))\" stroke-width=\"\(number(lineWidth))\" stroke-linecap=\"round\"/>")
    canvas.setStrokeColor(color(hex, opacity))
    canvas.setLineWidth(lineWidth)
    canvas.setLineCap(.round)
    canvas.beginPath()
    canvas.move(to: start)
    canvas.addLine(to: end)
    canvas.strokePath()
}

// Existing ATPlayer brand palette: quiet forest, sage and cream.
linearFill("background", rect: CGRect(x: 0, y: 0, width: width, height: height),
           start: .zero, end: CGPoint(x: width, y: height), first: "#0b1411", last: "#1b2d24")
glow("atmosphere", at: CGPoint(x: center.x + 260, y: center.y - 200), radius: 2290, hex: "#537f66", opacity: 0.27)
glow("tealAtmosphere", at: CGPoint(x: center.x - 1320, y: center.y + 550), radius: 1600, hex: "#2d7165", opacity: 0.13)

// Quiet audio rhythm outside the central artwork; decorative and crop-safe.
for side in [-1.0, 1.0] {
    for index in 0..<22 {
        let progress = CGFloat(index) / 21
        let distance = 1010 + CGFloat(index) * 61
        let x = center.x + CGFloat(side) * distance
        let pulse = 74 + 245 * pow(sin(CGFloat(index) * 0.56 + 0.45), 2)
        let length = pulse * (1 - 0.68 * progress)
        line(from: CGPoint(x: x, y: center.y - length / 2),
             to: CGPoint(x: x, y: center.y + length / 2),
             hex: "#8ebaa0", opacity: 0.24 * (1 - 0.78 * progress), lineWidth: 12)
    }
}
circle(at: center, radius: 1025, hex: "#a9ccba", opacity: 0.045, lineWidth: 2)
circle(at: center, radius: 958, hex: "#a9ccba", opacity: 0.065, lineWidth: 2)
glow("dialShadow", at: CGPoint(x: center.x + 12, y: center.y + 140), radius: 850, hex: "#000000", opacity: 0.52)

// Radial waveform follows the rhythm of the repository's original banner art.
for index in 0..<64 {
    let angle = 2 * CGFloat.pi * CGFloat(index) / 64 - CGFloat.pi / 2
    let length = 55 + 105 * pow(sin(CGFloat(index) * 0.72), 2) + 45 * pow(cos(CGFloat(index) * 0.27), 2)
    let inner: CGFloat = 740
    let start = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
    let end = CGPoint(x: center.x + cos(angle) * (inner + length), y: center.y + sin(angle) * (inner + length))
    let opacity = 0.53 + 0.22 * (cos(angle + 0.75) + 1) / 2
    line(from: start, to: end, hex: "#a9ccba", opacity: opacity, lineWidth: 15)
}

let radius: CGFloat = 654
linearFill("dial", rect: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
           start: CGPoint(x: center.x - 560, y: center.y - 640),
           end: CGPoint(x: center.x + 560, y: center.y + 640), first: "#294437", last: "#111e18", ellipse: true)
circle(at: center, radius: radius, hex: "#a9ccba", opacity: 0.29, lineWidth: 3)
circle(at: center, radius: 626, hex: "#e8f2eb", opacity: 0.06, lineWidth: 3)
circle(at: center, radius: 532, hex: "#6d947d", opacity: 0.35, lineWidth: 7)
circle(at: center, radius: 510, hex: "#000000", opacity: 0.17, lineWidth: 2)
glow("playGlow", at: CGPoint(x: center.x + 15, y: center.y - 20), radius: 440, hex: "#98bda5", opacity: 0.11)

// Original rounded geometric play mark, not a font glyph or imported icon.
let play = CGMutablePath()
let x = center.x
let y = center.y
play.move(to: CGPoint(x: x - 130, y: y - 224))
play.addQuadCurve(to: CGPoint(x: x - 174, y: y - 195), control: CGPoint(x: x - 174, y: y - 250))
play.addLine(to: CGPoint(x: x - 174, y: y + 195))
play.addQuadCurve(to: CGPoint(x: x - 130, y: y + 224), control: CGPoint(x: x - 174, y: y + 250))
play.addLine(to: CGPoint(x: x + 227, y: y + 28))
play.addQuadCurve(to: CGPoint(x: x + 227, y: y - 28), control: CGPoint(x: x + 278, y: y))
play.closeSubpath()
canvas.setFillColor(color("#c5dfcd"))
canvas.addPath(play)
canvas.fillPath()
elements.append("<path d=\"M\(number(x - 130)) \(number(y - 224))Q\(number(x - 174)) \(number(y - 250)) \(number(x - 174)) \(number(y - 195))L\(number(x - 174)) \(number(y + 195))Q\(number(x - 174)) \(number(y + 250)) \(number(x - 130)) \(number(y + 224))L\(number(x + 227)) \(number(y + 28))Q\(number(x + 278)) \(number(y)) \(number(x + 227)) \(number(y - 28))Z\" fill=\"#c5dfcd\"/>")

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" role="img" aria-labelledby="title desc">
<title id="title">ATPlayer original audio brand artwork</title>
<desc id="desc">An original circular play motif surrounded by a radial waveform, on a dark forest and teal background. Text-free brand illustration, not an app screenshot.</desc>
<defs>
\(definitions.joined(separator: "\n"))
</defs>
\(elements.joined(separator: "\n"))
</svg>

"""
try svg.write(to: output.appendingPathComponent("header-universal.svg"), atomically: true, encoding: .utf8)
guard let image = canvas.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("header-universal.png") as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("Cannot create PNG destination") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG encoding failed") }
print("Generated header-universal.svg and opaque sRGB header-universal.png: \(width) × \(height)")
