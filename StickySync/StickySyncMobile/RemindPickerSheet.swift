// RemindPickerSheet.swift (iOS)
//
// 0.12.15: SwiftUI equivalent of Mac's RemindPickerController.
// 4 quick presets + a custom date picker path. Same
// `RemindPreset` enum + `Reminder` shape; same UX language.
//
// Sheet presentation (not popover) because iOS has no anchoring
// popovers on iPhone — sheets are the canonical modal picker.

import SwiftUI
import WoojTokens

struct RemindPickerSheet: View {

    /// Called with the chosen fire time. Nil = cancelled.
    var onConfirm: (Date) -> Void
    var onCancel: () -> Void = {}
    var onClear: (() -> Void)? = nil
    var initialDate: Date? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var customDate: Date = Date().addingTimeInterval(60 * 60)

    var body: some View {
        NavigationStack {
            VStack(spacing: WoojSpace.md) {
                if !showCustom && initialDate == nil {
                    ForEach(RemindPreset.allCases, id: \.self) { preset in
                        Button {
                            handlePreset(preset)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 17))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, WoojSpace.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(WoojColor.clay)
                    }
                }

                if showCustom || initialDate != nil {
                    DatePicker("Fire at",
                               selection: $customDate,
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.vertical, WoojSpace.xs)

                    Button {
                        onConfirm(customDate)
                        dismiss()
                    } label: {
                        Text("Set reminder")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, WoojSpace.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WoojColor.clay)
                }

                if let clear = onClear {
                    Button(role: .destructive) {
                        clear()
                        dismiss()
                    } label: {
                        Text("Clear reminder")
                            .font(.system(size: 15))
                    }
                    .padding(.top, WoojSpace.xs)
                }

                Spacer(minLength: 0)
            }
            .padding(WoojSpace.md)
            .navigationTitle("Remind me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
            }
            .onAppear {
                if let initial = initialDate {
                    customDate = initial
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func handlePreset(_ preset: RemindPreset) {
        if preset == .custom {
            showCustom = true
            return
        }
        guard let fireAt = preset.fireAt(now: Date()) else { return }
        onConfirm(fireAt)
        dismiss()
    }
}
