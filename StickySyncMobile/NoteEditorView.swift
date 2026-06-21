import SwiftUI
import NotesKit

/// Full-screen editor for one note: a colored text area plus color and font
/// controls in the toolbar. Edits autosave (debounced) to the shared store,
/// so they sync out the same way the Mac app's do.
struct NoteEditorView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var saveTask: Task<Void, Never>?

    init(note: Note) {
        _note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $note.content)
                .font(Appearance.font(note.fontName, size: CGFloat(note.fontSize)))
                .foregroundStyle(Appearance.text(note.colorToken))
                .scrollContentBackground(.hidden)
                .background(Appearance.background(note.colorToken))
                .padding(.horizontal, 6)
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: note.content) { _ in scheduleSave() }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { saveNow(); dismiss() }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        colorMenu
                        fontMenu
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var colorMenu: some View {
        Menu {
            ForEach(Palette.colors, id: \.token) { color in
                Button {
                    note.colorToken = color.token
                    saveNow()
                } label: {
                    Label(color.displayName,
                          systemImage: note.colorToken == color.token ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .accessibilityLabel("Change color")
    }

    private var fontMenu: some View {
        Menu {
            ForEach(FontCatalog.options, id: \.id) { option in
                Button {
                    note.fontName = option.id
                    saveNow()
                } label: {
                    Label(option.displayName,
                          systemImage: note.fontName == option.id ? "checkmark" : "textformat")
                }
            }
            Divider()
            Button {
                note.fontSize = FontCatalog.clampSize(note.fontSize - 1)
                saveNow()
            } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
            Button {
                note.fontSize = FontCatalog.clampSize(note.fontSize + 1)
                saveNow()
            } label: { Label("Larger", systemImage: "textformat.size.larger") }
        } label: {
            Image(systemName: "textformat")
        }
        .accessibilityLabel("Change font")
    }

    private func scheduleSave() {
        note.modifiedAt = Date()
        saveTask?.cancel()
        let snapshot = note
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled { model.save(snapshot) }
        }
    }

    private func saveNow() {
        note.modifiedAt = Date()
        saveTask?.cancel()
        model.save(note)
    }
}
