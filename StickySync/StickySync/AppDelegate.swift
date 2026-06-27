import AppKit
import CloudKit
import NotesKit
#if canImport(Sparkle)
import Sparkle
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    // The Xcode app target defines CLOUDKIT (Active Compilation Conditions) so
    // it syncs; the SwiftPM build and tests have no entitlements and stay local.
    #if CLOUDKIT
    let store: NoteStore = CloudKitNoteStore()
    #else
    let store: NoteStore = JSONNoteStore()
    #endif

    private var controllers: [UUID: NoteWindowController] = [:]
    private var statusItemController: StatusItemController?
    private var listWindowController: NotesListWindowController?

    #if canImport(Sparkle)
    // In-app auto-updates. Start the updater only when a feed is configured —
    // shipping builds carry SUFeedURL via the merged Info.plist; dev (Debug)
    // builds don't, so it stays quiet there instead of erroring on a missing feed.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
        updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        setupStatusItem()

        let notes = store.allNotes()
        if notes.isEmpty {
            let welcome = Note(
                content: "Welcome to StickySync.\n\nDrag me by the title bar. Hover for the color and font controls. Close (✕) just hides a note — reopen it from the menu-bar list or All Notes (⌘L).",
                colorToken: Palette.defaultToken
            )
            store.add(welcome)
            openWindow(for: welcome, focus: false)
        } else {
            for note in notes where !store.isHidden(note.id) {
                openWindow(for: note, focus: false)
            }
        }

        // Refresh windows + lists when the store changes from outside (sync).
        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reconcileWindows() }
        }

        // Drop a "what's new in X.Y.0" release sticky if we've crossed a
        // minor/major bump since the last launch. Patch versions don't
        // surface; fresh installs treat current as seen.
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let preCount = store.allNotes().count
        ReleaseNotes.dropStickyIfNeeded(into: store, currentVersion: currentVersion)
        // Open any new release stickies the drop just inserted, otherwise
        // they'd sit in the All-Notes list invisibly until the user goes
        // looking. The launch loop above only opened pre-existing notes.
        if store.allNotes().count > preCount {
            for note in store.allNotes() where !store.isHidden(note.id)
                && !controllers.keys.contains(note.id) {
                openWindow(for: note, focus: false)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Note lifecycle

    private func openWindow(for note: Note, focus: Bool) {
        let controller = NoteWindowController(note: note, store: store)
        controller.onRequestClose = { [weak self] id in self?.hideNote(id) }
        controllers[note.id] = controller
        controller.show(focus: focus)
    }

    /// Close = hide on THIS device (device-local). The note still exists and
    /// keeps syncing; reopen it from a list.
    private func hideNote(_ id: UUID) {
        store.setHidden(true, for: id)
        controllers[id]?.close()
        controllers[id] = nil
        refreshLists()
    }

    /// Reopen a closed note (or focus it if already open).
    private func showNote(_ id: UUID) {
        store.setHidden(false, for: id)
        if let controller = controllers[id] {
            controller.show(focus: true)
        } else if let note = store.note(id: id) {
            openWindow(for: note, focus: true)
        }
        refreshLists()
    }

    /// Delete = tombstone, removed on every device. The explicit, synced action.
    private func deleteNote(_ id: UUID) {
        store.softDelete(id: id)
        controllers[id]?.close()
        controllers[id] = nil
        refreshLists()
    }

    /// Opens windows for newly-appeared (non-hidden) notes, live-updates open
    /// ones, and closes windows for notes deleted elsewhere.
    private func reconcileWindows() {
        let current = store.allNotes()
        let currentIDs = Set(current.map { $0.id })

        for note in current {
            if let controller = controllers[note.id] {
                controller.refresh(from: note)
            } else if !store.isHidden(note.id) {
                openWindow(for: note, focus: false)
            }
        }

        let staleIDs = controllers.keys.filter { !currentIDs.contains($0) }
        for id in staleIDs {
            controllers[id]?.close()
            controllers[id] = nil
        }

        refreshLists()
    }

    @objc func newNote() {
        let note = Note()
        store.add(note)
        openWindow(for: note, focus: true)
        refreshLists()
    }

    @objc func closeKeyNote() {
        if let id = keyNoteID() { hideNote(id) }
    }

    @objc func deleteKeyNote() {
        guard let id = keyNoteID(), let note = store.note(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "“\(NotePreview.title(for: note))” will be removed from all your devices. This can’t be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { deleteNote(id) }
    }

    private func keyNoteID() -> UUID? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return controllers.first(where: { $0.value.window === keyWindow })?.key
    }

    // MARK: - Lists

    private func setupStatusItem() {
        let controller = StatusItemController(store: store)
        controller.onNewNote = { [weak self] in self?.newNote() }
        controller.onShowNote = { [weak self] id in self?.showNote(id) }
        controller.onShowList = { [weak self] in self?.showList() }
        controller.onShowWhatsNew = { [weak self] note in
            guard let self else { return }
            // Make sure the (possibly newly-dropped) sticky has a window
            // before we try to focus it.
            if self.controllers[note.id] == nil {
                self.openWindow(for: note, focus: true)
            } else {
                self.showNote(note.id)
            }
        }
        controller.isNoteOpen = { [weak self] id in self?.controllers[id] != nil }
        statusItemController = controller
    }

    @objc func showList() {
        if listWindowController == nil {
            let controller = NotesListWindowController(store: store)
            controller.onShowNote = { [weak self] id in self?.showNote(id) }
            controller.onDeleteNote = { [weak self] id in self?.deleteNote(id) }
            controller.onNewNote = { [weak self] in self?.newNote() }
            controller.isNoteOpen = { [weak self] id in self?.controllers[id] != nil }
            listWindowController = controller
        }
        listWindowController?.show()
    }

    private func refreshLists() {
        listWindowController?.reload()
        // The status-bar menu rebuilds itself each time it opens, so it needs
        // no explicit refresh here.
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About StickySync",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        #if canImport(Sparkle)
        appMenu.addItem(.separator())
        let updatesItem = NSMenuItem(title: "Check for Updates…",
                                     action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                     keyEquivalent: "")
        updatesItem.target = updaterController
        appMenu.addItem(updatesItem)
        #endif
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit StickySync",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        addItem(to: fileMenu, "New Note", #selector(newNote), "n")
        addItem(to: fileMenu, "All Notes…", #selector(showList), "l")
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, "Close Note", #selector(closeKeyNote), "w")
        addItem(to: fileMenu, "Delete Note…", #selector(deleteKeyNote), "")

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

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - CloudKit Sharing — accept incoming invitations

    /// AppKit fires this when the user taps a CKShare URL (from iMessage,
    /// Mail, AirDrop, etc.) and StickySync is the registered owner of the
    /// container. Forward to the store, then — once the new note actually
    /// shows up in the store — bring the app forward and open the sticky
    /// as a window so the arrival feels like a deliberate moment, not a
    /// silent background sync.
    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard let ckStore = store as? CloudKitNoteStore else {
            NSLog("StickySync: accept-share fired but store isn't CloudKitNoteStore")
            return
        }
        Task { @MainActor in
            do {
                let arrived = try await ckStore.acceptShareInvitation(metadata: metadata)
                NSApp.activate(ignoringOtherApps: true)
                if let arrived {
                    openWindow(for: arrived, focus: true)
                }
            } catch {
                NSLog("StickySync: accept share failed: \(error)")
            }
        }
    }

    /// Universal Link handler. Tapped a `https://sticky-sync.vercel.app/?ck=…`
    /// URL anywhere on the system — Safari, Mail, a note in another app, an
    /// AirDropped message. macOS routes here based on the
    /// `applinks:sticky-sync.vercel.app` entitlement + the AASA file served
    /// at that domain. We extract the embedded iCloud share URL from the
    /// `ck` query parameter, fetch its share metadata, and run it through
    /// the same accept flow that the Messages collaboration path uses.
    func application(_ application: NSApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        guard let ckStore = store as? CloudKitNoteStore,
              let ckString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ck" })?.value,
              let ckURL = URL(string: ckString) else {
            NSLog("StickySync: universal link missing or malformed ck= param: \(url)")
            return false
        }
        Task { @MainActor in
            do {
                let arrived = try await ckStore.acceptShare(from: ckURL)
                NSApp.activate(ignoringOtherApps: true)
                if let arrived {
                    openWindow(for: arrived, focus: true)
                }
            } catch {
                NSLog("StickySync: universal-link share accept failed: \(error)")
            }
        }
        return true
    }

    /// Custom URL scheme handler — `stickysync://share?ck=…`. Used as the
    /// in-page "Open the sticky →" tap target on the landing page, which
    /// needs a deterministic open-the-app trigger that works even from the
    /// same Safari session as our landing page (where Universal Links
    /// don't re-fire).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "stickysync" {
            guard let ckString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "ck" })?.value,
                  let ckURL = URL(string: ckString),
                  let ckStore = store as? CloudKitNoteStore else {
                NSLog("StickySync: stickysync:// open with no ck=: \(url)")
                continue
            }
            Task { @MainActor in
                do {
                    let arrived = try await ckStore.acceptShare(from: ckURL)
                    NSApp.activate(ignoringOtherApps: true)
                    if let arrived {
                        openWindow(for: arrived, focus: true)
                    }
                } catch {
                    NSLog("StickySync: stickysync:// share accept failed: \(error)")
                }
            }
        }
    }
}
