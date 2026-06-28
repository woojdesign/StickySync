// SyncReportComposer.swift
//
// Mac surface for the Tier 1 "Report a Sync Issue…" flow. Presents an
// NSAlert with a free-text field, builds a SyncReport with the caller's
// current sync state + the last 30min of LWW gate events, writes it to
// a temp .txt file, and opens NSSharingServicePicker so the user can
// send it via Mail / Messages / AirDrop.
//
// Intentionally simple — no custom NSWindow, no SwiftUI host. NSAlert
// renders fast, doesn't need its own controller, and the accessory
// view is the only custom layout we need. A future revision could
// upgrade to a windowed composer if reports become a common flow.
//
// See Shared/SyncReport.swift for the report payload shape.

import AppKit
import OSLog

@MainActor
final class SyncReportComposer {
    static let shared = SyncReportComposer()
    private init() {}

    /// Open the composer pre-seeded with the current sync state.
    /// `present` may be called multiple times in a row — each call shows
    /// a fresh alert; there's no singleton "current report" notion.
    func present(currentSyncState: String) {
        let alert = NSAlert()
        alert.messageText = "Report a Sync Issue"
        alert.informativeText = "Tell me what you were doing. We'll attach the last 30 min of sync diagnostics + the app's current state. No note content, no titles."
        alert.addButton(withTitle: "Preview & Send…")
        alert.addButton(withTitle: "Cancel")

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 90))
        text.isRichText = false
        text.font = .systemFont(ofSize: 13)
        text.isEditable = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 90))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        alert.accessoryView = scroll

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let report = SyncReport(
            appVersion: Self.appVersionString,
            osVersion: Self.osVersionString,
            device: Self.deviceString,
            generatedAt: Date(),
            syncState: currentSyncState,
            lwwEvents: SyncReportBuilder.recentLWWEvents(),
            userText: text.string.trimmingCharacters(in: .whitespacesAndNewlines))

        presentShareSheet(for: report)
    }

    /// Write the report to a temp file then surface NSSharingServicePicker
    /// from the menu-bar status item rect. The file approach lets share
    /// services that need an attachment (Mail) work naturally; services
    /// that want plain text (Messages) read the file fine.
    private func presentShareSheet(for report: SyncReport) {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("StickySync-Sync-Report.txt")
        do {
            try report.formatted().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("%@", "StickySync: failed to write sync report: \(error)")
            return
        }
        let picker = NSSharingServicePicker(items: [url])
        // Anchor on the status item if we can find it; otherwise the
        // mouse location is fine (NSSharingServicePicker handles either).
        if let button = NSApp.windows.first?.contentView {
            picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
        } else {
            picker.show(relativeTo: .zero, of: NSApp.mainWindow?.contentView ?? NSView(), preferredEdge: .minY)
        }
    }

    // MARK: - Header strings

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var deviceString: String {
        // Best-effort model identifier — `hw.model` sysctl gives "MacBookPro18,1" etc.
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
