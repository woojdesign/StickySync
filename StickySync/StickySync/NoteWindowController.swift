import AppKit
import CloudKit
import NotesKit

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

    /// Apply an incoming (synced) version of this note to the open window.
    /// Appearance and collapse always update; the text only updates when the
    /// user isn't actively editing here, so a remote change never yanks the
    /// cursor out from under them.
    func refresh(from updated: Note) {
        let appearanceChanged = updated.colorToken != note.colorToken
            || updated.fontName != note.fontName
            || updated.fontSize != note.fontSize
        let contentChanged = updated.content != note.content
        // Only hold back the text update for the note the user is *actively*
        // editing — i.e. its window is key and the editor is focused. A
        // background note keeps its text view as first responder even when it
        // isn't key, so without the isKeyWindow check, any note you'd ever
        // clicked into would stop accepting synced edits.
        let isEditing = window.isKeyWindow && window.firstResponder === noteView.textView

        note = updated

        if appearanceChanged { applyAppearance() }
        setCollapsed(updated.collapsed, persist: false, animated: true)

        if contentChanged && !isEditing {
            let selection = noteView.textView.selectedRange
            noteView.textView.string = updated.content
            applyAppearance()
            let length = (updated.content as NSString).length
            noteView.textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    // MARK: - Appearance

    private func applyAppearance() {
        let option = FontCatalog.option(for: note.fontName)
        let font = Appearance.font(for: option, size: CGFloat(note.fontSize))
        noteView.apply(colorToken: note.colorToken, font: font)
    }

    // MARK: - Editing

    func textDidChange(_ notification: Notification) {
        note.content = noteView.textView.string
        scheduleSave()
        // The text view's selection range is implicitly at the end of the
        // newly-typed character; refresh marker fade so freshly-typed
        // `**` / `_` etc. stay visible while editing.
        refreshActiveMarkerRange()
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
            self.store.update(self.note)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        store.update(note)
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

    @MainActor
    private func presentCloudSharingPicker(share: CKShare, container: CKContainer) {
        // The documented Mac path is an NSItemProvider that registers the
        // share + container — passing raw [CKShare, CKContainer] as picker
        // items doesn't surface the collaboration UI (the share is created
        // in the back-end, but the picker presents nothing visible).
        let provider = NSItemProvider()
        provider.registerCKShare(share, container: container, allowedSharingOptions: .standard)
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
