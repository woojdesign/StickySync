import AppKit
import NotesKit

/// A window listing every note (open or closed on this Mac) with a color
/// swatch and preview. Double-click to open/show; Delete removes it everywhere.
final class NotesListWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onShowNote: ((UUID) -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onNewNote: (() -> Void)?
    var isNoteOpen: ((UUID) -> Bool)?

    private let store: NoteStore
    private let window: NSWindow
    private let tableView = NSTableView()
    private var notes: [Note] = []
    /// Per-note cached "is shared" lookup. CloudKit's isShared(_:) is
    /// cached metadata, but calling it once per row on every reload was
    /// still noisier than necessary; we compute once on reload.
    private var sharedIDs: Set<UUID> = []

    init(store: NoteStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "All Notes"
        window.minSize = NSSize(width: 280, height: 240)
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        buildUI()

        // The list cells render swatches via NotePreview.swatch(for:), which
        // resolves through the current theme. Re-render every cell when the
        // theme flips so the row swatches stay truthful.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeChanged() {
        DispatchQueue.main.async { [weak self] in self?.tableView.reloadData() }
    }

    func show() {
        reload()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        notes = store.allNotes().sorted { $0.modifiedAt > $1.modifiedAt }
        sharedIDs = computeSharedIDs(in: notes)
        tableView.reloadData()
    }

    private func computeSharedIDs(in notes: [Note]) -> Set<UUID> {
        guard let ck = store as? CloudKitNoteStore else { return [] }
        var ids: Set<UUID> = []
        for n in notes where ck.isShared(n) { ids.insert(n.id) }
        return ids
    }

    private func buildUI() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        tableView.headerView = nil
        // Card-style rows (mirroring iOS list mode): each row is painted
        // in its own sticky color, with title (15pt semibold) + a 2-line
        // snippet (12pt). 80pt accommodates two snippet lines + meta
        // column without crowding.
        tableView.rowHeight = 80
        tableView.backgroundColor = .clear
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClicked)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scroll.documentView = tableView

        let newButton = NSButton(title: "New Note", target: self, action: #selector(newNote))
        newButton.bezelStyle = .rounded
        newButton.bezelColor = .woojClay
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteClicked))
        deleteButton.bezelStyle = .rounded
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let bar = NSStackView(views: [newButton, spacer, deleteButton])
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.woojGround.usingColorSpace(.sRGB)?.cgColor
        content.addSubview(scroll)
        content.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        window.contentView = content
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let note = notes[row]
        let id = NSUserInterfaceItemIdentifier("NoteCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NoteListCellView) ?? {
            let created = NoteListCellView()
            created.identifier = id
            return created
        }()
        cell.configure(
            colorToken: note.colorToken,
            title: NotePreview.title(for: note),
            snippet: NotePreviewText.snippet2(for: note),
            modified: NotePreview.relativeTime(for: note.modifiedAt),
            isShared: sharedIDs.contains(note.id),
            hasAttachment: NotePreview.hasAttachmentReference(note),
            isOpen: isNoteOpen?(note.id) ?? false)
        cell.onDelete = { [weak self] in
            guard let self else { return }
            self.deleteWithConfirmation(note: note)
        }
        return cell
    }

    private func deleteWithConfirmation(note: Note) {
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "“\(NotePreview.title(for: note))” will be removed from all your devices. This can’t be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onDeleteNote?(note.id)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WoojRowView()
    }

    // MARK: - Actions

    @objc private func newNote() { onNewNote?() }

    @objc private func openClicked() {
        let row = tableView.clickedRow
        guard notes.indices.contains(row) else { return }
        onShowNote?(notes[row].id)
    }

    @objc private func deleteClicked() {
        let row = tableView.selectedRow
        guard notes.indices.contains(row) else { return }
        let note = notes[row]
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "“\(NotePreview.title(for: note))” will be removed from all your devices. This can’t be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onDeleteNote?(note.id)
        }
    }
}

