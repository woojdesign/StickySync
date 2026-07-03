// BetaChannelTests.swift
//
// 0.11.1: pins the beta-channel UserDefaults contract. The whole
// class is a pair of read/write helpers over SUFeedURL +
// SUAllowedChannels — small surface, worth pinning.

import XCTest
@testable import StickySync

final class BetaChannelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure a clean slate each test.
        UserDefaults.standard.removeObject(forKey: "SUFeedURL")
        UserDefaults.standard.removeObject(forKey: "SUAllowedChannels")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "SUFeedURL")
        UserDefaults.standard.removeObject(forKey: "SUAllowedChannels")
        super.tearDown()
    }

    func testInitialState_Disabled() {
        XCTAssertFalse(BetaChannel.isEnabled)
    }

    func testSetEnabled_True_WritesFeedAndChannels() {
        BetaChannel.setEnabled(true)
        XCTAssertTrue(BetaChannel.isEnabled)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "SUFeedURL"),
                       BetaChannel.feedURL)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "SUAllowedChannels"),
                       ["beta"])
    }

    func testSetEnabled_False_ClearsBothKeys() {
        BetaChannel.setEnabled(true)
        BetaChannel.setEnabled(false)
        XCTAssertFalse(BetaChannel.isEnabled)
        XCTAssertNil(UserDefaults.standard.string(forKey: "SUFeedURL"))
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "SUAllowedChannels"))
    }

    /// Toggling twice returns to the disabled state (round-trip).
    func testToggleTwice_ReturnsToDisabled() {
        BetaChannel.setEnabled(true)
        BetaChannel.setEnabled(false)
        XCTAssertFalse(BetaChannel.isEnabled)
    }

    /// A user with `SUAllowedChannels = ["beta"]` set externally is
    /// recognized as enabled — matches the CLI subscribe path.
    func testIsEnabled_HonorsExternalPref() {
        UserDefaults.standard.set(["beta"], forKey: "SUAllowedChannels")
        XCTAssertTrue(BetaChannel.isEnabled)
    }
}
