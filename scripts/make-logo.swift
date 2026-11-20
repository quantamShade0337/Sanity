// Generates Sanity's logo assets from one vector definition.
//
//   swift scripts/make-logo.swift <output-dir>
//
// Writes mark.png (preview), BrandMark.png, MenuBarIcon.png, MenuBarIcon@2x.png
// and AppIcon.iconset/ (turn into AppIcon.icns with `iconutil -c icns`).
//
// The mark: a solid disc, one open orbit tilted up to the right that sweeps
// in front of the disc, and a small moon where the orbit ends. Knockout gaps
// separate the orbit and moon from the disc so it reads at 16 px.
import AppKit
import CoreGraphics
import Foundation

struct Mark {
    /// Stroke and moon scale up at small sizes so the mark stays legible.
    var weight: CGFloat = 1

    // Geometry in a 1000 x 640 design box (y up).
    let box = CGSize(width: 1000, height: 640)
    let disc = CGPoint(x: 470, y: 320)
    let discRadius: CGFloat = 196
    let orbitCenter = CGPoint(x: 500, y: 318)
    let orbitRadii = CGSize(width: 452, height: 118)
    let orbitTilt: CGFloat = 16 * .pi / 180
    let orbitStart: CGFloat = 0.42          // the moon, upper right
    let orbitEnd: CGFloat = -.pi - 1.25     // hidden behind the disc, upper left
    var orbitWidth: CGFloat { 40 * weight }
    var moonRadius: CGFloat { 40 * weight }
    var gap: CGFloat { 22 * weight }

    func orbitPoint(_ t: CGFloat) -> CGPoint {
        let x = orbitRadii.width * cos(t)
        let y = orbitRadii.height * sin(t)
        return CGPoint(x: orbitCenter.x + x * cos(orbitTilt) - y * sin(orbitTilt),
                       y: orbitCenter.y + x * sin(orbitTilt) + y * cos(orbitTilt))
    }

    func arc(from start: CGFloat, to end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let steps = 240
        for i in 0...steps {
            let t = start + (end - start) * CGFloat(i) / CGFloat(steps)
            i == 0 ? path.move(to: orbitPoint(t)) : path.addLine(to: orbitPoint(t))
        }
        return path
    }

    /// Draws the mark in `color` into a context already scaled to the box.
    func draw(in ctx: CGContext, color: CGColor) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let moon = orbitPoint(orbitStart)
        // The orbit leaves the moon with a gap, like a satellite trail.
        let trailStart = orbitStart - (moonRadius + gap) / orbitRadii.width * 1.05

        // 1. Back of the orbit (sin t > 0 sections), later covered by the disc.
        ctx.setStrokeColor(color)
        ctx.setLineWidth(orbitWidth)
        ctx.addPath(arc(from: trailStart, to: orbitEnd))
        ctx.strokePath()

        // 2. The disc, with a knockout ring so the back orbit reads as behind.
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: disc.x - discRadius - gap, y: disc.y - discRadius - gap,
                                   width: 2 * (discRadius + gap), height: 2 * (discRadius + gap)))
        ctx.setBlendMode(.normal)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: disc.x - discRadius, y: disc.y - discRadius,
                                   width: 2 * discRadius, height: 2 * discRadius))

        // 3. Front of the orbit (t in -pi...0) over the disc, with a gap.
        let front = arc(from: min(0, trailStart), to: -.pi)
        // The gap only where the orbit crosses the disc, so it never cuts
        // the orbit's own back half at the far ends.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: disc.x - discRadius - 1, y: disc.y - discRadius - 1,
                                  width: 2 * discRadius + 2, height: 2 * discRadius + 2))
        ctx.clip()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(orbitWidth + 2 * gap)
        ctx.addPath(front)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(orbitWidth)
        ctx.addPath(front)
        ctx.strokePath()
        // Re-draw the right-hand stretch between the moon gap and the front.
        if trailStart > 0 {
            ctx.addPath(arc(from: trailStart, to: 0))
            ctx.strokePath()
        }

        // 4. The moon.
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: moon.x - moonRadius - gap * 0.6, y: moon.y - moonRadius - gap * 0.6,
                                   width: 2 * (moonRadius + gap * 0.6), height: 2 * (moonRadius + gap * 0.6)))
        ctx.setBlendMode(.normal)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius,
                                   width: 2 * moonRadius, height: 2 * moonRadius))
    }
}

func png(width: Int, height: Int, _ body: (CGContext) -> Void) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    body(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

/// Draws the mark into a separate transparent layer first, so knockouts
/// only clear the mark and never the background behind it.
func drawMark(_ mark: Mark, into ctx: CGContext, rect: CGRect, color: CGColor) {
    let scale = min(rect.width / mark.box.width, rect.height / mark.box.height)
    let w = Int((mark.box.width * scale).rounded(.up)), h = Int((mark.box.height * scale).rounded(.up))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let layer = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    layer.scaleBy(x: scale, y: scale)
    mark.draw(in: layer, color: color)
    let origin = CGPoint(x: rect.midX - CGFloat(w) / 2, y: rect.midY - CGFloat(h) / 2)
    ctx.draw(layer.makeImage()!, in: CGRect(origin: origin, size: CGSize(width: w, height: h)))
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let indigo = CGColor(red: 0.36, green: 0.33, blue: 0.86, alpha: 1)

// Preview and in-app mark (template).
try png(width: 1000, height: 640) { drawMark(Mark(), into: $0, rect: CGRect(x: 0, y: 0, width: 1000, height: 640), color: black) }
    .write(to: out.appendingPathComponent("mark.png"))
try png(width: 640, height: 410) { drawMark(Mark(), into: $0, rect: CGRect(x: 0, y: 0, width: 640, height: 410), color: black) }
    .write(to: out.appendingPathComponent("BrandMark.png"))

// Menu bar (template, heavier strokes for the tiny size).
for (name, w, h) in [("MenuBarIcon.png", 26, 20), ("MenuBarIcon@2x.png", 52, 40)] {
    try png(width: w, height: h) {
        drawMark(Mark(weight: 1.7), into: $0, rect: CGRect(x: 0, y: 0, width: w, height: h), color: black)
    }.write(to: out.appendingPathComponent(name))
}

// App icon: flat Sanity Indigo on the macOS icon grid, white mark.
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let data = png(width: px, height: px) { ctx in
            let s = CGFloat(px) / 1024
            let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil))
            ctx.setFillColor(indigo)
            ctx.fillPath()
            let weight: CGFloat = px <= 32 ? 1.6 : (px <= 64 ? 1.3 : 1)
            drawMark(Mark(weight: weight), into: ctx,
                     rect: body.insetBy(dx: 64 * s, dy: 120 * s), color: white)
        }
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
print("Wrote logo assets to \(out.path)")
