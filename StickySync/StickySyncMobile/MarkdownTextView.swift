// MarkdownTextView.swift
//
// SwiftUI wrapper around a UITextView backed by `MarkdownTextStorage`. The
// underlying string is plain Markdown — exactly what NotesKit stores and
// CloudKit ships — but the on-screen text shows live bold / italic / strike /
// heading / list / link styling. Replaces the previous `TextEditor(text:)`
// in NoteEditorView.
//
// Hardware keyboard shortcuts (⌘B/⌘I/⌘⇧X/⌘K) work via UIKeyCommand on the
// inner UITextView subclass; the on-screen iOS keyboard doesn't expose them,
// which is fine — Markdown remains optional ("shouldn't be necessary").

import SwiftUI
import UIKit
import NotesKit

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: UIFont
    let textColor: UIColor
    let tintColor: UIColor
    /// The note this editor is bound to — needed by the paste handler so
    /// uploaded attachments land on the right record, and by the loader so
    /// inline image references resolve. Pasting is a no-op while nil
    /// (e.g. preview rendering).
    var noteID: UUID? = nil
    /// The store the paste handler writes uploads through, and that the
    /// storage's `attachmentLoader` resolves UUIDs against. Held weakly to
    /// avoid retain cycles in the editor view hierarchy.
    weak var noteStore: AnyObject? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, noteID: noteID, noteStore: noteStore as? NoteStore)
    }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownTextStorage(
            baseFont: font,
            textColor: textColor,
            markerColor: textColor.markerVariant()
        )
        // Bridge the storage into NotesKit so inline `attachment://UUID`
        // refs hydrate to real UIImages without the storage importing
        // NotesKit directly.
        let storeRef = noteStore as? NoteStore
        storage.attachmentLoader = { [weak storeRef] uuid in
            guard let data = storeRef?.imageData(for: uuid) else { return nil }
            return UIImage(data: data)
        }

        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let tv = MarkdownUITextView(frame: .zero, textContainer: container)
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.tintColor = tintColor
        tv.font = font
        tv.textColor = textColor
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        tv.adjustsFontForContentSizeCategory = false
        tv.attachmentContext = .init(noteID: noteID, noteStore: noteStore as? NoteStore) {
            // After a paste that mutated the storage directly, push the
            // expanded (Markdown) form back to the binding so what NotesKit
            // saves is the portable form, not the FFFC-substituted backing.
            context.coordinator.syncBindingFromStorage()
        }

        // Seed initial content through the storage so processEditing runs and
        // styling is applied immediately, then substitute any existing
        // `![](attachment://UUID)` references in the loaded note.
        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
            storage.substituteAttachmentReferences()
        }

        context.coordinator.storage = storage
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = context.coordinator.storage else { return }

        // Keep the coordinator's attachment-context in sync with whatever
        // the parent passes — e.g. the editor view setting `noteID` once
        // it has saved a brand-new note.
        context.coordinator.noteID = noteID
        if let updated = noteStore as? NoteStore {
            context.coordinator.noteStore = updated
        }
        if let tv = uiView as? MarkdownUITextView {
            tv.attachmentContext = .init(noteID: noteID, noteStore: noteStore as? NoteStore) {
                context.coordinator.syncBindingFromStorage()
            }
        }

        // Outside binding changed (e.g. switching notes) — sync into storage.
        // Compare against `sourceString` (the expanded form) so the FFFC-vs-
        // Markdown difference doesn't trigger an infinite re-load loop.
        if storage.sourceString != text {
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: text)
            storage.substituteAttachmentReferences()
        }

        // Pick up font / color changes (color-token swatch tap, font menu).
        if !storage.baseFont.isEqual(font) {
            storage.baseFont = font
        }
        if !storage.textColor.isEqual(textColor) {
            storage.textColor = textColor
            storage.markerColor = textColor.markerVariant()
        }
        if uiView.tintColor != tintColor {
            uiView.tintColor = tintColor
        }

        // Sync SwiftUI-driven focus changes (e.g. keyboard "Done" button).
        DispatchQueue.main.async {
            if isFocused, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isFocused, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        weak var storage: MarkdownTextStorage?
        weak var textView: UITextView?
        var noteID: UUID?
        weak var noteStore: AnyObject?

        init(text: Binding<String>, isFocused: Binding<Bool>, noteID: UUID?, noteStore: NoteStore?) {
            self._text = text
            self._isFocused = isFocused
            self.noteID = noteID
            self.noteStore = noteStore
        }

        /// Push the storage's expanded Markdown form back to the binding.
        /// Used after edits that mutate the storage outside of the normal
        /// typing flow (paste handler, attachment substitution).
        func syncBindingFromStorage() {
            guard let storage else { return }
            let source = storage.sourceString
            if text != source { text = source }
        }

        func textViewDidChange(_ textView: UITextView) {
            // Expand `[]` / `[ ]` at line start into the canonical
            // `- [ ] ` before syncing the SwiftUI binding. Keeps the
            // underlying file format portable Markdown.
            if let exp = MarkdownEditing.checkboxAutoExpansion(in: textView.textStorage,
                                                               at: textView.selectedRange.location) {
                MarkdownEditing.applyCheckboxAutoExpansion(exp, in: textView.textStorage)
                textView.selectedRange = NSRange(location: exp.newCursor, length: 0)
            }
            // The storage is the source of truth, but it may contain FFFC
            // attachment placeholders — push the *expanded* Markdown back to
            // the binding so NotesKit persists the portable form.
            if let storage = textView.textStorage as? MarkdownTextStorage {
                let source = storage.sourceString
                if text != source { text = source }
            } else {
                let s = textView.text ?? ""
                if text != s { text = s }
            }
            refreshActiveMarkerRange(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused { isFocused = true }
            refreshActiveMarkerRange(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFocused { isFocused = false }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            refreshActiveMarkerRange(in: textView)
        }

        private func refreshActiveMarkerRange(in textView: UITextView) {
            guard let storage = textView.textStorage as? MarkdownTextStorage else { return }
            let ns = (textView.text ?? "") as NSString
            guard ns.length > 0 else { return }
            let selected = textView.selectedRange
            let paragraph = ns.paragraphRange(for: NSRange(location: selected.location, length: 0))
            let active = NSUnionRange(paragraph, selected)
            storage.setActiveLineRange(active)
        }

        /// Auto-continue list items on Enter, mirroring the Mac behavior.
        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            guard let storage = textView.textStorage as? MarkdownTextStorage else { return true }
            guard let action = MarkdownEditing.newlineAction(in: storage, at: range.location) else {
                return true
            }
            switch action {
            case .cancelPrefix(let removeRange):
                storage.replaceCharacters(in: removeRange, with: "")
                textView.selectedRange = NSRange(location: removeRange.location, length: 0)
            case .insertString(let s):
                storage.replaceCharacters(in: range, with: s)
                textView.selectedRange = NSRange(location: range.location + (s as NSString).length, length: 0)
            }
            // We mutated the storage directly, so SwiftUI binding needs an
            // explicit sync.
            let str = textView.text ?? ""
            if self.text != str { self.text = str }
            return false
        }
    }
}

