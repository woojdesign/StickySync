// UndoToast.swift
//
// 0.10.0: floating "Note deleted · Undo" pill shown after the user
// deletes a note from the ⋯ overflow menu. Non-modal (Notion /
// gmail pattern — undo over confirm, per the UX research).
//
// Positioning: anchored to where the deleted sticky WAS (last-known
// window frame). If the user hits Undo we can restore the sticky at
// the same spot. Auto-dismisses after `autoHideAfter` seconds; an
// explicit Undo tap dismisses it immediately.
//
// Deliberately close to PostPolishChip in visual language (rounded
// black pill, white text, floating .floating level). Keeps the
// "transient action toasts" family consistent.

import AppKit

final class UndoToast {

    enum State: Equatable { case none, visible }
    private(set) var state: State = .none

    /// Fired when the user taps Undo. The controller wires this to
    /// re-add the note (unset the soft-delete flag) + reopen its
    /// window at the captured origin.
    var onUndo: (() -> Void)?

    private struct Chrome {
        let window: NSWindow
        let undoButton: NSButton
    }
    private var chrome: Chrome?
    private var hideToken = 0

    init() {}

    private func ensureChrome() -> Chrome {
        if let chrome { return chrome }
        // Width fits the label + a comfy "Undo" button. Same 32pt
        // height as PostPolishChip so the two chip families feel
        // related.
        let frame = NSRect(x: 0, y: 0, width: 236, height: 32)
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

        // "Note deleted" label, left-aligned inside the pill.
        let label = NSTextField(labelWithString: "Note deleted")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 14, y: 8, width: 130, height: 16)
        pill.addSubview(label)

        // Right-aligned "Undo" pill button.
        let undo = NSButton(title: "Undo", target: self,
                            action: #selector(handleUndo))
        undo.bezelStyle = .inline
        undo.isBordered = false
        undo.font = .systemFont(ofSize: 12, weight: .semibold)
        undo.contentTintColor = .white
        undo.frame = NSRect(x: 156, y: 4, width: 68, height: 24)
        pill.addSubview(undo)

        window.contentView = pill
        let made = Chrome(window: window, undoButton: undo)
        chrome = made
        return made
    }

    /// Show the toast near the deleted sticky's last position.
    /// `anchorFrame` is the window frame the sticky occupied
    /// immediately before deletion — we center the toast horizontally
    /// on the sticky and place it a hair above the sticky's
    /// midpoint. Auto-hides after `autoHideAfter` seconds.
    func show(anchorFrame: NSRect,
              autoHideAfter: TimeInterval = 5.0) {
        let chrome = ensureChrome()
        reposition(anchorFrame: anchorFrame)
        chrome.window.orderFrontRegardless()
        state = .visible

        hideToken &+= 1
        let snapshot = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter) { [weak self] in
            guard let self, self.hideToken == snapshot else { return }
            self.hide()
        }
    }

    func hide() {
        state = .none
        chrome?.window.orderOut(nil)
    }

    @objc private func handleUndo() {
        hide()
        onUndo?()
    }

    private func reposition(anchorFrame a: NSRect) {
        guard let chrome else { return }
        let w = chrome.window.frame.size
        // Horizontally centered on the sticky's last position,
        // vertically at the sticky's vertical center. This puts the
        // toast right where the user was looking when they deleted.
        let origin = NSPoint(x: a.midX - w.width / 2,
                             y: a.midY - w.height / 2)
        chrome.window.setFrame(NSRect(origin: origin, size: w), display: true)
    }

    deinit { hide() }
}
