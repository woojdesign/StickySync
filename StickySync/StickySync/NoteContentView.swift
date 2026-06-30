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

/// The rounded, colored body of a note. **Chrome redesign A** (branch):
/// no top header. Native traffic-light close lives in a transparent
/// title bar via the NSWindow style mask (handled in
/// `NoteWindowController`). Per-sticky controls live in a hover-
/// revealed strip along the **bottom** edge:
///
///   ●  ●  ●  ⦿  ●  ●  ●   ·   ⇪   Aa
///   ↑                          ↑    ↑
///   seven palette colors,      share font
///   tap a color to switch      menu  popover
///   (one-tap, no popover)
final class NoteContentView: NSView {
    /// Bottom hover strip height. Slim so it doesn't compete with
    /// content when revealed.
    let bottomStripHeight: CGFloat = 30
    /// Inset at top so the native traffic lights don't cover the
    /// first line of text. NSWindow's standard title bar is ~28pt
    /// on macOS Tahoe.
    let titleBarInset: CGFloat = 28

    private(set) var colorToken: String = Palette.defaultToken

    /// Bottom hover-revealed strip container.
    let bottomStrip = NSView()
    /// Seven color buttons (one per palette slot), populated in
    /// `setup()` and ring-highlighted to show the current color.
    private(set) var colorButtons: [NSButton] = []
    let shareButton = NSButton()
    let fontButton = NSButton()
    let scrollView = NSScrollView()
    let textView: MarkdownNSTextView
    let markdownStorage: MarkdownTextStorage
    /// Custom resize handle in the bottom-right corner — larger and
    /// more reliable than the borderless-window default. Reset in
    /// `layout()`. See `ResizeGripView` at the bottom of this file.
    var resizeGrip: ResizeGripView!

    var onPickColor: ((String) -> Void)?
    var onFont: (() -> Void)?
    /// Retained for popover-based fallback flows (theme menus etc.)
    /// even though the bottom strip doesn't fire it directly.
    var onColor: (() -> Void)?
    var onClose: (() -> Void)?
    var onToggleCollapse: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    /// Tap "Share with someone…" — owner-side CKShare creation /
    /// participant-management UI. Wired by NoteWindowController.
    var onShareWithPeople: (() -> Void)?

    /// Whether this note is currently shared. Affects the share button's
    /// icon (`person.2.fill` vs `square.and.arrow.up`) and the share-menu
    /// presentation. NoteWindowController sets this on appearance and
    /// whenever the share state changes.
    var isShared: Bool = false {
        didSet { if oldValue != isShared { updateShareButtonAppearance() } }
    }

    private var trackingArea: NSTrackingArea?

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        // Build a Markdown-aware text view: the storage subclass restyles
        // bold / italic / strike / headings / lists / links on every edit
        // while the underlying string stays plain Markdown.
        let storage = MarkdownTextStorage(
            baseFont: NSFont.systemFont(ofSize: 14),
            textColor: .labelColor,
            markerColor: NSColor.labelColor.markerVariant()
        )
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.markdownStorage = storage
        self.textView = MarkdownNSTextView(frame: .zero, textContainer: container)

        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // --- Bottom hover strip ---
        // Slim colored band along the bottom holding the per-sticky
        // controls. Hover-revealed only — at rest the sticky is just
        // its content. Layout: seven color buttons (left/center), a
        // separator dot, then share + font icons (right).
        for slot in 1...7 {
            let token = String(slot)
            let b = NSButton(title: "", target: self, action: #selector(colorButtonTapped(_:)))
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.setButtonType(.momentaryChange)
            b.imagePosition = .imageOnly
            b.identifier = NSUserInterfaceItemIdentifier(rawValue: token)
            b.toolTip = "Color \(slot)"
            bottomStrip.addSubview(b)
            colorButtons.append(b)
        }

        configureIconButton(shareButton, symbol: "square.and.arrow.up",
                            tip: "Share note", action: #selector(shareTapped))
        bottomStrip.addSubview(shareButton)

        fontButton.title = "Aa"
        fontButton.isBordered = false
        fontButton.bezelStyle = .regularSquare
        fontButton.setButtonType(.momentaryChange)
        fontButton.target = self
        fontButton.action = #selector(fontTapped)
        fontButton.toolTip = "Change font"
        bottomStrip.addSubview(fontButton)

        addSubview(bottomStrip)

        // --- Scroll + text view (unchanged) ---
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

        // A wide, reliable resize grip in the bottom-right.
        resizeGrip = ResizeGripView(frame: .zero)
        resizeGrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeGrip)

        setChromeVisible(false, animated: false)
    }