/// UITextView subclass that surfaces ⌘B/⌘I/⌘⇧X/⌘K to hardware keyboards and
/// adds a tap recognizer that toggles checkbox state when the user taps a
/// `[ ]` / `[x]` slot directly.
///
/// Also intercepts paste to route image bytes through NotesKit → CDAttachment
/// instead of into the text view as a system attachment we'd then have to
/// chase to sync to CloudKit.
final class MarkdownUITextView: UITextView {

    /// Set by `MarkdownTextView.updateUIView` so paste knows which note to
    /// upload into. Closure fires after a successful paste so the SwiftUI
    /// binding picks up the new Markdown reference.
    struct AttachmentContext {
        let noteID: UUID?
        let noteStore: NoteStore?
        let onPasted: () -> Void
    }
    var attachmentContext: AttachmentContext?

    private lazy var checkboxTap: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
        g.cancelsTouchesInView = false  // let UITextView's own recognizers run too
        g.delegate = self
        return g
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addGestureRecognizer(checkboxTap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(checkboxTap)
    }

    // MARK: - Paste

    /// Tell UIKit's edit-menu / long-press-menu validator that we can
    /// consume an image-only pasteboard. Without this, when the user
    /// taps Copy on a photo and long-presses our text field, only
    /// "AutoFill" shows — no Paste — and our `paste(_:)` override
    /// never even gets called.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)),
           attachmentContext?.noteID != nil,
           attachmentContext?.noteStore != nil,
           UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Paste intercept. When the pasteboard carries an image, upload the
    /// bytes through NotesKit and insert a Markdown reference at the cursor.
    /// Anything else (text, URLs, …) falls through to the default behavior.
    override func paste(_ sender: Any?) {
        if let context = attachmentContext,
           let noteID = context.noteID,
           let store = context.noteStore,
           let imageData = bestImageData(from: UIPasteboard.general),
           let image = UIImage(data: imageData.data),
           let attachment = store.addImageAttachment(
                for: noteID,
                imageData: imageData.data,
                mimeType: imageData.mimeType,
                originalFilename: nil,
                altText: nil
           ),
           let storage = textStorage as? MarkdownTextStorage {
            // Insert the FFFC placeholder at the caret, then advance the
            // selection so the next keystroke lands after the image.
            let insertAt = selectedRange.location
            storage.insertAttachment(id: attachment.id,
                                     altText: "",
                                     image: image,
                                     at: insertAt)
            selectedRange = NSRange(location: insertAt + 1, length: 0)
            context.onPasted()
            return
        }
        super.paste(sender)
    }

