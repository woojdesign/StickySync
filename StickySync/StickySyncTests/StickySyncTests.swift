// StickySyncTests.swift
//
// Snapshot baselines for the Mac note-window surface. Catches the class of
// regressions we've already shipped (right-edge text bleed, theme rendering
// drift, resize-grip placement) by rendering a NoteContentView at a fixed
// size and diffing against a baseline PNG on every build.
//
// First run *creates* the baseline. Subsequent runs diff. A meaningful
// visual change should be reviewed before promoting the new baseline.

import XCTest
import AppKit
import SnapshotTesting
import NotesKit
@testable import StickySync

final class NoteContentViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// Hold the hosting NSWindow alive past `makeNote(...)` so the view's
    /// dynamic colors keep resolving during the snapshot capture. Without
    /// this the window deallocates at end of scope and `currentDrawing()`
    /// goes back to nil mid-snapshot.
    private var hostingWindows: [NSWindow] = []

    /// Build a fully-configured NoteContentView at the given size and theme.
    /// Mirrors the production path enough that the resulting layout matches
    /// what a real note window renders.
    ///
    /// **Hosting-window dance** (was the cause of the 0.7.11 black-snapshot
    /// regression): `NoteContentView.updateLayer()` sets its layer's
    /// `backgroundColor` from `Appearance.background(for:).cgColor`. The
    /// `Appearance.background(...)` is a *dynamic* `NSColor` whose resolver
    /// block fires against `NSAppearance.currentDrawing()` — nil in a
    /// headless XCTest env unless the view is attached to a window with an
    /// explicit appearance. Resolved-to-nil → the cgColor renders as
    /// transparent → snapshot captures the underlying black. Wrapping in a
    /// hosting NSWindow with `.aqua` appearance forces the resolver to pick
    /// the light variant, and we get the proper yellow/etc.
    @MainActor
    private func makeNote(text: String,
                          colorToken: String = "1",
                          width: CGFloat = 240,
                          height: CGFloat = 180,
                          themeID: String = "original") -> NoteContentView {
        // Force the theme so the snapshot doesn't drift with the user's
        // local default. ThemeStore.shared.current is read by Appearance.
        ThemeStore.shared.select(themeID)

        let view = NoteContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.textView.string = text
        let font = NSFont.systemFont(ofSize: 14)
        view.apply(colorToken: colorToken, font: font)

        // Host in an off-screen NSWindow so dynamic-color resolution works.
        // Borderless + zero shadow so the window chrome doesn't bleed into
        // the snapshot capture.
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

        // Force layout + an immediate draw pass so updateLayer() fires and
        // the dynamic color resolves with the window's appearance.
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        return view
    }

    override func tearDown() {
        super.tearDown()
        hostingWindows.removeAll()
    }

    // MARK: - Baselines

    @MainActor
    func testEmptyNote_Original_default() {
        let view = makeNote(text: "")
        assertSnapshot(of: view, as: .image)
    }

    @MainActor
    func testShortNote_Original_default() {
        let view = makeNote(text: "buy milk")
        assertSnapshot(of: view, as: .image)
    }

    /// Regression test for the 0.6.2 right-edge bleed. A long single line
    /// should wrap inside the inset, not extend past the rounded corner.
    /// If the textContainer override is reintroduced or the inset gets
    /// out of sync with the corner radius, this baseline will diff.
    @MainActor
    func testLongLineWrap_Original_default() {
        let view = makeNote(text: "this is a deliberately long single line meant to wrap and prove the text container respects the inset on the right edge of the note window",
                            width: 360, height: 180)
        assertSnapshot(of: view, as: .image)
    }

    @MainActor
    func testListBody_Original_default() {
        let body = """
        - [ ] first
        - [x] second
        - [ ] third
        """
        let view = makeNote(text: body, width: 300, height: 220)
        assertSnapshot(of: view, as: .image)
    }

    // MARK: - Theme drift guards

    @MainActor
    func testShortNote_Classic_butter() {
        let view = makeNote(text: "tomato\nbasil\nmozzarella",
                            colorToken: "1",
                            themeID: "classic")
        assertSnapshot(of: view, as: .image)
    }

    @MainActor
    func testShortNote_Dopamine_berry() {
        // Dopamine slot 3 is the magenta/pink with white ink. Pinning
        // this baseline catches any drift in either the bg hex or the
        // ink-color resolution path.
        let view = makeNote(text: "Saturday plans",
                            colorToken: "3",
                            themeID: "dopamine")
        assertSnapshot(of: view, as: .image)
    }

    @MainActor
    func testShortNote_Muted_sage() {
        let view = makeNote(text: "Quiet thoughts",
                            colorToken: "6",
                            themeID: "muted")
        assertSnapshot(of: view, as: .image)
    }
}
