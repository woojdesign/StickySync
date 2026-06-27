// ThemeSwatchSnapshotTests.swift
//
// Visual QA for the theme catalog. Renders each theme's 7 color slots as
// labeled swatches stacked vertically. Snapshot baselines pin the
// extracted hexes — if a future edit drifts a color or breaks contrast,
// the diff catches it before ship. Also doubles as documentation: the
// baseline PNGs *are* the canonical "what does Soft Rainbow look like"
// reference.

import XCTest
import AppKit
import SnapshotTesting
import NotesKit

final class ThemeSwatchView: NSView {
    var theme: Theme?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard let theme else { return }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        NSString(string: theme.displayName).draw(at: NSPoint(x: 16, y: 12), withAttributes: titleAttrs)

        let swatchTop: CGFloat = 50
        let swatchWidth = (bounds.width - 32 - CGFloat(theme.colors.count - 1) * 8) / CGFloat(theme.colors.count)
        let swatchHeight: CGFloat = 90

        for (i, c) in theme.colors.enumerated() {
            let rect = NSRect(
                x: 16 + CGFloat(i) * (swatchWidth + 8),
                y: swatchTop,
                width: swatchWidth,
                height: swatchHeight)
            let fill = NSColor(hex: c.lightBackgroundHex)
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

            let textColor = NSColor(hex: c.lightTextHex)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: textColor,
            ]
            // Slot name + a small "Aa" to expose text-contrast at a glance.
            NSString(string: c.displayName).draw(
                at: NSPoint(x: rect.minX + 6, y: rect.minY + 6),
                withAttributes: attrs)
            NSString(string: "Aa").draw(
                at: NSPoint(x: rect.minX + 6, y: rect.maxY - 22),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: textColor,
                ])
            NSString(string: c.lightBackgroundHex.lowercased()).draw(
                at: NSPoint(x: rect.minX + 6, y: rect.minY + rect.height / 2 - 6),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: textColor,
                ])
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(white: 0, alpha: 1); return
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8)  & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

final class ThemeSwatchSnapshotTests: XCTestCase {

    @MainActor
    private func snapshot(_ theme: Theme,
                          file: StaticString = #filePath,
                          testName: String = #function,
                          line: UInt = #line) {
        let view = ThemeSwatchView(frame: NSRect(x: 0, y: 0, width: 760, height: 160))
        view.theme = theme
        assertSnapshot(of: view, as: .image, file: file, testName: testName, line: line)
    }

    @MainActor func testTheme_Original()         { snapshot(Themes.original) }
    @MainActor func testTheme_Classic()          { snapshot(Themes.classic) }
    @MainActor func testTheme_Dopamine()         { snapshot(Themes.dopamine) }
    @MainActor func testTheme_Muted()            { snapshot(Themes.muted) }
    @MainActor func testTheme_SoftRainbow()      { snapshot(Themes.softRainbow) }
    @MainActor func testTheme_EarthyGreen()      { snapshot(Themes.earthyGreen) }
    @MainActor func testTheme_PastelDreamland()  { snapshot(Themes.pastelDreamland) }
    @MainActor func testTheme_BoldBerry()        { snapshot(Themes.boldBerry) }
    @MainActor func testTheme_EarthyForest()     { snapshot(Themes.earthyForest) }
    @MainActor func testTheme_SummerFun()        { snapshot(Themes.summerFun) }
    @MainActor func testTheme_TropicalBliss()    { snapshot(Themes.tropicalBliss) }
    @MainActor func testTheme_GoldenFields()     { snapshot(Themes.goldenFields) }
    @MainActor func testTheme_SunnyBeach()       { snapshot(Themes.sunnyBeach) }
    @MainActor func testTheme_EarthyTones()      { snapshot(Themes.earthyTones) }
    @MainActor func testTheme_AutumnHarvest()    { snapshot(Themes.autumnHarvest) }
}
