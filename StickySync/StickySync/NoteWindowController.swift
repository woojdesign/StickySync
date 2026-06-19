import AppKit
import NotesKit

/// Owns one note's window and mediates between the view and the store.
/// Everything it persists goes through the `NoteStore` protocol, so the
/// CloudKit swap later doesn't touch this file.
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: Note
    private let store: NoteStore
    let window: NoteWindow
    private let noteView: NoteContentView

    var onRequestDelete: ((UUID) -> Void)?

    private var expandedHeight: CGFloat
    private var saveWorkItem: DispatchWorkItem?
    private static var cascadeIndex = 0

    init(note: Note, store: NoteStore) {
        self.note = note
        self.store = store

        let layout = store.layout(for: note.id)
        let frame: NSRect
        if let l = layout {
            frame = NSRect(x: l.x, y: l.y, width: l.width, height: l.height)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let i = NoteWindowController.cascadeIndex
            NoteWindowController.cascadeIndex += 1
            let step = CGFloat(i % 8) * 28
            frame = NSRect(x: screen.minX + 90 + step,
                           y: screen.maxY - 200 - step,
                           width: 240, height: 180)
        }
        self.expandedHeight = CGFloat(layout?.expandedHeight ?? Double(frame.height))

        window = NoteWindow(contentRect: frame,
                            styleMask: [.borderless, .resizable],
                            backing: .buffered,
                            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.minSize = NSSize(width: 170, height: 30)
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
        noteView.onClose = { [weak self] in self?.requestDelete() }
        noteView.onToggleCollapse = { [weak self] in self?.toggleCollapse() }
        noteView.onHoverChange = { [weak self] hovering in
            self?.noteView.setChromeVisible(hovering, animated: true)
        }

        applyAppearance()
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
        note.collapsed.toggle()
        var frame = window.frame
        let collapsedHeight = noteView.headerHeight

        if note.collapsed {
            expandedHeight = frame.height
            frame.origin.y += frame.height - collapsedHeight
            frame.size.height = collapsedHeight
        } else {
            let target = max(expandedHeight, 80)
            frame.origin.y -= target - frame.height
            frame.size.height = target
        }

        noteView.scrollView.isHidden = note.collapsed
        window.setFrame(frame, display: true, animate: true)
        saveNow()
        persistLayout()
    }

    // MARK: - Delete

    private func requestDelete() {
        onRequestDelete?(note.id)
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
