// SyncDeepLinkRoutingTests.swift
//
// Pin the Mac state→System-Settings-pane mapping from 0.7.34's
// Phase 2.d wiring. Every SyncMonitor.State has exactly one expected
// outcome — a specific pane URL, or nil (the line stays informational).

import XCTest
@testable import StickySync

final class SyncDeepLinkRoutingTests: XCTestCase {

    func testHarmony_NoDeepLink() {
        XCTAssertNil(StatusItemController.syncDeepLinkURL(for: .harmony),
                     "harmony is silent; nothing to open")
    }

    func testSyncing_NoDeepLink() {
        XCTAssertNil(StatusItemController.syncDeepLinkURL(for: .syncing),
                     "syncing is transient; opening a pane mid-flight would be noise")
    }

    func testErrorUnknown_NoDeepLink() {
        XCTAssertNil(StatusItemController.syncDeepLinkURL(for: .error(.unknown)),
                     ".unknown has no clear target — fall through to the Report item")
    }

    func testErrorAccount_OpensAppleID() {
        let url = StatusItemController.syncDeepLinkURL(for: .error(.account))
        XCTAssertEqual(url?.absoluteString,
                       "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
                       "account errors must open the Apple ID / iCloud pane")
    }

    func testErrorQuota_OpensAppleID() {
        let url = StatusItemController.syncDeepLinkURL(for: .error(.quota))
        XCTAssertEqual(url?.absoluteString,
                       "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
                       "quota errors land the user where they manage iCloud storage")
    }

    func testOffline_OpensNetwork() {
        let url = StatusItemController.syncDeepLinkURL(for: .offline)
        XCTAssertEqual(url?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.network",
                       "offline ⇒ Network pane")
    }

    func testErrorNetwork_OpensNetwork() {
        let url = StatusItemController.syncDeepLinkURL(for: .error(.network))
        XCTAssertEqual(url?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.network",
                       ".network is the explicit signal for the same pane as .offline")
    }
}
