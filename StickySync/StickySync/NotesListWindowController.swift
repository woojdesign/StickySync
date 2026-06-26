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
        notes = store.allNotes()
        tableView.reloadData()
    }

    private func buildUI() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 50
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
        cell.configure(swatch: NotePreview.swatch(for: note.colorToken, size: 16),
                       title: NotePreview.title(for: note),
                       open: isNoteOpen?(note.id) ?? false)
        return cell
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

/// One row: color swatch, title, and open/closed status.
final class NoteListCellView: NSView {
    private let swatchView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = .woojInk
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .woojTertiary

        let textStack = NSStackView(views: [titleLabel, statusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let hStack = NSStackView(views: [swatchView, textStack])
        hStack.orientation = .horizontal
        hStack.alignment = .centerY
        hStack.spacing = 9
        hStack.translatesAutoresizingMaskIntoConstraints = false
        swatchView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            hStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(swatch: NSImage, title: String, open: Bool) {
        swatchView.image = swatch
        titleLabel.stringValue = title
        statusLabel.stringValue = open ? "Open" : "Closed"
    }

    func setSelected(_ selected: Bool) {
        titleLabel.textColor = selected ? .woojOnClay : .woojInk
        statusLabel.textColor = selected ? NSColor.woojOnClay.withAlphaComponent(0.8) : .woojTertiary
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
