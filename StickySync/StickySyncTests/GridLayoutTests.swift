// GridLayoutTests.swift
//
// Unit tests for the pure layout math behind "Arrange in Grid". Lifted
// out of ArrangeStickies after the 0.7.3 ship demonstrated that
// "compiles + I eyeballed it" wasn't enough.
//
// Each test asserts an invariant that, if broken, would re-produce the
// kind of garbage layout that piled stickies on top of each other:
//   - top-aligned in each row (no short windows floating below tall ones)
//   - no overlap between any two frames
//   - never extends past the right or bottom of the screen rect
//   - newer (= input order) lands at top-left

import XCTest
@testable import StickySync

final class GridLayoutTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: - Smoke

    func testEmptyInput_ReturnsEmptyOutput() {
        XCTAssertEqual(GridLayout.frames(forSizes: [], in: screen), [])
    }

    func testSingleSticky_LandsTopLeft() {
        let frames = GridLayout.frames(forSizes: [NSSize(width: 240, height: 180)],
                                        in: screen)
        XCTAssertEqual(frames.count, 1)
        let f = frames[0]
        XCTAssertEqual(f.minX, screen.minX + GridLayout.margin)
        XCTAssertEqual(f.maxY, screen.maxY - GridLayout.margin)
    }

    // MARK: - Top-alignment within a row

    func testMixedSizes_TopAlignedInRow() {
        // The 0.7.3 bug: short stickies landed at the row's *bottom*
        // because origin Y was computed against the row's max height, not
        // each window's own height. Two same-row stickies of different
        // heights should have the same top Y.
        let sizes = [NSSize(width: 240, height: 180),
                     NSSize(width: 240, height: 360)]
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        XCTAssertEqual(frames[0].maxY, frames[1].maxY,
                       "row 0 stickies must align at the same top edge")
    }

    // MARK: - No overlap

    func testFitsInARow_NoOverlap() {
        // Four 240×180 stickies fit in a single row on a 1440-wide screen.
        let sizes = Array(repeating: NSSize(width: 240, height: 180), count: 4)
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        assertNoOverlap(frames)
    }

    func testWrapsToNextRow_NoOverlap() {
        // Six 280-wide stickies on a 1440-wide screen: (1440 - 48) / (280
        // + 14) ≈ 4.7 → 4 per row, so the 5th wraps. Make sure none of
        // the resulting frames overlap.
        let sizes = Array(repeating: NSSize(width: 280, height: 200), count: 6)
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        XCTAssertEqual(frames.count, 6)
        assertNoOverlap(frames)
        // The 5th sticky should be at (margin, second-row top).
        XCTAssertEqual(frames[4].minX, screen.minX + GridLayout.margin)
        XCTAssertLessThan(frames[4].maxY, frames[0].minY,
                          "wrapped sticky should sit fully below row 0")
    }

    func testMixedHeights_NextRowDescendsByTallest() {
        // Row 0 contains a tall sticky; row 1 should sit below it,
        // not below the *average* of row 0. (The 0.7.3 bug used a single
        // global cellH = max(all heights) which wasted screen space; the
        // new code uses per-row max instead.)
        let sizes = [
            NSSize(width: 240, height: 180),
            NSSize(width: 240, height: 500),   // tall — fits in row 0
            NSSize(width: 240, height: 180),
            NSSize(width: 240, height: 180),
            NSSize(width: 240, height: 180),
            NSSize(width: 240, height: 180),   // wraps to row 1
        ]
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        XCTAssertEqual(frames.count, 6)
        // The wrapping sticky's top should be below the tallest of row 0.
        let row0Bottoms = frames[0..<5].map { $0.minY }.min() ?? 0
        XCTAssertLessThanOrEqual(frames[5].maxY, row0Bottoms,
                                 "row 1 must start below the tallest sticky in row 0")
        assertNoOverlap(frames)
    }

    // MARK: - Overflow handling

    func testTooManyStickies_ClampToVisible() {
        // Hammer the grid with way more stickies than fit. They must
        // all stay on-screen (clamped to the bottom margin if necessary)
        // rather than disappearing off the bottom edge.
        let sizes = Array(repeating: NSSize(width: 300, height: 300), count: 30)
        let frames = GridLayout.frames(forSizes: sizes, in: screen)
        XCTAssertEqual(frames.count, 30)
        for f in frames {
            XCTAssertGreaterThanOrEqual(f.minY, screen.minY,
                                        "no frame should sit below the screen")
        }
    }

    // MARK: - Helpers

    private func assertNoOverlap(_ frames: [NSRect],
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                let inter = frames[i].intersection(frames[j])
                XCTAssertTrue(inter.isNull || inter.isEmpty,
                              "frames \(i) and \(j) overlap: \(frames[i]) vs \(frames[j])",
                              file: file, line: line)
            }
        }
    }
}
