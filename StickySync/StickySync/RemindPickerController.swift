// RemindPickerController.swift
//
// 0.12.1: Mac popover that appears when the user types /remind on
// a fresh line in a sticky. 4 quick-preset buttons + a custom-time
// picker. Confirm closes the popover; caller handles storing +
// stripping the trigger line + surfacing the confirmation.
//
// Ships without NL parsing (0.12.2) and without the bell (0.12.5).
// After confirm, the caller shows a floating pill so the user
// gets feedback without seeing the bell yet.

import AppKit

final class RemindPickerController: NSViewController {
    /// The caller receives the fireAt on confirm. Nil = user
    /// dismissed without picking.
    var onConfirm: ((Date) -> Void)?
    var onCancel: (() -> Void)?
    /// 0.12.5: user tapped "Clear reminder" (edit-mode only).
    var onClear: (() -> Void)?
    /// 0.12.5: when non-nil, the custom date picker opens
    /// pre-populated with this value and the "Set reminder"
    /// button is shown by default instead of the presets.
    var initialDate: Date?
    /// 0.12.5: when true, a "Clear reminder" button is shown.
    /// Set this when opening the picker from the ⏰ bell (edit mode)
    /// rather than from a fresh /remind (create mode).
    var allowClear: Bool = false

    /// Set true when we present the custom date picker. Used so
    /// the caller doesn't tear us down on dismiss.
    private var customMode = false

    private let stack = NSStackView()
    private let datePicker = NSDatePicker()
    private let customConfirm = NSButton(title: "Set reminder",
                                          target: nil, action: nil)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 220))
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
        ])

        let title = NSTextField(labelWithString: "Remind me")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)

        for preset in RemindPreset.allCases {
            let button = NSButton(title: preset.label,
                                  target: self,
                                  action: #selector(presetTapped(_:)))
            button.bezelStyle = .regularSquare
            button.setButtonType(.momentaryLight)
            button.alignment = .left
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: presetTag(preset))
            stack.addArrangedSubview(button)
        }

        // Custom-mode UI stays hidden until the user picks
        // `.custom`. Wire the confirm target lazily too.
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.dateValue = Date().addingTimeInterval(60 * 60)
        datePicker.isHidden = true
        stack.addArrangedSubview(datePicker)

        customConfirm.target = self
        customConfirm.action = #selector(customConfirmTapped)
        customConfirm.isHidden = true
        stack.addArrangedSubview(customConfirm)

        // 0.12.5: edit mode — pre-populate the date picker and
        // hide the presets. The user can still hit any preset if
        // they want, but the primary intent when opening from the
        // bell is to tweak the existing time or clear.
        if let initial = initialDate {
            datePicker.dateValue = initial
            enterCustomMode()
            let title = NSTextField(labelWithString: "Reminder set for:")
            title.font = .systemFont(ofSize: 12)
            title.textColor = .secondaryLabelColor
            stack.insertArrangedSubview(title, at: 1)
        }

        if allowClear {
            let clear = NSButton(title: "Clear reminder",
                                 target: self, action: #selector(clearTapped))
            clear.bezelStyle = .rounded
            clear.contentTintColor = .systemRed
            stack.addArrangedSubview(clear)
        }

        view = root
    }

    private func presetTag(_ p: RemindPreset) -> String {
        switch p {
        case .in30Minutes:   return "in30"
        case .tomorrow9am:   return "tomorrow"
        case .nextMonday9am: return "nextMonday"
        case .custom:        return "custom"
        }
    }

    @objc private func presetTapped(_ sender: NSButton) {
        guard let tag = sender.identifier?.rawValue,
              let preset = RemindPreset.allCases.first(where: { presetTag($0) == tag }) else { return }
        if preset == .custom {
            enterCustomMode()
            return
        }
        guard let fireAt = preset.fireAt(now: Date()) else { return }
        onConfirm?(fireAt)
    }

    private func enterCustomMode() {
        customMode = true
        for view in stack.arrangedSubviews {
            if view is NSButton && !(view === customConfirm) {
                view.isHidden = true
            }
        }
        datePicker.isHidden = false
        customConfirm.isHidden = false
    }

    @objc private func customConfirmTapped() {
        onConfirm?(datePicker.dateValue)
    }

    @objc private func clearTapped() { onClear?() }
}
