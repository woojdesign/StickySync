// SyncTapRoutingTests.swift
//
// Pin the iOS state→action mapping from 0.7.34's Phase 2.d. Tap on
// the sync status line routes to either Settings (recoverable
// causes) or the Tier 1 report composer (ambiguous states). The
// underlying URL pick on iOS is forced to `openSettingsURLString`
// by Apple (App-prefs schemes are private), so this only pins the
// branch decision.

import XCTest
@testable import StickySyncMobile

final class SyncTapRoutingTests: XCTestCase {

    typealias Action = NotesListView.SyncTapAction

    func testAccount_OpensSettings() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .error(.account)), .openSettings,
                       "account errors point at Sign-In — Settings is the next step")
    }

    func testQuota_OpensSettings() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .error(.quota)), .openSettings,
                       "quota errors send the user to manage iCloud storage")
    }

    func testNetwork_OpensSettings() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .error(.network)), .openSettings)
    }

    func testOffline_OpensSettings() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .offline), .openSettings,
                       "offline mirrors .error(.network) — Settings (Wi-Fi / Cellular)")
    }

    func testUnknown_OpensReport() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .error(.unknown)), .openReport,
                       ".unknown is the diagnostic-needed bucket — composer is the fallback")
    }

    func testSyncing_OpensReport() {
        XCTAssertEqual(NotesListView.syncTapAction(for: .syncing), .openReport,
                       "syncing has no Settings target; report is informational")
    }

    func testHarmony_OpensReport() {
        // .harmony is technically unreachable because the call site
        // gates on `state != .harmony`. The function still returns a
        // valid action so future call sites don't crash if the gate
        // ever moves.
        XCTAssertEqual(NotesListView.syncTapAction(for: .harmony), .openReport)
    }
}
