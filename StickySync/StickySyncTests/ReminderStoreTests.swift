// ReminderStoreTests.swift
//
// 0.12.0: pins the Reminder value type + UserDefaultsReminderStore
// CRUD contract. When Phase B swaps for a CloudKit-backed store,
// these same tests should pass against that implementation with a
// one-line setUp change.

import XCTest
@testable import StickySync

final class ReminderStoreTests: XCTestCase {

    private var store: UserDefaultsReminderStore!
    private let suite = "design.wooj.StickySync.reminders.test"

    override func setUp() {
        super.setUp()
        store = UserDefaultsReminderStore(suiteName: suite)
        store.wipeAllForTesting()
    }

    override func tearDown() {
        store.wipeAllForTesting()
        super.tearDown()
    }

    private func future(_ interval: TimeInterval = 3600) -> Date {
        Date().addingTimeInterval(interval)
    }

    // MARK: - CRUD

    func testSet_ThenGet_RoundTrip() {
        let noteID = UUID()
        let r = Reminder(noteID: noteID, fireAt: future())
        store.set(r)
        let fetched = store.reminder(for: noteID)
        XCTAssertEqual(fetched?.id, r.id)
        XCTAssertEqual(fetched?.fireAt.timeIntervalSince1970 ?? 0,
                       r.fireAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSet_ReplacesExisting() {
        let noteID = UUID()
        let r1 = Reminder(noteID: noteID, fireAt: future(60))
        let r2 = Reminder(noteID: noteID, fireAt: future(3600))
        store.set(r1)
        store.set(r2)
        let fetched = store.reminder(for: noteID)
        XCTAssertEqual(fetched?.id, r2.id, "second set should replace first — sticky-scoped")
    }

    func testClear_RemovesReminder() {
        let noteID = UUID()
        store.set(Reminder(noteID: noteID, fireAt: future()))
        store.clear(for: noteID)
        XCTAssertNil(store.reminder(for: noteID))
    }

    func testReminder_ForUnknownNote_ReturnsNil() {
        XCTAssertNil(store.reminder(for: UUID()))
    }

    // MARK: - Active / fired

    func testIsActive_FutureUnfired_True() {
        let r = Reminder(noteID: UUID(), fireAt: future())
        XCTAssertTrue(r.isActive)
    }

    func testIsActive_Past_False() {
        let r = Reminder(noteID: UUID(), fireAt: Date().addingTimeInterval(-60))
        XCTAssertFalse(r.isActive)
    }

    func testIsActive_Fired_False() {
        let r = Reminder(noteID: UUID(), fireAt: future(),
                          fired: true, firedAt: Date())
        XCTAssertFalse(r.isActive)
    }

    func testActiveReminders_FiltersOutFiredAndPast() {
        let liveNoteID = UUID()
        store.set(Reminder(noteID: liveNoteID, fireAt: future()))
        store.set(Reminder(noteID: UUID(), fireAt: Date().addingTimeInterval(-60)))
        store.set(Reminder(noteID: UUID(), fireAt: future(),
                            fired: true, firedAt: Date()))
        let active = store.activeReminders()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.noteID, liveNoteID)
    }

    // MARK: - markFired

    func testMarkFired_StampsFlagAndTimestamp() {
        let noteID = UUID()
        let r = Reminder(noteID: noteID, fireAt: future())
        store.set(r)
        let firedAt = Date()
        store.markFired(r.id, at: firedAt)
        let fetched = store.reminder(for: noteID)
        XCTAssertTrue(fetched?.fired ?? false)
        XCTAssertEqual(fetched?.firedAt?.timeIntervalSince1970 ?? 0,
                       firedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMarkFired_UnknownID_NoOp() {
        // Should not crash, should not touch anything.
        store.markFired(UUID(), at: Date())
        XCTAssertTrue(store.activeReminders().isEmpty)
    }

    // MARK: - Codable round-trip

    func testCodable_RoundTrip_PreservesFields() throws {
        let r = Reminder(id: UUID(),
                         noteID: UUID(),
                         fireAt: future(),
                         isUrgent: true,
                         fired: true,
                         firedAt: Date())
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(Reminder.self, from: data)
        XCTAssertEqual(decoded.id, r.id)
        XCTAssertEqual(decoded.noteID, r.noteID)
        XCTAssertEqual(decoded.fireAt.timeIntervalSince1970,
                       r.fireAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.isUrgent, r.isUrgent)
        XCTAssertEqual(decoded.fired, r.fired)
        XCTAssertEqual(decoded.firedAt?.timeIntervalSince1970 ?? 0,
                       r.firedAt?.timeIntervalSince1970 ?? 0, accuracy: 0.001)
    }
}
