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

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: UIFont
    let textColor: UIColor
    let tintColor: UIColor

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: $isFocused) }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownTextStorage(
            baseFont: font,
            textColor: textColor,
            markerColor: textColor.markerVariant()
        )
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

        // Seed initial content through the storage so processEditing runs and
        // styling is applied immediately.
        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }

        context.coordinator.storage = storage
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = context.coordinator.storage else { return }

        // Outside binding changed (e.g. switching notes) — sync into storage.
        if storage.string != text {
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: text)
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

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self._text = text
            self._isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            // The storage is the source of truth for the underlying plain
            // text; SwiftUI binding receives only the raw string.
            let s = textView.text ?? ""
            if text != s { text = s }
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
final class MarkdownUITextView: UITextView {

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

    @objc private func handleCheckboxTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: self)
        guard let position = closestPosition(to: point),
              let storage = textStorage as? MarkdownTextStorage else { return }
        let index = offset(from: beginningOfDocument, to: position)
        guard let hit = MarkdownEditing.checkboxHit(in: storage, at: index) else { return }
        MarkdownEditing.applyCheckboxToggle(in: storage, hit: hit)
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