    /// Read the highest-fidelity image representation off the pasteboard.
    /// Preserves PNG / HEIC originals when present so we don't re-encode and
    /// lose quality.
    private func bestImageData(from pb: UIPasteboard) -> (data: Data, mimeType: String)? {
        if let png = pb.data(forPasteboardType: "public.png") {
            return (png, "image/png")
        }
        if let heic = pb.data(forPasteboardType: "public.heic") {
            return (heic, "image/heic")
        }
        if let jpeg = pb.data(forPasteboardType: "public.jpeg") {
            return (jpeg, "image/jpeg")
        }
        // Fallback: ask UIPasteboard for the synthesized UIImage and re-encode
        // as PNG. Slower path; covers screenshots from older sources.
        if let image = pb.image, let png = image.pngData() {
            return (png, "image/png")
        }
        return nil
    }

    @objc private func handleCheckboxTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: self)
        guard let position = closestPosition(to: point),
              let storage = textStorage as? MarkdownTextStorage else { return }
        let index = offset(from: beginningOfDocument, to: position)
        guard let hit = MarkdownEditing.checkboxHit(in: storage, at: index) else { return }
        MarkdownEditing.applyCheckboxToggle(in: storage, hit: hit)
        // The toggle mutated the storage directly (not via UIKit's input
        // system), so `textViewDidChange` is *not* called. Without an
        // explicit binding sync, `$note.content` stays at the pre-toggle
        // value, the editor's debounced save fires with stale content,
        // and the toggle is lost the moment the user navigates away.
        // syncBindingFromStorage is the existing helper meant for exactly
        // this class of mutation (paste-then-attach uses it too).
        (delegate as? MarkdownTextView.Coordinator)?.syncBindingFromStorage()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(action: #selector(mdBold), input: "b", modifierFlags: .command, discoverabilityTitle: "Bold"),
            UIKeyCommand(action: #selector(mdItalic), input: "i", modifierFlags: .command, discoverabilityTitle: "Italic"),
            UIKeyCommand(action: #selector(mdStrike), input: "x", modifierFlags: [.command, .shift], discoverabilityTitle: "Strikethrough"),
            UIKeyCommand(action: #selector(mdLink), input: "k", modifierFlags: .command, discoverabilityTitle: "Link"),
        ]
    }

    @objc private func mdBold() {
        guard let st = textStorage as? MarkdownTextStorage else { return }
        selectedRange = MarkdownEditing.toggleBold(in: st, range: selectedRange)
    }

    @objc private func mdItalic() {
        guard let st = textStorage as? MarkdownTextStorage else { return }
        selectedRange = MarkdownEditing.toggleItalic(in: st, range: selectedRange)
    }

    @objc private func mdStrike() {
        guard let st = textStorage as? MarkdownTextStorage else { return }
        selectedRange = MarkdownEditing.toggleStrikethrough(in: st, range: selectedRange)
    }

    @objc private func mdLink() {
        guard let st = textStorage as? MarkdownTextStorage else { return }
        selectedRange = MarkdownEditing.insertLink(in: st, range: selectedRange)
    }
}

extension MarkdownUITextView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Coexist with UITextView's built-in selection/cursor recognizers so
        // our checkbox tap runs without blocking normal interaction.
        return true
    }
}
