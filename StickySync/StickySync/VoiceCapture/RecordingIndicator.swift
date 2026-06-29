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

    private let window: NSWindow
    private let dot: NSView
    private let label: NSTextField
    private var pulseAnimation: CABasicAnimation?
    /// The sticky window we're shadowing. Reposition the indicator
    /// whenever it moves or resizes.
    private weak var anchor: NSWindow?
    private var anchorObservers: [Any] = []

    init() {
        let frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        window = NSWindow(contentRect: frame,
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

        dot = NSView(frame: NSRect(x: 10, y: 9, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        pill.addSubview(dot)

        label = NSTextField(labelWithString: "Listening…")
        label.frame = NSRect(x: 28, y: 5, width: 84, height: 18)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.drawsBackground = false
        pill.addSubview(label)

        window.contentView = pill
    }

    /// Show the indicator pinned above the given sticky window's top
    /// edge. Tracks its motion until `hide()` is called.
    func show(over anchorWindow: NSWindow) {
        anchor = anchorWindow
        reposition()
        window.orderFrontRegardless()
        startPulse()
        // Reposition on move/resize so the indicator stays anchored.
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = center.addObserver(forName: name, object: anchorWindow,
                                           queue: .main) { [weak self] _ in
                self?.reposition()
            }
            anchorObservers.append(token)
        }
    }

    func hide() {
        stopPulse()
        window.orderOut(nil)
        for token in anchorObservers {
            NotificationCenter.default.removeObserver(token)
        }
        anchorObservers.removeAll()
        anchor = nil
    }

    private func reposition() {
        guard let anchor else { return }
        let a = anchor.frame
        let w = window.frame.size
        // Centered above the sticky's top edge, 4pt gap.
        let origin = NSPoint(x: a.midX - w.width / 2,
                             y: a.maxY + 4)
        window.setFrame(NSRect(origin: origin, size: w), display: true)
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.layer?.add(pulse, forKey: "pulse")
        pulseAnimation = pulse
    }

    private func stopPulse() {
        dot.layer?.removeAnimation(forKey: "pulse")
        pulseAnimation = nil
    }

    deinit { hide() }
}
