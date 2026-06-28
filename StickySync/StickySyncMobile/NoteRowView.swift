// NoteRowView.swift
//
// Compact single-row SwiftUI rendering of a note for the iOS list-view
// mode (the alternate to the existing card grid). Carries the same data
// shape as the Mac all-notes row — swatch, title (semibold), snippet,
// modified time, shared/attachment indicators — so the two platforms
// stay visually consistent when a user toggles between them.
//
// Cards stay the default per Sean's design call (lower-churn for
// existing users). List mode is opt-in via the header toggle and
// persisted in @AppStorage so the choice survives a relaunch.

import SwiftUI
import UIKit
import NotesKit
import WoojTokens

struct NoteRowView: View {
    let note: Note
    var isShared: Bool = false
    /// SwiftUI skips re-running body when a struct's stored props are
    /// unchanged. `note` doesn't change on a theme switch — only the
    /// resolution of its `colorToken` does — so the row has to observe
    /// the theme directly. NoteCard (grid mode) had this from the
    /// start; the list-mode rows added in 0.7.19/0.7.20 were missing
    /// it, which manifested as Sean's 0.7.32 sticky: "On iOS themes
    /// only apply after restart." (Cards updated; rows didn't.)
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        // Per-slot text color so dark slots (Bold Berry's Burgundy,
        // Sunny Beach's Slate, etc.) stay legible. Same per-slot pattern
        // as NoteCard + the editor — keeps the family consistent.
        let textColor = Appearance.text(note.colorToken)

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NotePreviewText.title(for: note))
                    .font(.custom(WoojType.reading.family, size: 17).weight(.semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                let snip = NotePreviewText.snippet2(for: note)
                if !snip.isEmpty {
                    Text(snip)
                        .font(.custom(WoojType.reading.family, size: 14))
                        .foregroundStyle(textColor.opacity(0.7))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Meta column — date on top, shared/attachment icons below.
            VStack(alignment: .trailing, spacing: 6) {
                Text(NotePreviewText.relativeTime(for: note.modifiedAt))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.6))
                HStack(spacing: 6) {
                    if isShared {
                        // Shared indicator stays brand-clay (identity, not
                        // text) so it pops the same on every theme.
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WoojColor.clay)
                            .accessibilityLabel("Shared note")
                    }
                    if NotePreviewText.hasAttachmentReference(note) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(textColor.opacity(0.7))
                            .accessibilityLabel("Has attachment")
                    }
                }
            }
        }
        .padding(.horizontal, WoojSpace.md)
        .padding(.vertical, WoojSpace.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The row IS a card now — painted in the note's own sticky color.
        // Sean's design call: "list items as cards in the color of their
        // sticky." Drops the separate swatch chip; the whole row is the
        // swatch.
        .background(
            Appearance.background(note.colorToken),
            in: RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous)
                .strokeBorder(WoojColor.clay.opacity(0.35), lineWidth: isShared ? 1 : 0)
        )
        .shadow(color: WoojColor.ink.opacity(0.06), radius: 6, y: 2)
        .contentShape(Rectangle())
    }
}
