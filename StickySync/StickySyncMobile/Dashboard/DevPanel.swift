// DevPanel.swift (iOS)
//
// 0.12.17: hidden settings sheet reached via 5-tap on the app
// title in NotesListView's navigation bar. Sean's dev-only
// panel for the dashboard capture feature; nothing here is
// user-facing for public builds. Not synced across devices.
//
// Future dev-only knobs (log dumps, force-sync, feature flags)
// can slot in as additional Form sections without new files.

import SwiftUI
import WoojTokens

struct DevPanel: View {
    @ObservedObject private var config = DashboardConfigStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var endpointField: String = ""
    @State private var tokenField: String = ""
    @State private var afterSend: AfterSendAction = .keep
    @State private var revealToken: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard Capture") {
                    LabeledField("Endpoint URL") {
                        TextField("https://...", text: $endpointField)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { config.setEndpoint(endpointField) }
                    }

                    LabeledField("Token") {
                        HStack {
                            if revealToken {
                                TextField("token", text: $tokenField)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("token", text: $tokenField)
                            }
                            Button {
                                revealToken.toggle()
                            } label: {
                                Image(systemName: revealToken ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .onSubmit { config.setToken(tokenField) }
                    }

                    Picker("After successful send", selection: $afterSend) {
                        ForEach(AfterSendAction.allCases) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .onChange(of: afterSend) { config.setAfterSend($0) }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(config.current.isConfigured ? "Ready" : "Incomplete")
                            .foregroundStyle(config.current.isConfigured ? Color.green : .secondary)
                            .font(.system(size: 13, weight: .medium))
                    }

                    Text("Sends the current sticky's text to the dashboard's capture endpoint. Nothing else is exposed publicly.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dev")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        // Commit any un-submitted edits before closing.
                        config.setEndpoint(endpointField)
                        config.setToken(tokenField)
                        dismiss()
                    }
                }
            }
            .onAppear {
                endpointField = config.current.endpoint?.absoluteString ?? ""
                tokenField = config.current.token
                afterSend = config.current.afterSend
            }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 4)
    }
}
