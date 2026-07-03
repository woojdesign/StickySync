// StickyChromeSnapshotTests.swift
//
// 0.11.3: pin the sticky's chrome across all 7 palette colors AND
// both chrome-visible states. Catches regressions to:
//   - header spacing (0.9.3 → 0.10.2 arc)
//   - icon layout (color-font-share-close-⋯ positions)
//   - color-adaptive tint on chrome icons
//   - band contrast (dark overlay on light stickies vs light
//     overlay on dark stickies)
//   - overlay pattern (hidden chrome → text edge-to-edge)
//
// First run generates baselines under __Snapshots__. Subsequent
// runs pixel-diff. Sean can now spot regressions in CI without
// eyeballing each ship.

import XCTest
import SnapshotTesting
import AppKit
@testable import StickySync
import NotesKit

@MainActor
final class StickyChromeSnapshotTests: XCTestCase {

    private var hostingWindows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        ThemeStore.shared.select("original")
    }

    override func tearDown() {
        super.tearDown()
        hostingWindows.removeAll()
    }

    // MARK: - Helpers

    private func makeNote(colorToken: String,
                          chromeVisible: Bool,
                          text: String = "chrome check\nline 2\nline 3",
                          width: CGFloat = 340,
                          height: CGFloat = 180) -> NoteContentView {
        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.textView.string = text
        view.apply(colorToken: colorToken, font: NSFont.systemFont(ofSize: 14))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.contentView = view
        hostingWindows.append(window)

        view.setChromeVisible(chromeVisible, animated: false)
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        return view
    }

    // MARK: - All 7 colors × chrome-visible

    func testChromeVisible_Color1_Yellow() {
        assertSnapshot(of: makeNote(colorToken: "1", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color2_Peach() {
        assertSnapshot(of: makeNote(colorToken: "2", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color3_Rose() {
        assertSnapshot(of: makeNote(colorToken: "3", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color4_Lilac() {
        assertSnapshot(of: makeNote(colorToken: "4", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color5_Sky() {
        assertSnapshot(of: makeNote(colorToken: "5", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color6_Mint() {
        assertSnapshot(of: makeNote(colorToken: "6", chromeVisible: true), as: .image)
    }

    func testChromeVisible_Color7_Sand() {
        assertSnapshot(of: makeNote(colorToken: "7", chromeVisible: true), as: .image)
    }

    // MARK: - Chrome-hidden state (overlay pattern — text at top edge)

    /// With chrome hidden, the text should sit near the top of the
    /// sticky (12pt inset only) — no 26pt reserved header space.
    /// This baseline captures that "clean" state so a regression to
    /// the pre-0.9.4 reserved-header layout would diff.
    func testChromeHidden_Color1_TextNearTop() {
        assertSnapshot(of: makeNote(colorToken: "1", chromeVisible: false), as: .image)
    }

    func testChromeHidden_Color4_TextNearTop_DarkSticky() {
        assertSnapshot(of: makeNote(colorToken: "4", chromeVisible: false), as: .image)
    }
}
