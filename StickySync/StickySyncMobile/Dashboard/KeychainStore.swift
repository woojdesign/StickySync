// KeychainStore.swift (iOS)
//
// 0.12.17: minimal String↔Keychain wrapper for the dashboard
// capture token. Not a general-purpose library — pinned to the
// two operations we need (get/set/delete for a single account
// under one service). Uses `kSecClassGenericPassword`.
//
// Why not UserDefaults for the token: the token is an auth
// secret; keychain items skip iCloud backup by default (the
// `.afterFirstUnlock` accessibility keeps it usable at cold
// launch but out of Encrypted Backups unless the user opts in).

import Foundation
import Security

enum KeychainStore {

    private static let service = "wooj.StickySync.DashboardCapture"

    static func setString(_ value: String, account: String) {
        let data = Data(value.utf8)
        // Delete any existing item first (SecItemUpdate has
        // multi-attribute quirks that are more error-prone than
        // delete-then-add for our simple case).
        deleteString(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func deleteString(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
