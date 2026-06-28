// ThemePersistenceTests.swift
//
// Pins the "tests don't reset the user's theme" contract added 0.7.13.
// Pre-fix, every test that called `ThemeStore.shared.select(...)` —
// snapshot tests force-setting a theme for deterministic rendering —
// wrote through to UserDefaults, the sidecar plist, *and* iCloud KVS.
// The iCloud write pushed to every other device on the user's
// account, so months of "theme keeps getting reset" reports trace
// back to running tests during development.
//
// The fix: `ThemeStore` detects `XCTestConfigurationFilePath` and
// skips every persistence side-effect of `select(_:)` and `init`.
// The in-memory `current` still updates so snapshot tests still
// render against the forced theme.

import XCTest
import NotesKit

@MainActor
final class ThemePersistenceTests: XCTestCase {

    /// Pin: under XCTest, picking a non-default theme must NOT write
    /// through to UserDefaults. This is the most consequential
    /// persistence leak — UserDefaults' value becomes the next launch's
    /// default *and* is one of the seeds for the iCloud KVS push.
    func testSelect_UnderXCTest_DoesNotWriteToUserDefaults() {
        let key = "design.wooj.StickySync.themeID"
        let before = UserDefaults.standard.string(forKey: key)

        ThemeStore.shared.select("dopamine")
        XCTAssertEqual(ThemeStore.shared.current.id, "dopamine",
                       "select() still updates the in-memory current")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), before,
                       "select() must NOT write through to UserDefaults under XCTest")
    }

    /// Pin: under XCTest, picking a theme must NOT write through to
    /// NSUbiquitousKeyValueStore. This is the worst-case persistence
    /// leak — iCloud KVS propagates to every device on the user's
    /// account, so a stray test write resets the theme everywhere.
    func testSelect_UnderXCTest_DoesNotWriteToICloudKVS() {
        let key = "design.wooj.StickySync.themeID"
        let before = NSUbiquitousKeyValueStore.default.string(forKey: key)

        ThemeStore.shared.select("classic")
        XCTAssertEqual(NSUbiquitousKeyValueStore.default.string(forKey: key), before,
                       "select() must NOT write through to NSUbiquitousKeyValueStore under XCTest")
    }

    /// Pin: snapshot tests still work — picking a theme synchronously
    /// updates `current`, so a test that switches theme right before
    /// asserting a snapshot sees the new resolution. The .themeChanged
    /// notification still posts so any AppKit views that imperatively
    /// re-apply colors still get the signal.
    func testSelect_UnderXCTest_StillUpdatesCurrent() {
        ThemeStore.shared.select("muted")
        XCTAssertEqual(ThemeStore.shared.current.id, "muted")

        ThemeStore.shared.select("original")
        XCTAssertEqual(ThemeStore.shared.current.id, "original")
    }
}
