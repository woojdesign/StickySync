// Generates the StickySync app icon (concept A: a butter sticky note with a
// dog-eared corner) at every macOS AppIcon resolution, straight into the asset
// catalog. Pure Core Graphics — no external image tools.
//
//   swift scripts/make_icon.swift            # writes into the default appiconset
//   swift scripts/make_icon.swift <outDir>   # or a custom directory
//
// Re-run after tweaking colors/geometry below, then rebuild the app.

import AppKit
import CoreGraphics
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "StickySync/StickySync/Assets.xcassets/AppIcon.appiconset"

// Colors (butter sticky note)
let butterTop = CGColor(red: 1.000, green: 0.890, blue: 0.557, alpha: 1) // #FFE38E
let butterBot = CGColor(red: 0.961, green: 0.753, blue: 0.216, alpha: 1) // #F5C037
let inkColor  = CGColor(red: 0.588, green: 0.400, blue: 0.055, alpha: 0.5) // #96660E @50%
let foldFill  = CGColor(red: 0.890, green: 0.651, blue: 0.165, alpha: 1) // #E3A62A
let foldLine  = CGColor(red: 0.776, green: 0.557, blue: 0.098, alpha: 1) // #C68E19

func icon(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Flip to a top-left origin so the layout reads like the SVG mockup.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // Apple's icon grid: rounded square ~80.4% of the canvas, continuous corner.
    let margin = s * 0.098
    let W = s - 2 * margin
    let rect = CGRect(x: margin, y: margin, width: W, height: W)
    let radius = W * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()

    // Butter body (vertical gradient, light top → deeper bottom).
    let grad = CGGradient(colorsSpace: space,
                          colors: [butterTop, butterBot] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY),
                           options: [])

    // Three text lines.
    ctx.setFillColor(inkColor)
    let lineH = W * 0.064
    let lineX = rect.minX + W * 0.164
    for (yFrac, wFrac) in [(0.235, 0.57), (0.400, 0.66), (0.565, 0.40)] {
        let r = CGRect(x: lineX, y: rect.minY + W * CGFloat(yFrac),
                       width: W * CGFloat(wFrac), height: lineH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        ctx.fillPath()
    }

    // Dog-eared bottom-right corner.
    let fold = W * 0.26
    let br = CGPoint(x: rect.maxX, y: rect.maxY)
    let up = CGPoint(x: br.x, y: br.y - fold)
    let left = CGPoint(x: br.x - fold, y: br.y)
    ctx.setFillColor(foldFill)
    ctx.beginPath(); ctx.move(to: up); ctx.addLine(to: left); ctx.addLine(to: br); ctx.closePath(); ctx.fillPath()
    ctx.setStrokeColor(foldLine)
    ctx.setLineWidth(max(1, s * 0.014))
    ctx.setLineCap(.round)
    ctx.beginPath(); ctx.move(to: up); ctx.addLine(to: left); ctx.strokePath()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to encode \(path)\n", stderr); exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  (\(image.width)px)")
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(icon(px), "\(outDir)/icon_\(px).png")
}
