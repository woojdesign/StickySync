import AppKit
import NotesKit

/// 0.10.3: window listing soft-deleted notes with per-row Restore and
/// Delete Permanently actions, plus an "Empty Trash" bulk action. Mirrors
/// the shape of `NotesListWindowController` but reads from
/// `store.deletedNotes()`. Restore un-sets the tombstone (visible again
/// on all devices); Delete Permanently drops the CoreData row.
///
/// 30-day auto-purge runs on app launch (added in 0.10.4). This window
/// only ever shows notes deleted less than 30 days ago; older ones are
/// gone before the user opens the window.
final class RecentlyDeletedWindowController: NSObject, NSWindowDelegate,
                                              NSTableViewDataSource,
                                              NSTableViewDelegate {
    var onRestore: ((UUID) -> Void)?
    var onDeletePermanently: ((UUID) -> Void)?
    var onEmptyTrash: (() -> Void)?

    private let store: NoteStore
    private let window: NSWindow
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "Nothing recently deleted.")
    private var notes: [Note] = []

    init(store: NoteStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Recently Deleted"
        window.minSize = NSSize(width: 280, height: 240)
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        buildUI()

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .themeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

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
        notes = store.deletedNotes()
        tableView.reloadData()
        emptyLabel.isHidden = !notes.isEmpty
        tableView.enclosingScrollView?.isHidden = notes.isEmpty
    }

    private var emptyTrashButton: NSButton!

    private func buildUI() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        tableView.headerView = nil
        tableView.rowHeight = 92 // extra 16pt for the two-action row
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scroll.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let emptyButton = NSButton(title: "Empty Trash",
                                   target: self,
                                   action: #selector(emptyTrashClicked))
        emptyButton.bezelStyle = .rounded
        emptyTrashButton = emptyButton
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [spacer, emptyButton])
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.woojGround.usingColorSpace(.sRGB)?.cgColor
        content.addSubview(scroll)
        content.addSubview(emptyLabel)
        content.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
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
        let id = NSUserInterfaceItemIdentifier("DeletedCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? DeletedCellView) ?? {
            let created = DeletedCellView()
            created.identifier = id
            return created
        }()
        cell.configure(
            colorToken: note.colorToken,
            title: NotePreview.title(for: note),
            snippet: NotePreviewText.snippet2(for: note),
            deletedRelative: relativeDeletedTime(note.deletedAt))
        cell.onRestore = { [weak self] in self?.onRestore?(note.id) }
        cell.onDeletePermanently = { [weak self] in
            self?.confirmPermanentDelete(note: note)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WoojRowView()
    }

    private func relativeDeletedTime(_ date: Date?) -> String {
        guard let d = date else { return "Deleted" }
        return "Deleted " + NotePreview.relativeTime(for: d)
    }

    private func confirmPermanentDelete(note: Note) {
        let alert = NSAlert()
        alert.messageText = "Delete this note permanently?"
        alert.informativeText = "“\(NotePreview.title(for: note))” will be removed from all your devices. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Permanently")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onDeletePermanently?(note.id)
        }
    }

    @objc private func emptyTrashClicked() {
        guard !notes.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Recently Deleted?"
        alert.informativeText = "\(notes.count) note\(notes.count == 1 ? "" : "s") will be permanently deleted from all your devices. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onEmptyTrash?()
        }
    }
}

/// Row cell for the Recently Deleted list: colored card with title +
/// snippet + "Deleted N days ago" line, and two inline action buttons
/// (Restore in clay/primary, Delete Permanently in secondary).
final class DeletedCellView: NSView {
    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")
    private let deletedLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "Restore", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Permanently", target: nil, action: nil)

    private var currentColorToken: String = Palette.defaultToken

    var onRestore: (() -> Void)?
    var onDeletePermanently: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 4
            s.shadowOffset = NSSize(width: 0, height: -1)
            s.shadowColor = NSColor.black.withAlphaComponent(0.08)
            return s
        }()
        addSubview(card)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)

        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 1
        card.addSubview(snippetLabel)

        deletedLabel.translatesAutoresizingMaskIntoConstraints = false
        deletedLabel.font = .systemFont(ofSize: 11)
        card.addSubview(deletedLabel)

        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        restoreButton.bezelColor = .woojClay
        card.addSubview(restoreButton)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .small
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        card.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            snippetLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            deletedLabel.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 2),
            deletedLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            restoreButton.topAnchor.constraint(equalTo: deletedLabel.bottomAnchor, constant: 4),
            restoreButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            deleteButton.centerYAnchor.constraint(equalTo: restoreButton.centerYAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: restoreButton.trailingAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        card.layer?.backgroundColor = Appearance.background(for: currentColorToken).cgColor
        let textColor = Appearance.text(for: currentColorToken)
        titleLabel.textColor = textColor
        snippetLabel.textColor = textColor.withAlphaComponent(0.75)
        deletedLabel.textColor = textColor.withAlphaComponent(0.6)
    }

    func configure(colorToken: String,
                   title: String,
                   snippet: String,
                   deletedRelative: String) {
        currentColorToken = colorToken
        titleLabel.stringValue = title
        snippetLabel.stringValue = snippet
        deletedLabel.stringValue = deletedRelative
        needsDisplay = true
    }

    @objc private func restoreClicked() { onRestore?() }
    @objc private func deleteClicked() { onDeletePermanently?() }
}
