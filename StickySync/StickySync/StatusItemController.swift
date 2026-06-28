import AppKit
import NotesKit

/// Menu-bar (status item) list of every note. A checkmark marks notes that are
/// open on this Mac; clicking a note opens/shows it.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onNewNote: (() -> Void)?
    var onShowNote: ((UUID) -> Void)?
    var onShowList: (() -> Void)?
    var isNoteOpen: ((UUID) -> Bool)?
    /// Toggle the local MCP server on/off. Wired by AppDelegate.
    var onToggleAIAccess: ((Bool) -> Void)?
    /// Open the config sheet — the JSON snippet the user pastes into
    /// Claude Code / Cursor / etc. Only relevant when AI access is on.
    var onShowAIConfig: (() -> Void)?
    var isAIAccessEnabled: (() -> Bool)?
    var onTidyStickies: (() -> Void)?
    var onArrangeInGrid: (() -> Void)?

    private let store: NoteStore
    private let statusItem: NSStatusItem
    private let sync = SyncMonitor()

    init(store: NoteStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        refreshStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Repaint the status-item icon whenever SyncMonitor's state
        // changes — the small overlay dot is how Dropbox / iCloud
        // signal "I'm checking" without nagging the user.
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncStateDidChange),
            name: SyncMonitor.stateDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func syncStateDidChange() { refreshStatusIcon() }

    /// Base sticky-note glyph with a Dropbox-style overlay dot in the
    /// bottom-right corner that reflects sync state:
    ///   - .checking → soft yellow (we don't yet know if we're caught up)
    ///   - .syncing  → blue rotating accent (an operation is in flight)
    ///   - .error    → red exclamation
    ///   - .synced / .idle → no overlay
    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        let base = NSImage(systemSymbolName: "note.text",
                           accessibilityDescription: "StickySync")!
        button.image = composedIcon(base: base, overlay: overlaySymbol(for: sync.state))
        button.image?.isTemplate = false   // overlay needs color, so non-template
    }

    /// Returns the overlay symbol + color for the *non-harmony* states.
    /// `.harmony` returns nil — silence is the success signal. This is
    /// the Bear / Things / Drafts convention surveyed in round-2 research.
    private func overlaySymbol(for state: SyncMonitor.State) -> (String, NSColor)? {
        switch state {
        case .harmony:  return nil
        case .syncing:  return ("arrow.triangle.2.circlepath", .systemBlue)
        case .offline:  return ("cloud.slash.fill", .systemGray)
        case .error:    return ("exclamationmark.circle.fill", .systemRed)
        }
    }

    /// Compose the base symbol with a small overlay symbol in the
    /// bottom-right. The two images are rendered into a single
    /// 18×18 NSImage at NSStatusItem's natural button size.
    private func composedIcon(base: NSImage, overlay: (String, NSColor)?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            // Base glyph — tint to labelColor so the menu bar's auto
            // light/dark inversion still feels natural.
            let baseConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let basePaletted = base.withSymbolConfiguration(baseConfig)!
            basePaletted.isTemplate = true
            NSColor.labelColor.set()
            basePaletted.draw(in: rect, from: .zero,
                              operation: .sourceOver, fraction: 1.0,
                              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

            // Overlay dot in the bottom-right.
            guard let overlay else { return true }
            let (name, color) = overlay
            guard let badge = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return true }
            let badgeConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            let badgeSized = badge.withSymbolConfiguration(badgeConfig)!
            let badgeRect = NSRect(x: rect.maxX - 10, y: 0, width: 10, height: 10)

            // White ring behind the badge so it stays legible on top of
            // the dark/light menu bar — mirrors how Dropbox draws its
            // sync dot.
            let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1))
            NSColor.windowBackgroundColor.setFill()
            ring.fill()

            color.set()
            badgeSized.draw(in: badgeRect, from: .zero,
                            operation: .sourceOver, fraction: 1.0,
                            respectFlipped: true, hints: nil)
            return true
        }
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

        // Sync line — only present when there's something to say. Silence
        // (the `.harmony` state) is the success signal; showing "Synced"
        // would be overstating what we can actually verify, and round-2
        // research is unanimous that no respected app does this.
        if let title = syncTitle {
            let syncItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            syncItem.isEnabled = false
            syncItem.image = syncImage
            menu.addItem(syncItem)
        }

        menu.addItem(.separator())
        let tidy = NSMenuItem(title: "Tidy Stickies",
                              action: #selector(tidyStickiesTapped), keyEquivalent: "")
        tidy.target = self
        menu.addItem(tidy)
        let arrangeGrid = NSMenuItem(title: "Arrange in Grid",
                                     action: #selector(arrangeInGridTapped), keyEquivalent: "")
        arrangeGrid.target = self
        menu.addItem(arrangeGrid)

        menu.addItem(.separator())
        menu.addItem(themeSubmenu())
        let whatsNew = NSMenuItem(title: "What’s new in StickySync",
                                  action: #selector(showWhatsNew),
                                  keyEquivalent: "")
        whatsNew.target = self
        menu.addItem(whatsNew)
        menu.addItem(aiAccessSubmenu())
        menu.addItem(.separator())
        // Tier 1 verification surface — see Shared/SyncReport.swift.
        // Lets non-technical testers send us a report bundle with the
        // last 30 min of LWW gate events + current sync state without
        // having to know how `log show` works.
        let report = NSMenuItem(title: "Report a Sync Issue…",
                                action: #selector(reportSyncIssue), keyEquivalent: "")
        report.target = self
        menu.addItem(report)
        menu.addItem(NSMenuItem(title: "Quit StickySync",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    /// "AI access" submenu. Hidden from anyone who doesn't open it (the
    /// label itself is the only surface) — power-user feature, no
    /// nagging. Enable toggles the local MCP server; Show config opens
    /// the JSON snippet to paste into the user's AI client.
    private func aiAccessSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "AI access", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "AI access")
        let enabled = isAIAccessEnabled?() ?? false

        let toggle = NSMenuItem(title: "Enable AI access",
                                action: #selector(toggleAIAccess(_:)),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        sub.addItem(toggle)

        let config = NSMenuItem(title: "Show config…",
                                action: #selector(showAIConfig),
                                keyEquivalent: "")
        config.target = self
        config.isEnabled = enabled
        sub.addItem(config)

        parent.submenu = sub
        return parent
    }

    @objc private func toggleAIAccess(_ sender: NSMenuItem) {
        // The handler flips MCPSettings + starts/stops the server.
        // It also opens the config sheet on first enable.
        let nowEnabled = sender.state != .on
        onToggleAIAccess?(nowEnabled)
    }

    @objc private func showAIConfig() {
        onShowAIConfig?()
    }

    /// Drop the latest "what's new" sticky on demand (or open the existing
    /// one if it's already in the store), and tell the host to bring its
    /// window to the front so the user sees it immediately rather than
    /// hunting the list.
    var onShowWhatsNew: ((Note) -> Void)?
    @objc private func showWhatsNew() {
        guard let note = ReleaseNotes.dropLatest(into: store) else { return }
        onShowWhatsNew?(note)
    }

    @objc private func tidyStickiesTapped() { onTidyStickies?() }
    @objc private func arrangeInGridTapped() { onArrangeInGrid?() }

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
            item.image = Appearance.themeSwatchImage(for: t)
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.shared.select(id)
    }

    @objc private func reportSyncIssue() {
        SyncReportComposer.shared.present(currentSyncState: syncStateString())
    }

    /// Stringify the SyncMonitor state for the report header without
    /// coupling the report code to the enum's full type. "harmony" /
    /// "syncing" / "offline" / "error.network" etc.
    private func syncStateString() -> String {
        switch sync.state {
        case .harmony:               return "harmony"
        case .syncing:               return "syncing"
        case .offline:               return "offline"
        case .error(let kind):       return "error.\(kind.rawValue)"
        }
    }

    /// Sync menu-line copy. Returns nil in `.harmony` so the line is
    /// suppressed entirely. Failure copies follow the round-2 research
    /// pattern: cause + fix in the same sentence, word is "Couldn't sync"
    /// not "Sync error."
    private var syncTitle: String? {
        switch sync.state {
        case .harmony:        return nil
        case .syncing:        return "Syncing…"
        case .offline:        return "Offline — changes will sync when you're back"
        case .error(.account): return "Sign in to iCloud to keep notes in sync"
        case .error(.quota):  return "iCloud storage is full"
        case .error(.network): return "Offline — changes will sync when you're back"
        case .error(.unknown): return "Couldn't sync — will retry"
        }
    }

    private var syncImage: NSImage? {
        let name: String
        switch sync.state {
        case .harmony:  return nil
        case .syncing:  name = "arrow.triangle.2.circlepath"
        case .offline:  name = "cloud.slash"
        case .error:    name = "exclamationmark.icloud"
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