    @objc private func colorButtonTapped(_ sender: NSButton) {
        guard let token = sender.identifier?.rawValue else { return }
        onPickColor?(token)
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

    /// Tap the share button:
    ///   • Already shared → straight to participant-management picker
    ///     (onShareWithPeople fetches the existing CKShare and presents).
    ///   • Otherwise → small menu offering "Share with someone…" (CKShare)
    ///     or "Share text…" (plain text via the system share sheet).
    ///   • Empty unshared note → no-op.
    @objc private func shareTapped() {
        if isShared {
            onShareWithPeople?()
            return
        }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let collab = NSMenuItem(title: "Share with someone…",
                                action: #selector(shareWithPeopleSelected),
                                keyEquivalent: "")
        collab.target = self
        collab.image = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: nil)
        menu.addItem(collab)

        let textShare = NSMenuItem(title: "Share text…",
                                   action: #selector(shareTextSelected),
                                   keyEquivalent: "")
        textShare.target = self
        textShare.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(textShare)

        // Anchor the menu in screen coordinates so AppKit positions it
        // reliably below the button regardless of the host view's flipped
        // state. (The earlier view-local origin landed off-screen above
        // the title bar on non-flipped NoteContentView.)
        guard let window = shareButton.window else { return }
        let inWindow = shareButton.convert(shareButton.bounds, to: nil)
        let inScreen = window.convertToScreen(inWindow)
        // Menu's top-left ↔ button's bottom-left, in screen coords (y up).
        let menuOrigin = NSPoint(x: inScreen.minX, y: inScreen.minY)
        menu.popUp(positioning: nil, at: menuOrigin, in: nil)
    }

    @objc private func shareWithPeopleSelected() {
        onShareWithPeople?()
    }

