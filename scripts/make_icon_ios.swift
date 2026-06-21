// Generates the iOS app icon: a full-bleed butter sticky note with ink lines.
// Unlike macOS, iOS masks the corners itself, so this is edge-to-edge — no
// squircle outline, no margin, no dog-ear (it would be clipped by the mask).
//
//   swift scripts/make_icon_ios.swift
//
// Writes a single 1024px icon into the iOS app's asset catalog.

import AppKit
import CoreGraphics
import Foundation

let outDir = "StickySync/StickySyncMobile/Assets.xcassets/AppIcon.appiconset"

let butterTop = CGColor(red: 1.000, green: 0.890, blue: 0.557, alpha: 1) // #FFE38E
let butterBot = CGColor(red: 0.961, green: 0.753, blue: 0.216, alpha: 1) // #F5C037
let inkColor  = CGColor(red: 0.557, green: 0.376, blue: 0.047, alpha: 0.55)

func icon(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)

    // Full-bleed butter gradient (light top → deeper bottom).
    let grad = CGGradient(colorsSpace: space, colors: [butterTop, butterBot] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: 0), end: CGPoint(x: s / 2, y: s), options: [])

    // Three ink lines, kept well inside the corner-mask safe area.
    ctx.setFillColor(inkColor)
    let lineH = s * 0.060
    let lineX = s * 0.205
    for (yFrac, wFrac) in [(0.30, 0.50), (0.44, 0.59), (0.58, 0.35)] {
        let r = CGRect(x: lineX, y: s * CGFloat(yFrac), width: s * CGFloat(wFrac), height: lineH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        ctx.fillPath()
    }
    return ctx.makeImage()!
}

let rep = NSBitmapImageRep(cgImage: icon(1024))
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("encode failed\n", stderr); exit(1)
}
try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_1024.png"))
print("wrote \(outDir)/icon_1024.png (1024px)")
