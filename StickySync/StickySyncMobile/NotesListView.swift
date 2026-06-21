import SwiftUI
import NotesKit

/// Root screen: a grid of colored note cards. Tap to edit, long-press to
/// delete, compose button to add. (iOS has no floating windows, so notes live
/// in a list + full-screen editor rather than the Mac's draggable stickies.)
struct NotesListView: View {
    @EnvironmentObject private var model: NotesModel
    @State private var editing: Note?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.notes) { note in
                        NoteCard(note: note)
                            .onTapGesture { editing = note }
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.delete(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(16)
            }
            // Ground fills the scroll area. Inline title (below) lives on the nav
            // bar, not in the scroll content, so this fill can't paint over it.
            .background(WoojColor.ground.ignoresSafeArea())
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WoojColor.ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = model.newNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New note")
                }
            }
            .overlay {
                if model.notes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No notes yet").foregroundStyle(.secondary)
                        Text("Tap the compose button to add one.")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .tint(WoojColor.clay)
        .sheet(item: $editing) { note in
            NoteEditorView(note: note)
                .environmentObject(model)
        }
    }
}

private struct NoteCard: View {
    let note: Note

    var body: some View {
        Text(note.content.isEmpty ? "New note" : note.content)
            .font(Appearance.font(note.fontName, size: 15))
            .foregroundStyle(Appearance.text(note.colorToken))
            .lineLimit(7)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(12)
            .background(Appearance.background(note.colorToken))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WoojColor.line, lineWidth: 1))
    }
}
