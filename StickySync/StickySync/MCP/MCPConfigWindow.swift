// MCPConfigWindow.swift
//
// The little window that opens when the user enables AI access (and on
// "Show config…"). Shows the JSON snippet to paste into Claude Code /
// Cursor / Claude Desktop's MCP config, with a one-click Copy button
// and a Rotate-token button for the case where the user accidentally
// shared their config.

import AppKit

enum MCPConfigWindow {

    /// Build and return the config window. `onClose` lets the host
    /// (`AppDelegate`) clear its retained reference.
    @MainActor
    static func make(settings: MCPSettings,
                     onClose: @escaping () -> Void) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "StickySync · AI access"
        window.center()
        window.isReleasedWhenClosed = false

        let host = MCPConfigViewController(settings: settings, onClose: onClose)
        window.contentViewController = host
        window.delegate = host
        return window
    }
}

@MainActor
private final class MCPConfigViewController: NSViewController, NSWindowDelegate {
    private let settings: MCPSettings
    private let onClose: () -> Void
    private let textView = NSTextView()
    private var observer: NSObjectProtocol?

    init(settings: MCPSettings, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 440))
        view = container

        let heading = NSTextField(labelWithString: "Paste this into your AI client’s config")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(heading)

        let subhead = NSTextField(wrappingLabelWithString:
            "Claude Code, Cursor, and Claude Desktop all read MCP servers from " +
            "an `mcpServers` block. Drop this into ~/.claude/mcp.json (or the " +
            "equivalent for your client). The server only listens on 127.0.0.1 " +
            "and only accepts requests with the bearer token below.")
        subhead.font = .systemFont(ofSize: 12)
        subhead.textColor = .secondaryLabelColor
        subhead.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subhead)

        // Mono text-view for the JSON snippet. Selectable + read-only so
        // the user can manually select but not edit by accident.
        let scroll = NSScrollView()
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        container.addSubview(scroll)

        let copyButton = NSButton(title: "Copy",
                                  target: self, action: #selector(copyConfig))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"  // default button, ⏎ copies
        container.addSubview(copyButton)

        let rotateButton = NSButton(title: "Rotate token",
                                    target: self, action: #selector(rotateToken))
        rotateButton.translatesAutoresizingMaskIntoConstraints = false
        rotateButton.bezelStyle = .rounded
        container.addSubview(rotateButton)

        let footer = NSTextField(wrappingLabelWithString:
            "Rotating the token invalidates the snippet above. Paste the new " +
            "one wherever you used the old one.")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            subhead.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            subhead.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subhead.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: subhead.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 220),

            copyButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            copyButton.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

            rotateButton.topAnchor.constraint(equalTo: copyButton.topAnchor),
            rotateButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),

            footer.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            footer.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
        ])

        textView.string = settings.configJSON
    }

    @objc private func copyConfig() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(settings.configJSON, forType: .string)
    }

    @objc private func rotateToken() {
        _ = settings.rotateToken()
        textView.string = settings.configJSON
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.onClose() }
    }
}
