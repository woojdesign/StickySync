// StickySyncMobileTests.swift
//
// iOS test target. Today this is a placeholder — pure-logic regressions
// land in NotesKit's own test suite (which both apps share), and iOS
// snapshot tests are blocked on a sim-filesystem workaround (the iOS
// simulator's sandbox doesn't expose the host's source-tree path at
// `/Users/.../StickySyncMobileTests/__Snapshots__/`, so swift-snapshot-
// testing writes succeed via the test-runner bridge but the sim can't
// FileManager.fileExists those paths on subsequent runs).
//
// Options for re-enabling iOS snapshots (pick when we have a half-day
// to fix it properly):
//   (a) Bundle __Snapshots__ as a test-target resource so reads go
//       through Bundle.module instead of an absolute host path.
//   (b) Override snapshotDirectory to a sim-accessible path
//       (NSTemporaryDirectory or Documents) and ferry baselines into
//       the sim with a pre-test script.
//   (c) Run UI tests as a Mac Catalyst target so the filesystem is
//       shared with the host.
//
// Until then: Mac snapshot tests + NotesKit unit tests + manual smoke
// cover most of the visual surface (most of the buggy rendering paths
// are in shared code we exercise through NoteContentView on Mac).

import XCTest

final class StickySyncMobilePlaceholderTests: XCTestCase {
    /// Keeps the target compiling and running so the test scheme stays
    /// healthy. Delete when the first real iOS test lands.
    func testTargetBuildsAndLaunches() {
        XCTAssertTrue(true)
    }
}
