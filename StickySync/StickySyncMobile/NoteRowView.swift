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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Swatch — 22pt rounded rect, theme-resolved.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Appearance.background(note.colorToken))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(NotePreviewText.title(for: note))
                    .font(.custom(WoojType.reading.family, size: 17).weight(.semibold))
                    .foregroundStyle(WoojColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                let snip = NotePreviewText.snippet(for: note)
                if !snip.isEmpty {
                    Text(snip)
                        .font(.system(size: 13))
                        .foregroundStyle(WoojColor.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Meta column — date on top, shared/attachment icons below.
            VStack(alignment: .trailing, spacing: 4) {
                Text(NotePreviewText.relativeTime(for: note.modifiedAt))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(WoojColor.tertiary)
                HStack(spacing: 6) {
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WoojColor.clay)
                            .accessibilityLabel("Shared note")
                    }
                    if NotePreviewText.hasAttachmentReference(note) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(WoojColor.tertiary)
                            .accessibilityLabel("Has attachment")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
