import AppKit
import NotesKit

/// Menu-bar (status item) list of every note. A checkmark marks notes that are
/// open on this Mac; clicking a note opens/shows it.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onNewNote: (() -> Void)?
    var onShowNote: ((UUID) -> Void)?
    var onShowList: (() -> Void)?
    var isNoteOpen: ((UUID) -> Bool)?

    private let store: NoteStore
    private let statusItem: NSStatusItem

    init(store: NoteStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "StickySync")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuilt every time the menu opens, so it always reflects current notes.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)
        menu.addItem(.separator())

        let notes = store.allNotes()
        if notes.isEmpty {
            let empty = NSMenuItem(title: "No notes yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for note in notes {
                let item = NSMenuItem(title: NotePreview.title(for: note),
                                      action: #selector(openNote(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.id
                item.image = NotePreview.swatch(for: note.colorToken)
                item.state = (isNoteOpen?(note.id) ?? false) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let listItem = NSMenuItem(title: "Show All Notes…", action: #selector(showList), keyEquivalent: "")
        listItem.target = self
        menu.addItem(listItem)
        menu.addItem(NSMenuItem(title: "Quit StickySync",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @objc private func newNote() { onNewNote?() }
    @objc private func showList() { onShowList?() }
    @objc private func openNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onShowNote?(id)
    }
}
