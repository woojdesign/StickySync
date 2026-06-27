// LayoutSnapshotTests.swift
//
// Visual QA for the layout math — *this* is what snapshot-testing is for
// in this codebase, not just rendering individual views. Render the
// computed `[NSRect]` from `GridLayout.frames(...)` and `TidyLayout.places(...)`
// as labeled colored boxes on a canvas, diff against a baseline PNG. If
// the layout math regresses (top-aligned breaks, overflow piles up,
// overlap creeps in), the next test run fails the diff before the build
// ever ships.

import XCTest
import AppKit
import SnapshotTesting
@testable import StickySync

/// Draws an array of frames on a fixed-size canvas. Each frame is a
/// distinct color labeled with its input index — so a regression in
/// position (frame 4 lands where frame 0 should) is immediately legible
/// in the diff. The canvas itself represents a screen rect.
final class LayoutVisualizerView: NSView {
    var frames: [NSRect] = []
    /// The screen rect the frames were computed for; we scale to fit
    /// the visualizer's bounds.
    var screenRect: NSRect = .zero

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        guard screenRect.width > 0, screenRect.height > 0 else { return }

        let sx = bounds.width / screenRect.width
        let sy = bounds.height / screenRect.height

        // Screen border so the available area is visible.
        NSColor.black.withAlphaComponent(0.15).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        // Frames, with a deterministic color per index so diffs are
        // legible (red-orange-yellow…).
        for (i, f) in frames.enumerated() {
            let scaled = NSRect(
                x: (f.minX - screenRect.minX) * sx,
                y: (f.minY - screenRect.minY) * sy,
                width: f.width * sx,
                height: f.height * sy)

            let hue = CGFloat(i) / max(1, CGFloat(frames.count)) * 0.85
            let fill = NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 0.55)
            let stroke = NSColor(hue: hue, saturation: 0.7,  brightness: 0.6,  alpha: 1.0)

            fill.setFill()
            stroke.setStroke()
            let path = NSBezierPath(roundedRect: scaled, xRadius: 4, yRadius: 4)
            path.fill()
            path.lineWidth = 1.5
            path.stroke()

            let label = NSString(string: "\(i)")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: scaled.minX + 4, y: scaled.maxY - size.height - 2),
                withAttributes: attrs)
        }
    }
}

final class LayoutSnapshotTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private func visualizer(frames: [NSRect]) -> LayoutVisualizerView {
        let view = LayoutVisualizerView(frame: NSRect(x: 0, y: 0, width: 720, height: 450))
        view.screenRect = screen
        view.frames = frames
        return view
    }

    // MARK: - GridLayout baselines

    @MainActor
    func testGrid_UniformSizes_FourPerRow() {
        let sizes = Array(repeating: NSSize(width: 280, height: 200), count: 8)
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        assertSnapshot(of: visualizer(frames: frames), as: .image)
    }

    @MainActor
    func testGrid_MixedHeights_TopAligned() {
        // 0.7.3 regression: short stickies in row 0 floated at the row's
        // bottom because the origin used row-max height. This baseline
        // catches that — short and tall in the same row should align
        // at the top.
        let sizes: [NSSize] = [
            .init(width: 240, height: 180),
            .init(width: 240, height: 420),
            .init(width: 240, height: 240),
            .init(width: 240, height: 180),
        ]
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        assertSnapshot(of: visualizer(frames: frames), as: .image)
    }

    @MainActor
    func testGrid_VariableWidths_BinPack() {
        // Bin-pack a mix of wide and narrow stickies. Should fit as many
        // per row as cumulative width allows, then wrap.
        let sizes: [NSSize] = [
            .init(width: 240, height: 200),
            .init(width: 480, height: 200),  // chunky
            .init(width: 240, height: 200),
            .init(width: 320, height: 200),
            .init(width: 240, height: 200),
            .init(width: 240, height: 200),
        ]
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        assertSnapshot(of: visualizer(frames: frames), as: .image)
    }

    @MainActor
    func testGrid_TooManyOverflow_ClampToBottom() {
        // 20 stickies on a 1440×900 screen — most rows fit, the tail
        // clamps to the bottom margin instead of vanishing off-screen.
        let sizes = Array(repeating: NSSize(width: 280, height: 240), count: 20)
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        assertSnapshot(of: visualizer(frames: frames), as: .image)
    }

    // MARK: - TidyLayout baselines

    @MainActor
    func testTidy_AvoidsFixedRects() {
        // Three well-placed stickies form a U shape in the screen;
        // four drifted ones should land in the U's empty middle and
        // around the edges.
        let fixed: [NSRect] = [
            .init(x: 24,   y: 600, width: 240, height: 180),
            .init(x: 1176, y: 600, width: 240, height: 180),
            .init(x: 600,  y: 30,  width: 240, height: 180),
        ]
        let sizesToPlace = Array(repeating: NSSize(width: 240, height: 180), count: 4)
        let placed = TidyLayout.places(sizesToPlace: sizesToPlace,
                                        avoiding: fixed,
                                        in: screen)
        assertSnapshot(of: visualizer(frames: fixed + placed), as: .image)
    }

    @MainActor
    func testTidy_NewStickies_NoOverlapWithEachOther() {
        // No fixed rects — six new stickies should tile cleanly from
        // the top-left without overlapping.
        let sizesToPlace = Array(repeating: NSSize(width: 280, height: 220), count: 6)
        let placed = TidyLayout.places(sizesToPlace: sizesToPlace,
                                        avoiding: [],
                                        in: screen)
        assertSnapshot(of: visualizer(frames: placed), as: .image)
    }
}
