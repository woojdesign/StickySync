import AppKit
import NotesKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // The Xcode app target defines CLOUDKIT (Active Compilation Conditions) so
    // it syncs; the SwiftPM build and tests have no entitlements and stay local.
    #if CLOUDKIT
    let store: NoteStore = CloudKitNoteStore()
    #else
    let store: NoteStore = JSONNoteStore()
    #endif
    private var controllers: [UUID: NoteWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let notes = store.allNotes()
        if notes.isEmpty {
            let welcome = Note(
                content: "Welcome to StickySync.\n\nDrag me by the title bar. Hover to reveal the color and font controls. Double-click the title bar to roll me up. Press ⌘N for a new note.",
                colorToken: "butter"
            )
            store.add(welcome)
            openWindow(for: welcome, focus: false)
        } else {
            for note in notes {
                openWindow(for: note, focus: false)
            }
        }

        // Refresh windows when the store changes from outside (incoming sync,
        // once the CloudKit store is wired up).
        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reconcileWindows() }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Window management

    private func openWindow(for note: Note, focus: Bool) {
        let controller = NoteWindowController(note: note, store: store)
        controller.onRequestDelete = { [weak self] id in self?.deleteNote(id) }
        controllers[note.id] = controller
        controller.show(focus: focus)
    }

    private func deleteNote(_ id: UUID) {
        store.softDelete(id: id)
        controllers[id]?.close()
        controllers[id] = nil
    }

    /// Opens windows for notes that appeared and closes windows for notes that
    /// vanished — the hook a sync layer will lean on.
    private func reconcileWindows() {
        let current = store.allNotes()
        let currentIDs = Set(current.map { $0.id })

        for note in current where controllers[note.id] == nil {
            openWindow(for: note, focus: false)
        }
        for id in controllers.keys where !currentIDs.contains(id) {
            controllers[id]?.close()
            controllers[id] = nil
        }
    }

    @objc func newNote() {
        let note = Note()
        store.add(note)
        openWindow(for: note, focus: true)
    }

    @objc func closeKeyNote() {
        guard let keyWindow = NSApp.keyWindow,
              let entry = controllers.first(where: { $0.value.window === keyWindow })
        else { return }
        deleteNote(entry.key)
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About StickySync", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit StickySync",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)
        let closeItem = NSMenuItem(title: "Close Note", action: #selector(closeKeyNote), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}
