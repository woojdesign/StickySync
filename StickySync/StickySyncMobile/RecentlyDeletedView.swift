import SwiftUI
import NotesKit
import WoojTokens

/// 0.10.4: iOS parity for Mac's Recently Deleted window. Lists
/// soft-deleted notes with per-row swipe actions (Restore / Delete
/// Permanently) and an Empty Trash button in the toolbar. Same
/// colored-card visual language as the list-mode NotesListView.
struct RecentlyDeletedView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared
    @State private var notes: [Note] = []
    @State private var confirmEmpty = false
    @State private var confirmPermanent: Note?

    var body: some View {
        Group {
            if notes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(notes) { note in
                            row(note)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(WoojColor.ground.ignoresSafeArea())
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !notes.isEmpty {
                    Button("Empty") { confirmEmpty = true }
                        .foregroundStyle(WoojColor.clay)
                }
            }
        }
        .confirmationDialog("Empty Recently Deleted?",
                            isPresented: $confirmEmpty,
                            titleVisibility: .visible) {
            Button("Empty Trash (\(notes.count))", role: .destructive) {
                emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These notes will be permanently deleted from all your devices. This can't be undone.")
        }
        .confirmationDialog("Delete permanently?",
                            isPresented: Binding(
                                get: { confirmPermanent != nil },
                                set: { if !$0 { confirmPermanent = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                if let n = confirmPermanent { permanentlyDelete(n) }
                confirmPermanent = nil
            }
            Button("Cancel", role: .cancel) { confirmPermanent = nil }
        } message: {
            Text("This can't be undone.")
        }
        .task { reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 40))
                .foregroundStyle(WoojColor.tertiary)
            Text("Nothing recently deleted.")
                .foregroundStyle(WoojColor.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoojColor.ground.ignoresSafeArea())
    }

    /// Same colored-card row as NotesListView's list mode, with a
    /// small "Deleted N days ago" footer instead of the standard
    /// modified-time footer.
    private func row(_ note: Note) -> some View {
        let textColor = Appearance.text(note.colorToken)
        return VStack(alignment: .leading, spacing: 4) {
            Text(NotePreviewText.title(for: note))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
            let snippet = NotePreviewText.snippet2(for: note)
            if !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor.opacity(0.75))
                    .lineLimit(1)
            }
            Text(relativeDeleted(note.deletedAt))
                .font(.system(size: 11))
                .foregroundStyle(textColor.opacity(0.6))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Appearance.background(note.colorToken),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .swipeActions(edge: .leading) {
            Button {
                restore(note)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(WoojColor.clay)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                confirmPermanent = note
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        }
    }

    private func relativeDeleted(_ date: Date?) -> String {
        guard let d = date else { return "Deleted" }
        return "Deleted " + NotePreviewText.relativeTime(for: d)
    }

    private func reload() {
        notes = model.sharedStore.deletedNotes()
    }

    private func restore(_ note: Note) {
        model.sharedStore.restore(id: note.id)
        model.reload()
        reload()
    }

    private func permanentlyDelete(_ note: Note) {
        model.sharedStore.hardDelete(id: note.id)
        reload()
    }

    private func emptyTrash() {
        for note in notes {
            model.sharedStore.hardDelete(id: note.id)
        }
        reload()
    }
}

private extension Color {
    // Placeholder: RecentlyDeletedView uses Appearance colors resolved
    // via NSColor / UIColor bridges from NotesKit. Nothing to add here.
}
