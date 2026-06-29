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
    private var mcpServer: MCPServer?
    private var mcpConfigWindow: NSWindow?
    private var voiceCapture: VoiceCaptureController?

    #if canImport(Sparkle)
    // In-app auto-updates. Start the updater only when a feed is configured —
    // shipping builds carry SUFeedURL via the merged Info.plist; dev (Debug)
    // builds don't, so it stays quiet there instead of erroring on a missing feed.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
        updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest / Swift Testing the host app is launched as a test
        // runner; the production launch path (CloudKit container init,
        // status item, welcome sticky, release-sticky drop, window
        // restoration) isn't what we want there and frequently crashes
        // because test environments don't carry the iCloud entitlement.
        // Xcode sets this env var when running tests; bail before the
        // heavy work and let the test runner take over.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

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

        // Also reconcile on app activate (foreground). Tier 1 report
        // 2026-06-28: an iOS-captured sticky only appeared on Mac
        // after a relaunch — LWW timestamps confirmed the import
        // landed correctly when it finally landed, so the bug wasn't
        // the gate; it was that NSPersistentStoreRemoteChange didn't
        // fire (or didn't fire promptly) for the new record while the
        // app was running. NSPersistentCloudKitContainer's import IS
        // documented as occasionally lazy. A foreground refresh is
        // the standard mitigation: the user coming back is a natural
        // signal that they want a fresh read, so refetch
        // unconditionally. allNotes() already does a fresh Core Data
        // fetch each call, so this surfaces any record the import
        // landed silently in the background.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppActivated),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)

        // Voice capture: register the global hotkey (⌃⌥V) so the user
        // can talk-to-sticky from anywhere. Phase 1 (no audio yet)
        // just inserts placeholder markers so the trigger path is
        // visible; phases 2/3 swap in AVAudioEngine + WhisperKit.
        let voice = VoiceCaptureController(store: store)
        voice.resolveKeyStickyID = { [weak self] in self?.keyNoteID() }
        voice.openNoteWindow = { [weak self] note, focus in
            self?.openWindow(for: note, focus: focus)
            // openWindow brings the window forward; also activate the
            // app so the user lands in the sticky regardless of what
            // they had focused before. Matches the user's expectation
            // when capture is triggered from outside the app.
            if focus { NSApp.activate(ignoringOtherApps: true) }
        }
        voice.appendToOpenNote = { [weak self] id, text in
            self?.controllers[id]?.appendText(text)
        }
        voice.replaceTrailingInNote = { [weak self] id, expected, new in
            self?.controllers[id]?.replaceTrailingMatch(expected, with: new)
        }
        voice.windowForSticky = { [weak self] id in
            self?.controllers[id]?.window
        }
        voice.start()
        self.voiceCapture = voice

        // Start the local AI-access HTTP server if the user enabled it
        // last session. Failure is non-fatal (e.g. port conflict) — we
        // log and surface in the UI via the "Enable AI access" toggle
        // showing as off.
        if MCPSettings.shared.isEnabled {
            startMCPServer()
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
    @objc private func handleAppActivated() {
        // Cheap (one Core Data fetch + diff against `controllers`); fine
        // to run on every activation. If nothing changed, reconcile is
        // a no-op.
        reconcileWindows()
    }

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
        controller.onToggleAIAccess = { [weak self] enable in
            guard let self else { return }
            MCPSettings.shared.setEnabled(enable)
            if enable {
                self.startMCPServer()
                // First-enable: open the config sheet immediately so the
                // user can copy the snippet into their AI client without
                // having to re-navigate the menu.
                self.showMCPConfigWindow()
            } else {
                self.stopMCPServer()
                self.mcpConfigWindow?.close()
            }
        }
        controller.onShowAIConfig = { [weak self] in self?.showMCPConfigWindow() }
        controller.isAIAccessEnabled = { MCPSettings.shared.isEnabled }
        controller.onTidyStickies = { [weak self] in self?.tidyStickies() }
        controller.onArrangeInGrid = { [weak self] in self?.arrangeInGrid() }
        controller.isNoteOpen = { [weak self] id in self?.controllers[id] != nil }
        statusItemController = controller
    }

    // MARK: - MCP server lifecycle

    private func startMCPServer() {
        guard mcpServer == nil else { return }
        let token = MCPSettings.shared.token
        let server = MCPServer(store: store as AnyObject & NoteStore, authToken: token)
        do {
            try server.start()
            mcpServer = server
        } catch {
            NSLog("MCP server failed to start: \(error)")
            MCPSettings.shared.setEnabled(false)
        }
    }

    private func stopMCPServer() {
        mcpServer?.stop()
        mcpServer = nil
    }

    @MainActor private func showMCPConfigWindow() {
        if let existing = mcpConfigWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = MCPConfigWindow.make(settings: MCPSettings.shared) { [weak self] in
            self?.mcpConfigWindow = nil
        }
        mcpConfigWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

        // MARK: StickySync (app menu)
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
        appMenu.addItem(aiAccessMainMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide StickySync",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit StickySync",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // MARK: File
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        addItem(to: fileMenu, "New Note", #selector(newNote), "n")
        addItem(to: fileMenu, "All Notes…", #selector(showList), "l")
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, "Close Note", #selector(closeKeyNote), "w")
        addItem(to: fileMenu, "Delete Note…", #selector(deleteKeyNote), "")

        // MARK: Edit
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

        // MARK: View (theme)
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(themeMainMenuItem())

        // MARK: Window (standard + arrange)
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        addItem(to: windowMenu, "Tidy Stickies", #selector(tidyStickies), "")
        addItem(to: windowMenu, "Arrange in Grid", #selector(arrangeInGrid), "")
        NSApp.windowsMenu = windowMenu

        // MARK: Help
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpItem.submenu = helpMenu
        let whatsNew = NSMenuItem(title: "What’s New in StickySync",
                                  action: #selector(showWhatsNewFromMenu),
                                  keyEquivalent: "")
        whatsNew.target = self
        helpMenu.addItem(whatsNew)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu

        // Re-render the View → Theme submenu's checkmark when the user
        // picks a theme (from any surface — status item, here, iCloud
        // sync). Same handler keeps both menus in sync.
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildThemeSubmenu),
            name: .themeChanged, object: nil)
    }

    /// Theme submenu used in the View menu — mirrors the status-item
    /// version so the two surfaces stay aligned. Rebuilt on
    /// `.themeChanged`.
    private func themeMainMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        parent.submenu = makeThemeSubmenu()
        return parent
    }

    private func makeThemeSubmenu() -> NSMenu {
        let sub = NSMenu(title: "Theme")
        let currentID = ThemeStore.shared.current.id
        for t in Themes.all {
            let item = NSMenuItem(title: t.displayName,
                                  action: #selector(pickThemeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            item.state = (t.id == currentID) ? .on : .off
            item.image = Appearance.themeSwatchImage(for: t)
            sub.addItem(item)
        }
        return sub
    }

    @objc private func rebuildThemeSubmenu() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "View" })?.submenu,
              let themeItem = viewMenu.items.first(where: { $0.title == "Theme" })
        else { return }
        themeItem.submenu = makeThemeSubmenu()
    }

    @objc private func pickThemeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.shared.select(id)
    }

    /// AI access submenu used in the StickySync app menu. Same shape as
    /// the status item version — Enable toggle + Show config… — so the
    /// power-user feature lives in the canonical "app preferences"
    /// location while still being available from the tray icon.
    private func aiAccessMainMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "AI access", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "AI access")
        let toggle = NSMenuItem(title: "Enable AI access",
                                action: #selector(toggleAIAccessFromMenu(_:)),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = MCPSettings.shared.isEnabled ? .on : .off
        sub.addItem(toggle)

        let config = NSMenuItem(title: "Show config…",
                                action: #selector(showAIConfigFromMenu),
                                keyEquivalent: "")
        config.target = self
        config.isEnabled = MCPSettings.shared.isEnabled
        sub.addItem(config)
        parent.submenu = sub
        return parent
    }

    @objc private func toggleAIAccessFromMenu(_ sender: NSMenuItem) {
        let nowEnabled = sender.state != .on
        MCPSettings.shared.setEnabled(nowEnabled)
        if nowEnabled {
            startMCPServer()
            showMCPConfigWindow()
        } else {
            stopMCPServer()
            mcpConfigWindow?.close()
        }
        sender.state = nowEnabled ? .on : .off
        if let parent = sender.menu?.items, parent.count > 1 {
            parent[1].isEnabled = nowEnabled
        }
    }

    @objc private func showAIConfigFromMenu() {
        showMCPConfigWindow()
    }

    @objc private func tidyStickies() {
        ArrangeStickies.tidy(Array(controllers.values))
    }

    @objc private func arrangeInGrid() {
        ArrangeStickies.grid(Array(controllers.values))
    }

    @objc private func showWhatsNewFromMenu() {
        guard let note = ReleaseNotes.dropLatest(into: store) else { return }
        if controllers[note.id] == nil {
            openWindow(for: note, focus: true)
        } else {
            showNote(note.id)
        }
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
