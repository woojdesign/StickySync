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

    /// Click over a chrome button (chrome visible) lands on the
    /// button — z-order stays correct.
    func testHitTest_OnCloseButton_VisibleChrome_LandsOnButton() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutSubtreeIfNeeded()
        view.setChromeVisible(true, animated: false)

        // Close button lives at edgePad=10 in header coords; convert
        // to the noteContentView's coords. Aim right in its center.
        let closeCenter = view.header.convert(
            NSPoint(x: view.closeButton.frame.midX,
                    y: view.closeButton.frame.midY), to: view)
        let hit = view.hitTest(closeCenter)

        var walker: NSView? = hit
        var foundButton = false
        while let w = walker {
            if w === view.closeButton { foundButton = true; break }
            walker = w.superview
        }
        XCTAssertTrue(foundButton,
            "click on the close button should hit the button, not fall through")
    }

    /// 0.10.1: chrome hover-HIDDEN, click in header region falls
    /// through to text.
    func testHitTest_InHeaderFrame_HiddenChrome_FallsThrough() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutSubtreeIfNeeded()
        view.setChromeVisible(false, animated: false)

        let headerCenterY = view.bounds.height - (view.headerHeight / 2)
        let point = NSPoint(x: 18, y: headerCenterY)
        let hit = view.hitTest(point)
        assertNotInHeaderSubtree(hit: hit, header: view.header,
            message: "hidden-chrome hit-test should not resolve into the header")
    }

    /// 0.10.2: even with chrome VISIBLE, clicks in EMPTY header
    /// space (between/around buttons) fall through to text. Fixes
    /// Sean's "can't select text slightly under the chrome" issue.
    func testHitTest_InEmptyHeaderSpace_VisibleChrome_FallsThrough() {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutSubtreeIfNeeded()
        view.setChromeVisible(true, animated: false)

        // Aim for the dead center of the header horizontally — no
        // buttons live there (close is far left; color/font/share/⋯
        // are all clustered right).
        let headerCenterY = view.bounds.height - (view.headerHeight / 2)
        let point = NSPoint(x: view.bounds.midX, y: headerCenterY)
        let hit = view.hitTest(point)
        assertNotInHeaderSubtree(hit: hit, header: view.header,
            message: "visible chrome should let clicks in empty header space fall through")
    }

    private func assertNotInHeaderSubtree(hit: NSView?, header: NSView, message: String) {
        var walker: NSView? = hit
        while let w = walker {
            XCTAssertFalse(w === header, message)
            walker = w.superview
        }
    }
}
