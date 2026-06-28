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
    ///   - .harmony  → no overlay
    ///   - .syncing  → blue rotating accent (an operation is in flight)
    ///   - .offline  → gray cloud.slash
    ///   - .error    → red exclamation
    ///
    /// Implementation note: the base glyph is a **template** image
    /// (system auto-tints to match the menu bar — black on light, white
    /// on dark, transparency-aware on the wallpaper-tracking variant).
    /// The colored overlay dot lives in a **separate NSImageView
    /// subview** of the status button so it can keep its own color
    /// without forcing `isTemplate = false` on the whole image (which
    /// would defeat the auto-tint). This is the only reliable way; the
    /// 0.7.28/0.7.29 attempts to detect the menu bar's appearance from
    /// outside (`NSApp.effectiveAppearance`, `button.effectiveAppearance`)
    /// both gave wrong answers in transparent-menu-bar mode, so the
    /// base painted as flat black on dark bars.
    private let overlayBadge: NSImageView = {
        let v = NSImageView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.imageScaling = .scaleProportionallyDown
        return v
    }()

    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }

        // Base glyph as a template image so the menu bar handles tinting
        // natively — same path WiFi / clock / battery use.
        if button.image == nil {
            let base = NSImage(systemSymbolName: "note.text",
                               accessibilityDescription: "StickySync")
            base?.isTemplate = true
            button.image = base
            button.imagePosition = .imageOnly
        }

        // Lazily attach the overlay badge subview once the button
        // exists. NSStatusBarButton is an NSButton; subviews layer on
        // top of its image and Auto Layout positions them.
        if overlayBadge.superview == nil {
            button.addSubview(overlayBadge)
            NSLayoutConstraint.activate([
                overlayBadge.widthAnchor.constraint(equalToConstant: 10),
                overlayBadge.heightAnchor.constraint(equalToConstant: 10),
                overlayBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
                overlayBadge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2),
            ])
        }

        // Update the overlay's image + color to match the current state.
        if let (symbolName, color) = overlaySymbol(for: sync.state),
           let badgeImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            // Non-template so we can color it ourselves; tinted via
            // contentTintColor (NSImageView understands).
            badgeImage.isTemplate = false
            overlayBadge.image = badgeImage
            overlayBadge.contentTintColor = color
            overlayBadge.isHidden = false
        } else {
            overlayBadge.isHidden = true
        }
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

    // composedIcon removed in 0.7.30 — see refreshStatusIcon's doc
    // comment for why the off-screen-composed approach can't reliably
    // resolve the menu-bar appearance.

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
