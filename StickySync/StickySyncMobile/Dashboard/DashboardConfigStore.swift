// DashboardConfigStore.swift (iOS)
//
// 0.12.17: reads/writes the DashboardConfig. URL + afterSend in
// UserDefaults (not-secret, cheap access), token in Keychain
// (secret, avoids iCloud backup by default).
//
// ObservableObject so DevPanel binds directly and re-renders on
// updates without a manual reload.

import Foundation
import Combine

final class DashboardConfigStore: ObservableObject {

    static let shared = DashboardConfigStore()

    @Published private(set) var current: DashboardConfig

    private let defaults = UserDefaults.standard
    private let endpointKey = "wooj.stickysync.dashboardEndpoint"
    private let afterSendKey = "wooj.stickysync.dashboardAfterSend"
    private let tokenAccount = "captureToken"

    private init() {
        let endpointStr = defaults.string(forKey: endpointKey) ?? ""
        let afterSend = AfterSendAction(
            rawValue: defaults.string(forKey: afterSendKey) ?? ""
        ) ?? .keep
        let token = KeychainStore.getString(account: tokenAccount) ?? ""
        current = DashboardConfig(
            endpoint: URL(string: endpointStr),
            token: token,
            afterSend: afterSend)
    }

    func setEndpoint(_ value: String) {
        defaults.set(value, forKey: endpointKey)
        current.endpoint = URL(string: value)
    }

    func setToken(_ value: String) {
        if value.isEmpty {
            KeychainStore.deleteString(account: tokenAccount)
        } else {
            KeychainStore.setString(value, account: tokenAccount)
        }
        current.token = value
    }

    func setAfterSend(_ value: AfterSendAction) {
        defaults.set(value.rawValue, forKey: afterSendKey)
        current.afterSend = value
    }
}
