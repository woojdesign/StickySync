import AppKit
import CloudKit
import NotesKit
import OSLog

/// Owns one note's window and mediates between the view and the store.
/// Everything it persists goes through the `NoteStore` protocol, so the
/// CloudKit swap later doesn't touch this file.
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate, NSSharingServicePickerDelegate {
    private(set) var note: Note
    private let store: NoteStore
    let window: NoteWindow
    private let noteView: NoteContentView

    var onRequestClose: ((UUID) -> Void)?

    private var expandedHeight: CGFloat
    private var saveWorkItem: DispatchWorkItem?
    private static var cascadeIndex = 0

    init(note: Note, store: NoteStore) {
        self.note = note
        self.store = store

        let layout = store.layout(for: note.id)
        let frame: NSRect
        // Real saved geometry → restore it. Otherwise (a new note, or a
        // hidden-state sentinel with zero size) → cascade a fresh frame.
        if let l = layout, l.width > 0, l.height > 0 {
            frame = NSRect(x: l.x, y: l.y, width: l.width, height: l.height)
            self.expandedHeight = CGFloat(l.expandedHeight ?? l.height)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let i = NoteWindowController.cascadeIndex
            NoteWindowController.cascadeIndex += 1
            let step = CGFloat(i % 8) * 28
            frame = NSRect(x: screen.minX + 90 + step,
                           y: screen.maxY - 200 - step,
                           width: 240, height: 180)
            self.expandedHeight = frame.height
        }

        window = NoteWindow(contentRect: frame,
                            styleMask: [.borderless, .resizable],
                            backing: .buffered,
                            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.minSize = NSSize(width: 170, height: 18)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        noteView = NoteContentView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = noteView

        super.init()

        window.delegate = self
        noteView.textView.delegate = self
        noteView.textView.string = note.content

        // Bridge the storage into NotesKit so inline `attachment://UUID`
        // references hydrate to NSImage, and existing references in the
        // loaded note's body get substituted into FFFC + inline image now.
        let storeRef = store
        noteView.markdownStorage.attachmentLoader = { [weak storeRef] uuid in
            guard let data = storeRef?.imageData(for: uuid) else { return nil }
            return NSImage(data: data)
        }
        noteView.markdownStorage.substituteAttachmentReferences()

        // Wire the paste handler to upload through NotesKit and re-sync the
        // expanded Markdown back into Note.content.
        noteView.textView.attachmentContext = .init(
            noteID: note.id,
            noteStore: store as AnyObject
        ) { [weak self] in
            guard let self else { return }
            self.note.content = self.noteView.markdownStorage.sourceString
            self.scheduleSave()
        }

        noteView.onColor = { [weak self] in self?.showColorPopover() }
        noteView.onFont = { [weak self] in self?.showFontPopover() }
        noteView.onClose = { [weak self] in self?.requestClose() }
        noteView.onToggleCollapse = { [weak self] in self?.toggleCollapse() }
        noteView.onShareWithPeople = { [weak self] in self?.shareWithPeople() }
        noteView.onHoverChange = { [weak self] hovering in
            self?.noteView.setChromeVisible(hovering, animated: true)
        }

        applyAppearance()
        refreshShareIndicator()
        noteView.scrollView.isHidden = note.collapsed

        // Repaint when the user picks a new theme (or iCloud syncs one in).
        // The token doesn't change — the hex resolution does — so we just
        // re-run applyAppearance() on every open window.
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
        DispatchQueue.main.async { [weak self] in self?.applyAppearance() }
    }

    func show(focus: Bool) {
        window.makeKeyAndOrderFront(nil)
        if focus {
            window.makeFirstResponder(noteView.textView)
        }
    }

    func close() {
        saveWorkItem?.perform()
        window.delegate = nil
        window.orderOut(nil)
    }

    // MARK: - Sync

    /// A remote update (CloudKit import, MCP write from another device)
    /// that arrived while the user was actively typing here. Held back
    /// instead of dropped so we can re-apply it when the user pauses —
    /// the silent-drop behavior was what caused remote edits to be lost
    /// (the "Mac MCP edit lost after iOS edit" / "dabi paste-image-loss"
    /// pattern).
    private var pendingRemoteUpdate: Note?

    /// Apply an incoming (synced) version of this note to the open window.
    /// Appearance and collapse always update; the text only updates when
    /// the user isn't actively editing here, so a remote change never
    /// yanks the cursor. If the user IS editing, the remote is stashed
    /// in `pendingRemoteUpdate` and applied on focus-loss
    /// (`textDidEndEditing`) or window-resign.
    func refresh(from updated: Note) {
        let appearanceChanged = updated.colorToken != note.colorToken
            || updated.fontName != note.fontName
            || updated.fontSize != note.fontSize
        let contentChanged = updated.content != note.content
        // Only hold back the text update for the note the user is *actively*
        // editing — i.e. its window is key and the editor is focused.
        let isEditing = window.isKeyWindow && window.firstResponder === noteView.textView

        if appearanceChanged {
            note.colorToken = updated.colorToken
            note.fontName = updated.fontName
            note.fontSize = updated.fontSize
            applyAppearance()
        }
        setCollapsed(updated.collapsed, persist: false, animated: true)

        if contentChanged {
            if isEditing {
                // Hold off — don't yank the cursor mid-keystroke. Apply
                // when the user pauses (textDidEndEditing) or when the
                // window resigns key — and only then if the held remote
                // is genuinely newer than our local state at that point.
                pendingRemoteUpdate = updated
                SyncLog.gate.info("refresh \(SyncLog.short(self.note.id), privacy: .public): editing → stash, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) remote=\(SyncLog.ts(updated.modifiedAt), privacy: .public)")
            } else if updated.modifiedAt > note.modifiedAt {
                // Not editing AND remote is newer → safe to apply
                // directly. The newer-than gate prevents the dabi-style
                // class of bug where a stale CloudKit import (the
                // pre-paste version, arriving mid-paste-save debounce)
                // wipes the local fresh paste.
                SyncLog.gate.info("refresh \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) remote=\(SyncLog.ts(updated.modifiedAt), privacy: .public)")
                applyRemoteContent(updated)
            } else {
                // Not editing but remote is older or equal — drop the
                // refresh. Our local will push to CloudKit on the next save.
                SyncLog.gate.info("refresh \(SyncLog.short(self.note.id), privacy: .public): drop-stale, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) remote=\(SyncLog.ts(updated.modifiedAt), privacy: .public)")
            }
        } else {
            // No content change — still useful to update modifiedAt so
            // local LWW comparisons stay accurate.
            note.modifiedAt = max(note.modifiedAt, updated.modifiedAt)
        }
    }

    private func applyRemoteContent(_ updated: Note) {
        note = updated
        let selection = noteView.textView.selectedRange
        noteView.textView.string = updated.content
        // Hydrate any `![alt](attachment://UUID)` references in the
        // incoming content into inline image placeholders.
        noteView.markdownStorage.substituteAttachmentReferences()
        applyAppearance()
        let length = (updated.content as NSString).length
        noteView.textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        pendingRemoteUpdate = nil
    }

    /// Flush any held-back remote update once the user has paused. Called
    /// from `textDidEndEditing` (focus left the text view) and
    /// `windowDidResignKey` (user moved to another window / app).
    ///
    /// LWW gate: only apply if the pending remote is genuinely newer
    /// than what's in the editor *now*. By the time the user pauses,
    /// their local edits (a paste, a few keystrokes) may carry a
    /// `modifiedAt` newer than the pending — applying it would silently
    /// revert their work. That's exactly the dabi paste-image-loss
    /// shape: pasted image at T0, stale-remote refresh held during
    /// typing, flushed on pause, image lost. Now we drop the stale
    /// pending and let the next local save push our newer state to
    /// CloudKit.
    private func flushPendingRemoteIfQuiescent() {
        guard let pending = pendingRemoteUpdate else { return }
        pendingRemoteUpdate = nil
        guard pending.modifiedAt > note.modifiedAt else {
            SyncLog.gate.info("flush \(SyncLog.short(self.note.id), privacy: .public): drop-overtaken, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
            return
        }
        SyncLog.gate.info("flush \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
        // Pause any in-flight local save so the remote isn't immediately
        // overwritten by our debounced write (now-stale-vs-remote).
        saveWorkItem?.cancel()
        applyRemoteContent(pending)
    }

    // MARK: - Appearance

    private func applyAppearance() {
        let option = FontCatalog.option(for: note.fontName)
        let font = Appearance.font(for: option, size: CGFloat(note.fontSize))
        noteView.apply(colorToken: note.colorToken, font: font)
    }

    // MARK: - Editing

    func textDidChange(_ notification: Notification) {
        // Expand `[]` / `[ ]` at line start into the canonical `- [ ] `
        // before reading the string out — keeps the underlying file format
        // portable Markdown without making the user type the heavier form.
        if let storage = noteView.textView.textStorage {
            let cursor = noteView.textView.selectedRange().location
            if let exp = MarkdownEditing.checkboxAutoExpansion(in: storage, at: cursor) {
                MarkdownEditing.applyCheckboxAutoExpansion(exp, in: storage)
                noteView.textView.setSelectedRange(NSRange(location: exp.newCursor, length: 0))
            }
        }
        // Use the storage's expanded form so any inline `\u{FFFC}` image
        // placeholders round-trip back to `![alt](attachment://UUID)` on
        // disk — saving the raw string would persist the FFFC marker.
        note.content = noteView.markdownStorage.sourceString
        note.modifiedAt = Date()
        scheduleSave()
        // The text view's selection range is implicitly at the end of the
        // newly-typed character; refresh marker fade so freshly-typed
        // `**` / `_` etc. stay visible while editing.
        refreshActiveMarkerRange()
    }

    /// Focus left the text view — natural pause. Flush any remote update
    /// we held back during the user's typing.
    func textDidEndEditing(_ notification: Notification) {
        flushPendingRemoteIfQuiescent()
    }

    /// Window lost key — user moved to another window or app. Also a
    /// natural pause point. Flush any pending remote.
    func windowDidResignKey(_ notification: Notification) {
        flushPendingRemoteIfQuiescent()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshActiveMarkerRange()
    }

    private func refreshActiveMarkerRange() {
        let selected = noteView.textView.selectedRange()
        let ns = noteView.textView.string as NSString
        guard ns.length > 0 else { return }
        // Active range = the paragraph containing the cursor, expanded to
        // cover any active selection that crosses paragraph boundaries.
        let paragraph = ns.paragraphRange(for: NSRange(location: selected.location, length: 0))
        let active = NSUnionRange(paragraph, selected)
        noteView.markdownStorage.setActiveLineRange(active)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            SyncLog.gate.info("save \(SyncLog.short(self.note.id), privacy: .public): snapshot=\(SyncLog.ts(self.note.modifiedAt), privacy: .public)")
            self.store.update(self.note)
            // Save just landed → local store now matches our editor
            // state. If a remote update was held in pendingRemoteUpdate
            // during typing and is still newer than what we just saved,
            // it's safe to apply now (LWW gate inside drops anything
            // stale). Without this, an inbound remote that arrived
            // mid-typing was *silently lost* — the user kept editing,
            // the save pushed stale content over the remote, and the
            // pending never flushed because focus never left.
            self.flushPendingRemoteIfNewer()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        store.update(note)
        flushPendingRemoteIfNewer()
    }

    /// Drop the pending remote if local state has overtaken it; apply
    /// otherwise. Called after every save completes — the other natural
    /// quiescence point besides focus-loss/window-resign. The Mac
    /// counterpart to NoteEditorView.flushPendingRemoteIfNewer on iOS.
    private func flushPendingRemoteIfNewer() {
        guard let pending = pendingRemoteUpdate else { return }
        pendingRemoteUpdate = nil
        guard pending.modifiedAt > note.modifiedAt else {
            SyncLog.gate.info("post-save \(SyncLog.short(self.note.id), privacy: .public): drop-overtaken, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
            return
        }
        SyncLog.gate.info("post-save \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
        applyRemoteContent(pending)
    }

    // MARK: - Sharing

    /// Update the share button's icon based on the current share state.
    /// Cheap synchronous call — `fetchShares(matching:)` is cached metadata.
    private func refreshShareIndicator() {
        guard let ckStore = store as? CloudKitNoteStore else {
            noteView.isShared = false
            return
        }
        noteView.isShared = ckStore.isShared(note)
    }

    /// "Share with someone…" — owner creates a CKShare (or fetches the
    /// existing one) and we hand it to NSSharingServicePicker, which
    /// presents Apple's stock recipient picker / participant management
    /// UI. The picker handles adding people, changing permissions, and
    /// "Stop Sharing"; we just refresh the indicator afterward.
    private func shareWithPeople() {
        guard let ckStore = store as? CloudKitNoteStore else { return }
        Task { @MainActor in
            do {
                let (share, container) = try await ckStore.share(note)
                // The share now exists — flip the indicator immediately so
                // the user gets visual feedback even before the picker UI is
                // fully on screen.
                self.refreshShareIndicator()
                self.presentCloudSharingPicker(share: share, container: container)
            } catch {
                NSLog("StickySync: share creation failed: \(error)")
            }
        }
    }

    /// Wrap a raw iCloud `share.url` in our landing page so recipients
    /// without StickySync installed get a Wooj-styled install prompt
    /// (`web/share/index.html`) instead of Apple's misleading "you need a
    /// newer version" wall. Installed recipients land on the page briefly
    /// then click through to the iCloud URL, which the OS routes to the
    /// app like any other share link.
    ///
    /// The base URL points at where the landing page is hosted. Update this
    /// constant once Wooj's hosting destination is settled.
    private static let landingPageBase = URL(string: "https://sticky-sync.vercel.app/")!

    private func wrappedShareURL(_ ckURL: URL) -> URL? {
        var components = URLComponents(url: Self.landingPageBase, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "ck", value: ckURL.absoluteString),
            URLQueryItem(name: "from", value: NSFullUserName()),
        ]
        return components?.url
    }

    @MainActor
    private func presentCloudSharingPicker(share: CKShare, container: CKContainer) {
        // We intentionally do NOT call `provider.registerCKShare(...)` here.
        // CKShare registration makes Apple's iMessage / Mail collaboration
        // handler send the raw `https://www.icloud.com/share/...` URL — which
        // routes correctly for recipients who already have StickySync, but
        // dead-ends with "you need a newer version" for everyone else.
        //
        // Sending the wrapped Wooj landing URL instead gives both cases a
        // graceful path: installed recipients see the page briefly and
        // click through; non-installed recipients see an install prompt and
        // can come back to open the sticky once they have the app.
        //
        // The cost is Apple's in-Messages collaboration UI (avatars,
        // "Edited just now" inline labels) — those only appear when the
        // CKShare wrapper is registered. We trade the inline collaboration
        // chrome for actually-working delivery, since most shares today are
        // to people who don't have the app yet.
        let provider = NSItemProvider()
        let urlToShare: NSURL = {
            if let raw = share.url, let wrapped = wrappedShareURL(raw) {
                return wrapped as NSURL
            }
            if let raw = share.url { return raw as NSURL }
            return URL(string: "https://share.wooj.design/")! as NSURL
        }()
        provider.registerObject(urlToShare, visibility: .all)
        let picker = NSSharingServicePicker(items: [provider])
        picker.delegate = self
        picker.show(relativeTo: noteView.shareButton.bounds,
                    of: noteView.shareButton,
                    preferredEdge: .minY)
    }

    // MARK: - Color / font popovers

    private func showColorPopover() {
        let controller = ColorPaletteController(selected: note.colorToken)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onSelect = { [weak self, weak popover] token in
            guard let self else { return }
            self.note.colorToken = token
            self.applyAppearance()
            self.saveNow()
            popover?.performClose(nil)
        }
        popover.show(relativeTo: noteView.colorButton.bounds,
                     of: noteView.colorButton,
                     preferredEdge: .maxY)
    }

    private func showFontPopover() {
        let controller = FontPickerController(selectedFontID: note.fontName, size: note.fontSize)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onSelectFont = { [weak self] id in
            guard let self else { return }
            self.note.fontName = id
            self.applyAppearance()
            self.saveNow()
        }
        controller.onSetSize = { [weak self] size in
            guard let self else { return }
            self.note.fontSize = size
            self.applyAppearance()
            self.saveNow()
        }
        popover.show(relativeTo: noteView.fontButton.bounds,
                     of: noteView.fontButton,
                     preferredEdge: .maxY)
    }

    // MARK: - Collapse

    private func toggleCollapse() {
        setCollapsed(!note.collapsed, persist: true, animated: true)
    }

    /// Applies a target collapsed state to the window. `persist` writes it back
    /// to the store — pass false when the change *came* from the store (sync).
    private func setCollapsed(_ collapsed: Bool, persist: Bool, animated: Bool) {
        // Already in the requested visual state: just keep the model in step.
        if collapsed == noteView.scrollView.isHidden {
            note.collapsed = collapsed
            if persist { saveNow() }
            return
        }

        note.collapsed = collapsed
        var frame = window.frame
        let collapsedHeight = noteView.headerHeight

        if collapsed {
            expandedHeight = frame.height
            frame.origin.y += frame.height - collapsedHeight
            frame.size.height = collapsedHeight
        } else {
            let target = max(expandedHeight, 80)
            frame.origin.y -= target - frame.height
            frame.size.height = target
        }

        noteView.scrollView.isHidden = collapsed
        window.setFrame(frame, display: true, animate: animated)
        if persist {
            saveNow()
            persistLayout()
        }
    }

    // MARK: - Close

    private func requestClose() {
        onRequestClose?(note.id)
    }

    // MARK: - Layout persistence

    private func persistLayout() {
        let f = window.frame
        let layout = NoteLayout(noteID: note.id,
                                x: Double(f.origin.x),
                                y: Double(f.origin.y),
                                width: Double(f.width),
                                height: Double(f.height),
                                expandedHeight: Double(expandedHeight))
        store.setLayout(layout)
    }

    func windowDidMove(_ notification: Notification) {
        persistLayout()
    }

    func windowDidResize(_ notification: Notification) {
        if !note.collapsed {
            expandedHeight = window.frame.height
        }
        persistLayout()
    }
}
