// PostPolishChip.swift
//
// Floating chip that appears for a few seconds after WhisperKit
// polish lands on a *fresh* voice-created sticky. Two actions:
//
//   - **Copy** — writes the polished transcript to the system
//     pasteboard, then soft-deletes the sticky (the "I just wanted
//     to dictate this somewhere else" flow — Sean's tracker item:
//     "copy to clipboard and destroy").
//   - **Delete** — soft-deletes the sticky without copying.
//
// The chip is its own borderless NSWindow at .floating level,
// anchored above the target sticky (same pattern as
// RecordingIndicator). Auto-hides after `autoHideAfter` seconds; an
// explicit Copy or Delete tap dismisses it immediately.
//
// Only shown when the sticky was *created fresh* by voice. For
// append-into-existing-sticky sessions we never show it — the user
// presumably wanted the text in that sticky.

import AppKit

final class PostPolishChip {

    enum State: Equatable { case none, visible }
    private(set) var state: State = .none

    /// Called when the user clicks Copy. The string passed back is
    /// the polished transcript — wire up the clipboard write + sticky
    /// delete in the caller (so the chip stays UI-only).
    var onCopy: ((String) -> Void)?
    /// Called when the user clicks Delete.
    var onDelete: (() -> Void)?

    private struct Chrome {
        let window: NSWindow
        let copyButton: NSButton
        let deleteButton: NSButton
    }
    private var chrome: Chrome?

    private weak var anchor: NSWindow?
    private var anchorObservers: [Any] = []
    private var hideToken = 0    // increments on each show; auto-hide compares snapshot
    /// The polished text Copy will hand back via `onCopy`. Captured
    /// when the chip is shown so the user can click any time inside
    /// the visible window without the text getting stale.
    private var polishedText: String = ""

    init() {}

    private func ensureChrome() -> Chrome {
        if let chrome { return chrome }
        // Width fits "Copy & Delete" (132pt) + 8pt gap + "Delete"
        // (78pt) + 12pt padding (6 each side) = 236pt.
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

        // 0.9.2 relabel: "Copy" → "Copy & Delete" so the combined
        // action is explicit. The button always did both (copy text
        // + soft-delete the sticky); the old label hid that.
        let copy = makeButton(title: "Copy & Delete",
                              symbol: "doc.on.doc",
                              action: #selector(handleCopy))
        copy.frame = NSRect(x: 6, y: 4, width: 132, height: 24)
        pill.addSubview(copy)

        let delete = makeButton(title: "Delete",
                                symbol: "trash",
                                action: #selector(handleDelete))
        delete.frame = NSRect(x: 140, y: 4, width: 78, height: 24)
        pill.addSubview(delete)

        window.contentView = pill
        let made = Chrome(window: window, copyButton: copy, deleteButton: delete)
        chrome = made
        return made
    }

    /// Show the chip above `anchorWindow` with `polished` as the
    /// content Copy will hand back. Auto-hides after `autoHideAfter`
    /// seconds (default 5) unless dismissed sooner.
    func show(over anchorWindow: NSWindow,
              polished: String,
              autoHideAfter: TimeInterval = 5.0) {
        let chrome = ensureChrome()
        self.anchor = anchorWindow
        self.polishedText = polished
        reposition()
        chrome.window.orderFrontRegardless()
        installAnchorObservers(anchorWindow)
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
        for token in anchorObservers {
            NotificationCenter.default.removeObserver(token)
        }
        anchorObservers.removeAll()
        anchor = nil
        polishedText = ""
        chrome?.window.orderOut(nil)
    }

    @objc private func handleCopy() {
        let text = polishedText
        hide()
        onCopy?(text)
    }

    @objc private func handleDelete() {
        hide()
        onDelete?()
    }

    private func reposition() {
        guard let chrome, let anchor else { return }
        let a = anchor.frame
        let w = chrome.window.frame.size
        // Centered above the sticky's top edge, 4pt gap. Same
        // pattern as RecordingIndicator so the two surfaces feel
        // like a related family.
        let origin = NSPoint(x: a.midX - w.width / 2,
                             y: a.maxY + 4)
        chrome.window.setFrame(NSRect(origin: origin, size: w), display: true)
    }

    private func installAnchorObservers(_ anchorWindow: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = center.addObserver(forName: name, object: anchorWindow,
                                           queue: .main) { [weak self] _ in
                self?.reposition()
            }
            anchorObservers.append(token)
        }
    }

    private func makeButton(title: String, symbol: String, action: Selector) -> NSButton {
        let b = NSButton(title: " " + title, target: self, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.font = .systemFont(ofSize: 12, weight: .medium)
        b.contentTintColor = .white
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.alignment = .center
        return b
    }

    deinit { hide() }
}
