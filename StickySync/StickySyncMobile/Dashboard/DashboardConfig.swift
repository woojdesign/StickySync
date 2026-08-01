// DashboardConfig.swift (iOS)
//
// 0.12.17: hidden dev-panel-only feature. Lets Sean's own iOS
// device forward a note transcript to his ops dashboard's
// /api/capture endpoint. Spec: docs/dashboardcapture.md (or the
// upstream in the dashboard repo).
//
// Not exposed on Mac. Not synced across devices — dev-per-device
// config. Token in Keychain; URL + afterSend in UserDefaults.

import Foundation

/// What to do with the sticky after a successful dashboard send.
/// User-configurable per Sean's ask; both are legitimate flows
/// (keep = "the sticky is still useful", delete = "capture-only,
/// this was just a way to get text into the dashboard").
enum AfterSendAction: String, CaseIterable, Identifiable {
    case keep
    case delete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep:   return "Keep sticky"
        case .delete: return "Delete sticky"
        }
    }
}

/// Snapshot of the dashboard capture config, read at send time.
struct DashboardConfig: Equatable {
    var endpoint: URL?
    var token: String
    var afterSend: AfterSendAction

    /// True when the config is complete enough to fire a POST.
    var isConfigured: Bool {
        endpoint != nil && !token.isEmpty
    }

    static let empty = DashboardConfig(endpoint: nil, token: "", afterSend: .keep)
}
