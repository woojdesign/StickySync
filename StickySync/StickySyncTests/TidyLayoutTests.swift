// TidyLayoutTests.swift
//
// Pins the "respect what's well-placed, only fix what's broken" promise.
// The 0.7.4 Tidy stacked drifted stickies in a tight pile at the top-
// right corner, ignoring the well-placed ones underneath; these tests
// would have caught that.

import XCTest
@testable import StickySync

final class TidyLayoutTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: - Avoids fixed rects

    func testSinglePlacement_AvoidsFixed() {
        // A 300×200 sticky needs a spot. The top-left is occupied by a
        // 400×300 well-placed sticky; the result should sit somewhere
        // that doesn't intersect that.
        let fixed = [NSRect(x: 24, y: 576, width: 400, height: 300)]
        let result = TidyLayout.places(sizesToPlace: [NSSize(width: 300, height: 200)],
                                        avoiding: fixed,
                                        in: screen)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].intersection(fixed[0]).isEmpty,
                      "placed sticky overlaps the fixed rect")
    }

    func testMultiplePlacement_NoOverlapWithEachOther() {
        // Three new stickies; together they shouldn't overlap each other.
        let sizes = Array(repeating: NSSize(width: 240, height: 180), count: 3)
        let result = TidyLayout.places(sizesToPlace: sizes,
                                        avoiding: [],
                                        in: screen)
        for i in 0..<result.count {
            for j in (i + 1)..<result.count {
                let inter = result[i].intersection(result[j])
                XCTAssertTrue(inter.isNull || inter.isEmpty,
                              "tidy results \(i) and \(j) overlap")
            }
        }
    }

    func testPlacement_StaysWithinBounds() {
        let sizes = Array(repeating: NSSize(width: 240, height: 180), count: 5)
        let result = TidyLayout.places(sizesToPlace: sizes, avoiding: [], in: screen)
        for f in result {
            XCTAssertGreaterThanOrEqual(f.minX, screen.minX)
            XCTAssertGreaterThanOrEqual(f.minY, screen.minY)
            XCTAssertLessThanOrEqual(f.maxX, screen.maxX)
            XCTAssertLessThanOrEqual(f.maxY, screen.maxY)
        }
    }

    func testCrowdedScreen_FallsBackToTopLeft() {
        // Cover most of the screen with fixed rects. The new sticky
        // can't find free space; the algorithm should still return a
        // valid frame (top-left fallback) rather than asserting.
        let fixed = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
        let result = TidyLayout.places(sizesToPlace: [NSSize(width: 240, height: 180)],
                                        avoiding: fixed,
                                        in: screen)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(screen.contains(result[0]),
                      "fallback frame should still be on-screen")
    }

    // MARK: - Respects well-placed siblings

    func testWellPlacedStickies_NeverDisturbed() {
        // The user's intent: I have two well-placed stickies and one
        // that drifted off-screen. Tidy should reposition only the
        // drifted one, into a spot that doesn't overlap the well-placed.
        let wellPlaced = [
            NSRect(x: 100, y: 600, width: 240, height: 180),
            NSRect(x: 800, y: 400, width: 240, height: 180),
        ]
        let drifted = NSSize(width: 240, height: 180)

        let result = TidyLayout.places(sizesToPlace: [drifted],
                                        avoiding: wellPlaced,
                                        in: screen)
        XCTAssertEqual(result.count, 1)
        for w in wellPlaced {
            XCTAssertTrue(result[0].intersection(w).isEmpty,
                          "tidied sticky overlaps a well-placed sibling")
        }
    }

    // MARK: - Newest-first ordering preserved

    func testInputOrder_PreservedInOutput() {
        // We pass three sizes in a specific order; the output order
        // should match (so the caller can zip back to the controllers).
        let sizes = [
            NSSize(width: 100, height: 100),
            NSSize(width: 200, height: 200),
            NSSize(width: 300, height: 300),
        ]
        let result = TidyLayout.places(sizesToPlace: sizes,
                                        avoiding: [],
                                        in: screen)
        XCTAssertEqual(result.map { $0.size }, sizes)
    }
}
