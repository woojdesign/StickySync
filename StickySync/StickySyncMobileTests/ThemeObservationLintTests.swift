// ThemeObservationLintTests.swift
//
// Lint-style test that catches the 0.7.33 NoteRowView regression
// class: any iOS view that reads from `Appearance.text(...)` or
// `Appearance.background(...)` (which resolve through
// `ThemeStore.shared.current`) MUST also observe ThemeStore so its
// body re-runs when the user picks a new theme. Without the
// observer, SwiftUI sees no dependency change → body is cached →
// the theme change only "lands" after the next view init (which
// usually means app relaunch).
//
// This test reads the source files directly; it's a structural
// guard, not a behavioral one.

import XCTest

final class ThemeObservationLintTests: XCTestCase {

    /// Files under iOS that legitimately *use* Appearance.* but
    /// don't need a ThemeStore observer (e.g. helpers that take the
    /// theme as a parameter, files where the parent observes).
    /// Add only with justification.
    private let exemptions: Set<String> = []

    func testEveryAppearanceConsumerObservesThemeStore() throws {
        let mobileDir = sourceURL().appendingPathComponent("StickySyncMobile")
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: mobileDir,
                                       includingPropertiesForKeys: nil,
                                       options: [.skipsHiddenFiles])
        var offenders: [String] = []
        while let next = enumerator?.nextObject() as? URL {
            guard next.pathExtension == "swift" else { continue }
            let name = next.lastPathComponent
            if exemptions.contains(name) { continue }
            let source = try String(contentsOf: next, encoding: .utf8)
            let usesAppearance = source.contains("Appearance.text(")
                || source.contains("Appearance.background(")
                || source.contains("Appearance.swatchImage(")
                || source.contains("Appearance.themeSwatchImage(")
            guard usesAppearance else { continue }
            let observesTheme = source.contains("ThemeStore.shared")
                && (source.contains("@ObservedObject") || source.contains("@StateObject")
                    || source.contains("@EnvironmentObject"))
            if !observesTheme {
                offenders.append(name)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "These iOS files use Appearance.* but don't observe ThemeStore — "
                      + "theme changes will only apply after app restart "
                      + "(0.7.33 NoteRowView class of bug): \(offenders.joined(separator: ", "))")
    }

    /// Walk up from this file's path to the StickySync source root.
    /// Test targets are run from a build dir; #file points back into
    /// the repo, so we can find the source tree relative to it.
    private func sourceURL() -> URL {
        var url = URL(fileURLWithPath: #file)
        while url.lastPathComponent != "StickySync" {
            url.deleteLastPathComponent()
            if url.path == "/" {
                XCTFail("couldn't locate StickySync source root from \(#file)")
                return URL(fileURLWithPath: "/")
            }
        }
        return url
    }
}
