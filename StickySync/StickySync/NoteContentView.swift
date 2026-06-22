import AppKit
import NotesKit

/// The title-bar strip. Drags the window on a single click, rolls the note up
/// on a double-click. Because the chrome buttons are subviews that handle
/// their own clicks, this only fires on the empty title area.
final class HeaderView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// The rounded, colored body of a note: a title bar with hover-revealed
/// controls (color, font, close) over a plain-text editor.
final class NoteContentView: NSView {
    /// Thin top strip holding the hover controls; it's also the drag handle.
    /// Kept slim so text starts near the top of the note, like Stickies.
    let headerHeight: CGFloat = 18

    private(set) var colorToken: String = Palette.defaultToken

    let header = HeaderView()
    let colorButton = NSButton()
    let shareButton = NSButton()
    let fontButton = NSButton()
    let closeButton = NSButton()
    let scrollView = NSScrollView()
    let textView = NSTextView()

    var onColor: (() -> Void)?
    var onFont: (() -> Void)?
    var onClose: (() -> Void)?
    var onToggleCollapse: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        header.onDoubleClick = { [weak self] in self?.onToggleCollapse?() }
        addSubview(header)

        configureIconButton(colorButton, symbol: "paintpalette", tip: "Change color", action: #selector(colorTapped))
        header.addSubview(colorButton)

        configureIconButton(shareButton, symbol: "square.and.arrow.up", tip: "Share note", action: #selector(shareTapped))
        header.addSubview(shareButton)

        fontButton.title = "Aa"
        fontButton.isBordered = false
        fontButton.bezelStyle = .regularSquare
        fontButton.setButtonType(.momentaryChange)
        fontButton.target = self
        fontButton.action = #selector(fontTapped)
        fontButton.toolTip = "Change font"
        header.addSubview(fontButton)

        configureIconButton(closeButton, symbol: "xmark", tip: "Close note", action: #selector(closeTapped))
        header.addSubview(closeButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .allowed

        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        addSubview(scrollView)

        setChromeVisible(false, animated: false)
    }

    private func configureIconButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.setButtonType(.momentaryChange)
        b.target = self
        b.action = action
        b.toolTip = tip
    }

    @objc private func colorTapped() { onColor?() }
    @objc private func fontTapped() { onFont?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func shareTapped() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSSharingServicePicker(items: [text]).show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
    }

    func apply(colorToken: String, font: NSFont) {
        self.colorToken = colorToken
        needsDisplay = true

        let textColor = Appearance.text(for: colorToken)
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        if let ts = textView.textStorage, ts.length > 0 {
            let range = NSRange(location: 0, length: ts.length)
            ts.addAttribute(.foregroundColor, value: textColor, range: range)
            ts.addAttribute(.font, value: font, range: range)
        }
        textView.font = font
        textView.typingAttributes = [.foregroundColor: textColor, .font: font]

        let tint = textColor.withAlphaComponent(0.85)
        colorButton.contentTintColor = tint
        shareButton.contentTintColor = tint
        closeButton.contentTintColor = tint
        fontButton.attributedTitle = NSAttributedString(string: "Aa", attributes: [
            .foregroundColor: tint,
            .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ])
    }

    func setChromeVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                colorButton.animator().alphaValue = alpha
                shareButton.animator().alphaValue = alpha
                fontButton.animator().alphaValue = alpha
                closeButton.animator().alphaValue = alpha
            }
        } else {
            colorButton.alphaValue = alpha
            shareButton.alphaValue = alpha
            fontButton.alphaValue = alpha
            closeButton.alphaValue = alpha
        }
    }

    override func updateLayer() {
        layer?.backgroundColor = Appearance.background(for: colorToken).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func layout() {
        super.layout()
        let b = bounds
        header.frame = NSRect(x: 0, y: b.height - headerHeight, width: b.width, height: headerHeight)

        let pad: CGFloat = 7
        let size: CGFloat = 16
        let cy = (headerHeight - size) / 2
        colorButton.frame = NSRect(x: pad, y: cy, width: size, height: size)
        shareButton.frame = NSRect(x: pad + size + 6, y: cy, width: size, height: size)
        closeButton.frame = NSRect(x: header.bounds.width - pad - size, y: cy, width: size, height: size)
        fontButton.frame = NSRect(x: header.bounds.width - pad - size - 6 - 24, y: cy, width: 24, height: size)

        scrollView.frame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - headerHeight))
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    }
}
