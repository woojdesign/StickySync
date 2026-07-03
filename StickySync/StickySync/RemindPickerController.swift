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

    // Popover content sizes.
    private static let presetSize = NSSize(width: 210, height: 200)
    // 0.12.14: custom mode was (260, 300) with .clockAndCalendar —
    // Sean preferred the compact .textFieldAndStepper picker, just
    // with less padding around it. Compact size hugs the picker +
    // "Set reminder" button.
    private static let customSize = NSSize(width: 210, height: 150)

    private let stack = NSStackView()
    private let datePicker = NSDatePicker()
    private let customConfirm = NSButton(title: "Set reminder",
                                          target: nil, action: nil)

    override func loadView() {
        // 0.12.14: sized-to-content. Was 260×220 with .regularSquare
        // buttons stretched full-width + leading text = lots of
        // empty space per row. Now: ~210pt wide, rounded pill
        // buttons with centered labels, tighter row spacing.
        // Popover expands to `customSize` in custom mode.
        let root = NSView(frame: NSRect(origin: .zero, size: Self.presetSize))
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        stack.distribution = .fill
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
        ])

        let title = NSTextField(labelWithString: "Remind me")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .center
        stack.addArrangedSubview(title)

        for preset in RemindPreset.allCases {
            let button = NSButton(title: preset.label,
                                  target: self,
                                  action: #selector(presetTapped(_:)))
            button.bezelStyle = .rounded
            button.setButtonType(.momentaryLight)
            button.alignment = .center
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: presetTag(preset))
            // Rounded bezel + centerX stack alignment lets each pill
            // size to its label instead of stretching the full width.
            stack.addArrangedSubview(button)
        }

        // Custom-mode UI stays hidden until the user picks
        // `.custom`. Wire the confirm target lazily too.
        //
        // 0.12.14: kept `.textFieldAndStepper` (compact) — Sean
        // liked the picker style, just wanted less padding around
        // it in the popover. `customSize` is now sized to hug the
        // picker + Set reminder button rather than being 300pt tall.
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
        preferredContentSize = customMode ? Self.customSize : Self.presetSize
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
        // Resize the popover to fit the clock+calendar picker.
        // NSPopover observes preferredContentSize and animates.
        preferredContentSize = Self.customSize
    }

    @objc private func customConfirmTapped() {
        onConfirm?(datePicker.dateValue)
    }

    @objc private func clearTapped() { onClear?() }
}
