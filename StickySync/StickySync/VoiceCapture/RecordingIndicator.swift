// RecordingIndicator.swift
//
// Small floating pill that hovers above the top edge of the sticky
// being recorded into. Lives in its own borderless NSWindow so it
// can sit *over* the sticky chrome without participating in the
// sticky's autolayout, and so it stays positioned correctly when
// the sticky moves.
//
// Design: solid color circle with a soft pulse + "Listening…" label,
// matched to whatever sticky we're recording into so the indicator
// visually feels like a child of that sticky (not separate
// chrome). Mirrors the breathing-dot aesthetic from iOS Capture.

import AppKit

final class RecordingIndicator {

    /// Visual state the pill is currently showing. `none` means hidden.
    /// Surfaced internal so tests can pin the state-transition contract
    /// of VoiceCaptureController (listening → polishing → none).
    enum State: Equatable { case none, listening, polishing }
    private(set) var state: State = .none

    /// Lazy AppKit chrome — created on first show so tests can
    /// instantiate VoiceCaptureController without standing up an
    /// NSWindow (under XCTest the AppKit cycle isn't bootstrapped
    /// enough for the borderless-floating window the indicator
    /// uses, and creating one aborts).
    private struct Chrome {
        let window: NSWindow
        let dot: NSView
        let spinner: NSProgressIndicator
        let label: NSTextField
    }
    private var chrome: Chrome?

    private var pulseAnimation: CABasicAnimation?
    /// The sticky window we're shadowing. Reposition the indicator
    /// whenever it moves or resizes.
    private weak var anchor: NSWindow?
    private var anchorObservers: [Any] = []

    init() {}

    private func ensureChrome() -> Chrome {
        if let chrome { return chrome }
        let frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let pill = NSView(frame: frame)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 14
        pill.layer?.cornerCurve = .continuous
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor

        let dot = NSView(frame: NSRect(x: 10, y: 9, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        pill.addSubview(dot)

        let spinner = NSProgressIndicator(frame: NSRect(x: 9, y: 6, width: 14, height: 14))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        pill.addSubview(spinner)

        let label = NSTextField(labelWithString: "Listening…")
        label.frame = NSRect(x: 28, y: 5, width: 84, height: 18)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.drawsBackground = false
        pill.addSubview(label)

        window.contentView = pill
        let made = Chrome(window: window, dot: dot, spinner: spinner, label: label)
        chrome = made
        return made
    }

    /// Show the indicator in "Listening…" state, pinned above the
    /// sticky's top edge. Tracks motion until `hide()` or transition
    /// to polishing.
    func showListening(over anchorWindow: NSWindow) {
        let c = ensureChrome()
        anchor = anchorWindow
        applyListeningVisuals(c)
        reposition()
        c.window.orderFrontRegardless()
        installAnchorObservers(anchorWindow)
        state = .listening
    }

    /// Transition to "Polishing…" state — same anchor, different
    /// visual (NSProgressIndicator spinner instead of the pulsing red
    /// dot). Called by VoiceCaptureController after stop while the
    /// WhisperKit finalize pass runs (which can take seconds for
    /// transcribe, or tens of seconds on first-run while the ~150MB
    /// base.en model downloads). Without this state the user has no
    /// signal that anything is still happening — they see the
    /// SFSpeech text settled and assume polish is broken (Sean's
    /// 0.8.1 report).
    func showPolishing() {
        state = .polishing
        // If no chrome was ever shown (test environment, or polish
        // fires without a prior listening session), skip the visual
        // update — the state flag is still tracked for the
        // VoiceCaptureController contract.
        guard let chrome else { return }
        applyPolishingVisuals(chrome)
        if !chrome.window.isVisible {
            chrome.window.orderFrontRegardless()
        }
    }

    func hide() {
        state = .none
        for token in anchorObservers {
            NotificationCenter.default.removeObserver(token)
        }
        anchorObservers.removeAll()
        anchor = nil
        guard let chrome else { return }
        stopPulse()
        chrome.spinner.stopAnimation(nil)
        chrome.window.orderOut(nil)
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

    private func applyListeningVisuals(_ c: Chrome) {
        c.dot.isHidden = false
        c.spinner.isHidden = true
        c.spinner.stopAnimation(nil)
        c.label.stringValue = "Listening…"
        startPulse(c)
    }

    private func applyPolishingVisuals(_ c: Chrome) {
        stopPulse()
        c.dot.isHidden = true
        c.spinner.isHidden = false
        c.spinner.startAnimation(nil)
        c.label.stringValue = "Polishing…"
    }

    private func reposition() {
        guard let chrome, let anchor else { return }
        let a = anchor.frame
        let w = chrome.window.frame.size
        // Centered above the sticky's top edge, 4pt gap.
        let origin = NSPoint(x: a.midX - w.width / 2,
                             y: a.maxY + 4)
        chrome.window.setFrame(NSRect(origin: origin, size: w), display: true)
    }

    private func startPulse(_ chrome: Chrome) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        chrome.dot.layer?.add(pulse, forKey: "pulse")
        pulseAnimation = pulse
    }

    private func stopPulse() {
        chrome?.dot.layer?.removeAnimation(forKey: "pulse")
        pulseAnimation = nil
    }

    deinit { hide() }
}
