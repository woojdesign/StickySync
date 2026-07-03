// ReminderConfirmationChip.swift
//
// 0.12.1: floating "Reminder set · <when>" pill shown after the
// user confirms a /remind picker choice. Same family as UndoToast
// (0.10.0) and PostPolishChip (0.9.0) — the calm-tools transient-
// chip pattern.
//
// Ships before the chrome bell (0.12.5) so Sean has runtime
// feedback that the reminder was actually set, without needing
// to look at a bell that doesn't exist yet.

import AppKit

final class ReminderConfirmationChip {

    private struct Chrome {
        let window: NSWindow
        let label: NSTextField
    }
    private var chrome: Chrome?
    private var hideToken = 0

    init() {}

    private func ensureChrome() -> Chrome {
        if let chrome { return chrome }
        let frame = NSRect(x: 0, y: 0, width: 280, height: 32)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true

        let pill = NSView(frame: frame)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 16
        pill.layer?.cornerCurve = .continuous
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 8, width: 256, height: 16)
        pill.addSubview(label)

        window.contentView = pill
        let made = Chrome(window: window, label: label)
        chrome = made
        return made
    }

    /// Show the chip above `anchorFrame` (the sticky's window
    /// frame) with the reminder time. Auto-hides after 4s.
    func show(anchorFrame: NSRect, fireAt: Date) {
        let chrome = ensureChrome()
        chrome.label.stringValue = "Reminder set · " + Self.formattedTime(fireAt)
        reposition(anchorFrame: anchorFrame)
        chrome.window.orderFrontRegardless()

        hideToken &+= 1
        let snapshot = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.hideToken == snapshot else { return }
            self.hide()
        }
    }

    func hide() {
        chrome?.window.orderOut(nil)
    }

    private func reposition(anchorFrame a: NSRect) {
        guard let chrome else { return }
        let w = chrome.window.frame.size
        // Anchored just above the sticky's top edge — matches
        // PostPolishChip's placement family.
        let origin = NSPoint(x: a.midX - w.width / 2,
                             y: a.maxY + 4)
        chrome.window.setFrame(NSRect(origin: origin, size: w), display: true)
    }

    private static func formattedTime(_ d: Date) -> String {
        let df = DateFormatter()
        // Style: "tomorrow · 9:00 AM", "Sat 6 · 9:00 AM" etc.
        if Calendar.current.isDateInToday(d) {
            df.dateFormat = "'today, ' h:mm a"
        } else if Calendar.current.isDateInTomorrow(d) {
            df.dateFormat = "'tomorrow, ' h:mm a"
        } else {
            df.dateFormat = "EEE MMM d, h:mm a"
        }
        return df.string(from: d)
    }

    deinit { hide() }
}