/// One row, rendered as a *card in the note's own sticky color* — mirrors
/// the iOS list mode (0.7.20). Drops the separate swatch chip; the whole
/// row IS the swatch. Two-line snippet, per-slot text colors so dark
/// themes (Bold Berry's Burgundy, Sunny Beach's Slate, etc.) stay legible.
/// Designed at 80pt row height.
final class NoteListCellView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let sharedIcon = NSImageView()
    private let attachmentIcon = NSImageView()
    private let trashButton = NSButton()
    private var trackingArea: NSTrackingArea?

    /// Currently rendered token — used to re-resolve dynamic colors on
    /// theme switch / appearance change (see updateLayer).
    private var currentColorToken: String = Palette.defaultToken

    /// Called when the user clicks the per-row trash. The controller
    /// handles confirmation + dispatch to the store.
    var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The card lives inside an 8pt-inset region (so adjacent cards
        // breathe). Corner radius matches the iOS WoojRadius.lg of 14.
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.maximumNumberOfLines = 1

        // Two-line snippet — embedded \n in NotePreviewText.snippet2's
        // output becomes a real line break. byTruncatingTail handles
        // overflow on each line independently after word wrapping.
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.maximumNumberOfLines = 2
        snippetLabel.cell?.wraps = true
        snippetLabel.cell?.usesSingleLineMode = false

        let textStack = NSStackView(views: [titleLabel, snippetLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.alignment = .right

        sharedIcon.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "Shared")
        sharedIcon.contentTintColor = .woojClay
        sharedIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        sharedIcon.isHidden = true

        attachmentIcon.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Has attachment")
        attachmentIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        attachmentIcon.isHidden = true

        let indicatorStack = NSStackView(views: [sharedIcon, attachmentIcon])
        indicatorStack.orientation = .horizontal
        indicatorStack.alignment = .centerY
        indicatorStack.spacing = 6

        let metaStack = NSStackView(views: [dateLabel, indicatorStack])
        metaStack.orientation = .vertical
        metaStack.alignment = .trailing
        metaStack.spacing = 4

        trashButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        trashButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        trashButton.isBordered = false
        trashButton.bezelStyle = .accessoryBarAction
        trashButton.target = self
        trashButton.action = #selector(trashClicked)
        trashButton.isHidden = true
        trashButton.toolTip = "Delete this note"

        let hStack = NSStackView(views: [textStack, metaStack, trashButton])
        hStack.orientation = .horizontal
        hStack.alignment = .top
        hStack.spacing = 10
        hStack.translatesAutoresizingMaskIntoConstraints = false

        // textStack expands to fill; meta + trash hug right. Mirrors the
        // 0.7.18 fix that pinned the meta column to the right edge.
        metaStack.setContentHuggingPriority(.required, for: .horizontal)
        metaStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        trashButton.setContentHuggingPriority(.required, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        snippetLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(hStack)
        // Card inset: 6pt inset from the row's vertical extent (so cards
        // separate visually), 14pt horizontal padding inside the card.
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            hStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            metaStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        // Re-resolve the card bg + text colors against the *current*
        // appearance (light/dark) so a system-appearance flip after the
        // row was last configured still draws correctly. The cgColor
        // computation needs an active NSAppearance.currentDrawing —
        // happens naturally because updateLayer is called from inside
        // an AppKit redraw.
        layer?.backgroundColor = Appearance.background(for: currentColorToken).cgColor
        applyTextColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        trashButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        trashButton.isHidden = true
    }

    @objc private func trashClicked() {
        onDelete?()
    }

    func configure(colorToken: String,
                   title: String,
                   snippet: String,
                   modified: String,
                   isShared: Bool,
                   hasAttachment: Bool,
                   isOpen: Bool) {
        currentColorToken = colorToken
        titleLabel.stringValue = title
        snippetLabel.stringValue = snippet
        snippetLabel.isHidden = snippet.isEmpty
        dateLabel.stringValue = modified
        sharedIcon.isHidden = !isShared
        attachmentIcon.isHidden = !hasAttachment
        // Mark layer dirty so updateLayer re-paints with the new token
        // (background + text colors). Without this, switching themes
        // wouldn't flow through to already-cached cells.
        needsDisplay = true
        applyTextColors()
    }

    /// Apply per-slot text colors. Public-ish because both updateLayer
    /// and configure call it; they need to stay in sync.
    private func applyTextColors() {
        let inkColor = Appearance.text(for: currentColorToken)
        titleLabel.textColor = inkColor
        snippetLabel.textColor = inkColor.withAlphaComponent(0.7)
        dateLabel.textColor = inkColor.withAlphaComponent(0.6)
        attachmentIcon.contentTintColor = inkColor.withAlphaComponent(0.7)
        trashButton.contentTintColor = inkColor.withAlphaComponent(0.7)
        // Shared icon stays brand-clay — identity, not text. Reads
        // legibly on every slot.
    }

    func setSelected(_ selected: Bool) {
        // No selection-fill on the card itself anymore; the row is
        // already its own color. Slight rim glow on selection: kept the
        // border subtle so it doesn't clash with the shared-note clay
        // border that some rows already wear.
        layer?.borderWidth = selected ? 2 : 0
        layer?.borderColor = selected ? NSColor.woojClay.cgColor : nil
    }
}

/// Row chrome. Transparent now — each `NoteListCellView` paints its own
/// sticky-colored card (0.7.21, matching iOS 0.7.20). Selection delegated
/// to the cell, which draws a rim border instead of a fill (the cell
/// already wears the note's color; flipping its bg on selection would
/// hide the row's identity).
final class WoojRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override var isSelected: Bool {
        didSet { subviews.forEach { ($0 as? NoteListCellView)?.setSelected(isSelected) } }
    }
}