    @objc private func shareTextSelected() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSSharingServicePicker(items: [text]).show(relativeTo: shareButton.bounds,
                                                   of: shareButton, preferredEdge: .minY)
    }

    private func updateShareButtonAppearance() {
        let symbol = isShared ? "person.2.fill" : "square.and.arrow.up"
        let label = isShared ? "Manage sharing" : "Share note"
        shareButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        shareButton.toolTip = label
    }

    func apply(colorToken: String, font: NSFont) {
        self.colorToken = colorToken
        needsDisplay = true

        let textColor = Appearance.text(for: colorToken)
        textView.insertionPointColor = textColor
        // The text storage redraws on its own when these properties change,
        // applying baseFont/textColor across all existing Markdown spans.
        markdownStorage.baseFont = font
        markdownStorage.textColor = textColor
        markdownStorage.markerColor = textColor.markerVariant()
        textView.typingAttributes = [.foregroundColor: textColor, .font: font]

        let tint = textColor.withAlphaComponent(0.85)
        shareButton.contentTintColor = tint
        fontButton.attributedTitle = NSAttributedString(string: "Aa", attributes: [
            .foregroundColor: tint,
            .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ])
        // Refresh the color buttons' images so the current-slot ring
        // resolves against the new appearance.
        refreshColorButtonImages()
    }

    /// Draws each palette swatch as a small filled circle. The
    /// current color gets a thin outline ring so it's visually
    /// distinct without a separate selection chrome layer.
    private func refreshColorButtonImages() {
        let dotSize: CGFloat = 14
        for b in colorButtons {
            guard let token = b.identifier?.rawValue else { continue }
            let isCurrent = (token == colorToken)
            let fill = Appearance.background(for: token)
            let img = NSImage(size: NSSize(width: dotSize, height: dotSize),
                              flipped: false) { rect in
                fill.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
                if isCurrent {
                    NSColor.labelColor.withAlphaComponent(0.6).setStroke()
                    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
                return true
            }
            b.image = img
        }
    }

    func setChromeVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                bottomStrip.animator().alphaValue = alpha
            }
        } else {
            bottomStrip.alphaValue = alpha
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

        // Bottom strip lives along the bottom edge.
        bottomStrip.frame = NSRect(x: 0, y: 0, width: b.width, height: bottomStripHeight)

        // Layout inside the strip:
        //   [7 color dots, left-aligned with consistent gap]
        //   [flexible spacer]
        //   [share icon] [font icon]
        let dotSize: CGFloat = 14
        let dotGap: CGFloat = 6
        let edgePad: CGFloat = 10
        let iconSize: CGFloat = 16
        let cy = (bottomStripHeight - dotSize) / 2
        let iconCy = (bottomStripHeight - iconSize) / 2

        var x = edgePad
        for b in colorButtons {
            b.frame = NSRect(x: x, y: cy, width: dotSize, height: dotSize)
            x += dotSize + dotGap
        }

        let fontW: CGFloat = 24
        let rightEdge = bounds.width - edgePad
        fontButton.frame = NSRect(x: rightEdge - fontW, y: iconCy,
                                  width: fontW, height: iconSize)
        shareButton.frame = NSRect(x: rightEdge - fontW - 8 - iconSize, y: iconCy,
                                   width: iconSize, height: iconSize)

        // ScrollView fills the window minus the title-bar inset at top
        // and the bottom strip's height. With `.fullSizeContentView`
        // the content view extends behind the title bar, so leaving
        // titleBarInset at the top keeps text out from under the
        // traffic lights.
        let contentHeight = max(0, b.height - titleBarInset - bottomStripHeight)
        scrollView.frame = NSRect(x: 0, y: bottomStripHeight,
                                  width: b.width, height: contentHeight)
        // Do NOT set textContainer.containerSize here. textView has
        // `widthTracksTextView = true`, which makes the container width
        // follow the textView's content area (i.e. width minus
        // textContainerInset on each side). Overriding it to
        // `scrollView.contentSize.width` ignored the inset and made text
        // wrap ~2×inset past the visible right edge — the bleed bug.

        // 20x20 grip in the bottom-right corner. Bigger than the 8x8
        // default resize hit zone and we own the cursor + drag tracking
        // ourselves, so a click in the grip never falls through to
        // whatever's behind the sticky.
        let gripSize: CGFloat = 20
        resizeGrip.frame = NSRect(x: b.width - gripSize, y: 0,
                                  width: gripSize, height: gripSize)
    }
}

/// Custom resize handle in the bottom-right of a note. Borderless windows
/// get only a tiny 8x8 hit zone for resize, and a near-miss click in that
/// area passes through to whatever's behind the sticky — both because the
/// cursor changes "near" the corner without `resetCursorRects` precision,
/// and because the underlying window doesn't always claim the event.
///
/// This view owns its cursor rect (so the diagonal cursor lights up
/// exactly within bounds) and resizes the window itself in `mouseDragged`
/// — no fallthrough, no "I clicked the resize cursor but nothing
/// happened."
final class ResizeGripView: NSView {
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero

    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)  // overwritten below
        // .resizeRightDown isn't a public constant; load it by name.
        if let img = NSImage(named: NSImage.Name("NSResizeNorthWestSouthEastCursor")) {
            addCursorRect(bounds, cursor: NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8)))
        } else {
            // Fallback: any diagonal-ish indicator is better than the
            // default arrow.
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        let minSize = window.minSize
        let newWidth  = max(minSize.width,  dragStartFrame.width  + dx)
        let newHeight = max(minSize.height, dragStartFrame.height - dy)
        // Keep top-left of the window fixed while resizing the bottom-right
        // corner — i.e. anchor origin.y to top of original frame.
        let originY = dragStartFrame.origin.y + dragStartFrame.height - newHeight
        window.setFrame(NSRect(x: dragStartFrame.origin.x,
                               y: originY,
                               width: newWidth,
                               height: newHeight),
                        display: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle visual cue — three short hairlines in the corner so the
        // grip is *findable*, not just behaviorally present. Matches
        // typical Mac-app resize chevrons but quiet enough not to clutter
        // a sticky.
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(1)
        for i in 0..<3 {
            let inset = CGFloat(4 + i * 4)
            ctx.move(to: CGPoint(x: bounds.maxX - inset, y: bounds.minY + 4))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 4, y: bounds.minY + inset))
        }
        ctx.strokePath()
    }
}
