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
    private let sync = SyncMonitor()

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

        // Quiet sync-status line, so an eventual-consistency delay reads as
        // "Syncing…" rather than "my note didn't sync."
        let syncItem = NSMenuItem(title: syncTitle, action: nil, keyEquivalent: "")
        syncItem.isEnabled = false
        syncItem.image = syncImage
        menu.addItem(syncItem)

        menu.addItem(.separator())
        menu.addItem(themeSubmenu())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StickySync",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    /// "Theme" submenu — one entry per bundled theme with a checkmark next to
    /// the active one. Picking flips `ThemeStore.shared`, which posts
    /// `.themeChanged` so open note windows + the menu's own swatches
    /// repaint on the next open.
    private func themeSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Theme")
        let currentID = ThemeStore.shared.current.id
        for t in Themes.all {
            let item = NSMenuItem(title: t.displayName,
                                  action: #selector(pickTheme(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            item.state = (t.id == currentID) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.shared.select(id)
    }

    private var syncTitle: String {
        switch sync.state {
        case .syncing: return "Syncing…"
        case .synced:  return "Synced"
        case .error:   return "Sync paused"
        case .idle:    return "iCloud"
        }
    }

    private var syncImage: NSImage? {
        let name: String
        switch sync.state {
        case .syncing: name = "arrow.triangle.2.circlepath"
        case .synced:  name = "checkmark.icloud"
        case .error:   name = "exclamationmark.icloud"
        case .idle:    name = "icloud"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: syncTitle)
        img?.isTemplate = true
        return img
    }

    @objc private func newNote() { onNewNote?() }
    @objc private func showList() { onShowList?() }
    @objc private func openNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onShowNote?(id)
    }
}
