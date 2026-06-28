// SyncReportComposerView.swift
//
// iOS surface for the Tier 1 "Report a Sync Issue…" flow. SwiftUI sheet
// with a TextEditor for the user's "what I was doing" description and
// a Send button that builds a SyncReport, writes it to a temp .txt,
// and surfaces a ShareLink so the user picks the destination
// (Mail / Messages / AirDrop).
//
// Reached from two places:
//   - NotesListView header sync line — tapping a non-harmony status
//     opens this (the failure-state copy is its own deep-link, see
//     Phase 2.d; reporting an issue is the always-on fallback).
//   - Editor `…` menu — a "Report a Sync Issue…" item.
//
// See Shared/SyncReport.swift for the report payload shape.

import SwiftUI
import UIKit
import OSLog

struct SyncReportComposerView: View {
    let currentSyncState: String
    var onDismiss: () -> Void = {}

    @State private var userText: String = ""
    @State private var preparedReport: PreparedReport?
    @Environment(\.dismiss) private var dismiss

    /// Wrapper so the ShareLink only materializes once `userText` is
    /// captured into a frozen report (otherwise SwiftUI would rebuild
    /// the file on every keystroke).
    struct PreparedReport: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tell me what you were doing. We'll attach the last 30 minutes of sync diagnostics + the app's current state.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("No note content, no titles.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextEditor(text: $userText)
                    .font(.body)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 160)

                Spacer()

                if let prepared = preparedReport {
                    ShareLink(item: prepared.url) {
                        Label("Send Report…", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        prepareReport()
                    } label: {
                        Label("Prepare Report", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Report a Sync Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }

    /// Build the report, write it to a temp file, and stash the URL so
    /// the ShareLink can surface. Splits build-and-send into two taps
    /// so the user can see the file is ready before committing to a
    /// share destination.
    private func prepareReport() {
        let report = SyncReport(
            appVersion: Self.appVersionString,
            osVersion: Self.osVersionString,
            device: Self.deviceString,
            generatedAt: Date(),
            syncState: currentSyncState,
            lwwEvents: SyncReportBuilder.recentLWWEvents(),
            userText: userText.trimmingCharacters(in: .whitespacesAndNewlines))
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("StickySync-Sync-Report.txt")
        do {
            try report.formatted().write(to: url, atomically: true, encoding: .utf8)
            preparedReport = PreparedReport(url: url)
        } catch {
            NSLog("%@", "StickySync: failed to write sync report: \(error)")
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
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var deviceString: String {
        UIDevice.current.model
    }
}
