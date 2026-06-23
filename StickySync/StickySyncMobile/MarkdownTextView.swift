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
        let layoutManager = NSLayoutManager()
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
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused { isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFocused { isFocused = false }
        }
    }
}

/// UITextView subclass that surfaces ⌘B/⌘I/⌘⇧X/⌘K to hardware keyboards.
final class MarkdownUITextView: UITextView {
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
