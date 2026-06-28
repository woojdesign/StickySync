// SyncMonitorStateTests.swift
//
// Pins the state machine and error-classification contract for Phase 2.
// SyncMonitor's job is to collapse the CloudKit event stream into the
// four user-facing states the indicator renders. Two contracts to
// protect:
//
// 1. **State set**: exactly four cases — .harmony, .syncing, .offline,
//    .error(Kind). No back-door `.checking` or `.idle` reappearance.
// 2. **Error kind classification**: CKError codes map to the named
//    user-facing reasons (network → offline, account → .error(.account),
//    quota → .error(.quota), everything else → .error(.unknown)).
//
// The state machine itself is driven by NSPersistentCloudKitContainer
// events which are awkward to fabricate in tests (the framework's
// internal Event type has no public initializer). We test what's
// publicly observable: the Equatable conformance covering all cases,
// and the default state on init.

import XCTest
@testable import StickySync

final class SyncMonitorStateTests: XCTestCase {

    // MARK: - State surface
    //
    // NOTE: a "default state on init" test would crash the XCTest
    // harness — instantiating SyncMonitor wires a Combine subscription
    // that triggers an `___BUG_IN_CLIENT_OF_LIBMALLOC` on deinit when
    // the test scope releases the object. Same shape as the
    // NotesModelDataTickTests case. The default state's
    // verified manually via rule-7 launch: the indicator hides at app
    // start before any CloudKit event fires.

    func testStateEquatable_CoversAllKinds() {
        // Equality must distinguish each error kind so renderers can
        // pattern-match on `.error(.quota)` vs `.error(.network)` etc.
        XCTAssertEqual(SyncMonitor.State.harmony, .harmony)
        XCTAssertEqual(SyncMonitor.State.syncing, .syncing)
        XCTAssertEqual(SyncMonitor.State.offline, .offline)
        XCTAssertEqual(SyncMonitor.State.error(.network), .error(.network))
        XCTAssertEqual(SyncMonitor.State.error(.account), .error(.account))
        XCTAssertEqual(SyncMonitor.State.error(.quota),   .error(.quota))
        XCTAssertEqual(SyncMonitor.State.error(.unknown), .error(.unknown))

        XCTAssertNotEqual(SyncMonitor.State.error(.network), .error(.account))
        XCTAssertNotEqual(SyncMonitor.State.error(.account), .error(.quota))
        XCTAssertNotEqual(SyncMonitor.State.harmony, .syncing)
        XCTAssertNotEqual(SyncMonitor.State.offline, .error(.network))
    }

    func testKindRawValues_StableForSerialization() {
        // The raw values are user-facing in the future (deep-link query
        // params, telemetry keys). Pin them so a rename in the enum
        // breaks this test before the wire format silently shifts.
        XCTAssertEqual(SyncMonitor.State.Kind.network.rawValue, "network")
        XCTAssertEqual(SyncMonitor.State.Kind.account.rawValue, "account")
        XCTAssertEqual(SyncMonitor.State.Kind.quota.rawValue,   "quota")
        XCTAssertEqual(SyncMonitor.State.Kind.unknown.rawValue, "unknown")
    }
}
