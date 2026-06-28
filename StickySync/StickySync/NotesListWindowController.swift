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
        // Two-line row: title (15pt semibold) + snippet (12pt regular)
        // + meta column on the right. 64pt gives comfortable breathing
        // room without making the list feel sparse.
        tableView.rowHeight = 64
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
            swatch: NotePreview.swatch(for: note.colorToken, size: 20),
            title: NotePreview.title(for: note),
            snippet: NotePreview.snippet(for: note),
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

/// One row: swatch | (title + snippet) | (date + share/attach indicators + hover trash).
/// Designed at 64pt row height so two lines of text + meta column have room.
final class NoteListCellView: NSView {
    private let swatchView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let sharedIcon = NSImageView()
    private let attachmentIcon = NSImageView()
    /// Hover-revealed trash — see hover/exit handlers. Standard Mac
    /// affordance (Mail, Reminders). The bottom-bar Delete button is
    /// kept as a keyboard-driven backup.
    private let trashButton = NSButton()
    private var trackingArea: NSTrackingArea?

    /// Called when the user clicks the per-row trash. The controller
    /// handles confirmation + dispatch to the store.
    var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = .woojInk

        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.maximumNumberOfLines = 1
        snippetLabel.textColor = .woojTertiary

        let textStack = NSStackView(views: [titleLabel, snippetLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .woojTertiary
        dateLabel.alignment = .right

        sharedIcon.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "Shared")
        sharedIcon.contentTintColor = .woojClay
        sharedIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        sharedIcon.isHidden = true

        attachmentIcon.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Has attachment")
        attachmentIcon.contentTintColor = .woojTertiary
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

        // Trash button: SF Symbol, borderless. Hidden by default; shown
        // on hover via mouseEntered/mouseExited.
        trashButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        trashButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        trashButton.contentTintColor = .secondaryLabelColor
        trashButton.isBordered = false
        trashButton.bezelStyle = .accessoryBarAction
        trashButton.target = self
        trashButton.action = #selector(trashClicked)
        trashButton.isHidden = true
        trashButton.toolTip = "Delete this note"

        let hStack = NSStackView(views: [swatchView, textStack, metaStack, trashButton])
        hStack.orientation = .horizontal
        hStack.alignment = .centerY
        hStack.spacing = 10
        hStack.translatesAutoresizingMaskIntoConstraints = false
        swatchView.setContentHuggingPriority(.required, for: .horizontal)
        metaStack.setContentHuggingPriority(.required, for: .horizontal)
        trashButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 20),
            swatchView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    func configure(swatch: NSImage,
                   title: String,
                   snippet: String,
                   modified: String,
                   isShared: Bool,
                   hasAttachment: Bool,
                   isOpen: Bool) {
        swatchView.image = swatch
        titleLabel.stringValue = title
        snippetLabel.stringValue = snippet
        snippetLabel.isHidden = snippet.isEmpty
        dateLabel.stringValue = modified
        sharedIcon.isHidden = !isShared
        attachmentIcon.isHidden = !hasAttachment
    }

    func setSelected(_ selected: Bool) {
        let titleColor: NSColor = selected ? .woojOnClay : .woojInk
        let secondaryColor: NSColor = selected
            ? NSColor.woojOnClay.withAlphaComponent(0.8)
            : .woojTertiary
        titleLabel.textColor = titleColor
        snippetLabel.textColor = secondaryColor
        dateLabel.textColor = secondaryColor
        // Indicator tints don't flip — they remain identifiable as
        // brand colors against either bg (clay shared icon stays clay,
        // attachment paperclip stays tertiary).
    }
}

/// Wooj chrome: each row is a warm `surface` card on the `ground`; the selected
/// row fills with `clay` (and its text flips to `onClay`).
final class WoojRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.woojSurface.usingColorSpace(.sRGB)?.setFill()
        cardPath().fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.woojClay.usingColorSpace(.sRGB)?.setFill()
        cardPath().fill()
    }
    private func cardPath() -> NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 3), xRadius: 8, yRadius: 8)
    }
    override var isSelected: Bool {
        didSet { subviews.forEach { ($0 as? NoteListCellView)?.setSelected(isSelected) } }
    }
}
