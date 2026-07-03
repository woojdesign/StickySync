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
}
