// NoteContentViewZOrderTests.swift
//
// Pins the z-order contract that 0.9.10 fixed: the hover-revealed
// chrome header MUST sit above the scrollView so its buttons
// receive clicks. Since 0.9.4 the scrollView takes the full sticky
// height (chrome overlays content), so wrong z-order routes every
// chrome tap into a text-view cursor move instead of a button
// action.
//
// Sean caught it live: "sadly we'll have to adjust the chrome up
// top because none of the icons are clickable (it cursors into the
// text)."

import XCTest
@testable import StickySync

final class NoteContentViewZOrderTests: XCTestCase {

    /// The header must be above the scrollView in the subview array —
    /// AppKit's later-added-subviews-are-on-top rule.
    func testHeader_IsAboveScrollView() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let subs = view.subviews
        guard let headerIdx = subs.firstIndex(of: view.header),
              let scrollIdx = subs.firstIndex(of: view.scrollView) else {
            XCTFail("header or scrollView missing from subview hierarchy")
            return
        }
        XCTAssertGreaterThan(headerIdx, scrollIdx,
            "header must be above scrollView so chrome buttons receive clicks")
    }

    /// The resize grip must be above everything (bottom-right corner
    /// grip needs to eat clicks in that hot zone).
    func testResizeGrip_IsAboveEverything() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let subs = view.subviews
        guard let gripIdx = subs.firstIndex(of: view.resizeGrip) else {
            XCTFail("resizeGrip missing")
            return
        }
        XCTAssertEqual(gripIdx, subs.count - 1,
            "resizeGrip must be topmost so the bottom-right grip captures clicks")
    }

    /// A click inside the header's frame should hit-test to a chrome
    /// button (or the header itself, for drag), NEVER through to the
    /// text view.
    ///
    /// Contract only applies when chrome is VISIBLE — when hidden
    /// the header intentionally lets clicks fall through so the
    /// user can place their cursor at the top of text.
    func testHitTest_InHeaderFrame_VisibleChrome_LandsOnChrome() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutSubtreeIfNeeded()
        view.setChromeVisible(true, animated: false)

        let headerCenterY = view.bounds.height - (view.headerHeight / 2)
        let point = NSPoint(x: 18, y: headerCenterY)
        let hit = view.hitTest(point)

        XCTAssertFalse(hit is NSTextView,
            "visible-chrome hit-test escaped into the text view — z-order broken")
        var walker: NSView? = hit
        var foundHeaderAncestry = false
        while let w = walker {
            if w === view.header { foundHeaderAncestry = true; break }
            walker = w.superview
        }
        XCTAssertTrue(foundHeaderAncestry,
            "visible-chrome hit-test in header region should land in the header subtree")
    }

    /// 0.10.1: when the chrome is hover-HIDDEN (alpha 0), a click in
    /// the header's frame should FALL THROUGH to whatever's below
    /// (scrollView / text view). Sean: "it's now hard to click on
    /// text that's near the top" — this test guards the fix.
    func testHitTest_InHeaderFrame_HiddenChrome_FallsThrough() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutSubtreeIfNeeded()
        view.setChromeVisible(false, animated: false)

        let headerCenterY = view.bounds.height - (view.headerHeight / 2)
        let point = NSPoint(x: 18, y: headerCenterY)
        let hit = view.hitTest(point)

        // Whatever the hit resolves to, it must NOT be inside the
        // header subtree — click should have passed through.
        var walker: NSView? = hit
        while let w = walker {
            XCTAssertFalse(w === view.header,
                "hidden-chrome hit-test should NOT resolve into the header")
            walker = w.superview
        }
    }
}
