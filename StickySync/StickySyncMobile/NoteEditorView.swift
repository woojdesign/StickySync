import SwiftUI
import NotesKit

/// Full-screen editor for one note: a colored text area with color, format, and
/// delete controls. Edits autosave (debounced) to the shared store, so they
/// sync out the same way the Mac app's do.
struct NoteEditorView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var saveTask: Task<Void, Never>?
    @State private var showFormat = false
    @State private var confirmDelete = false
    @FocusState private var editing: Bool

    init(note: Note) {
        _note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $note.content)
                .font(Appearance.font(note.fontName, size: CGFloat(note.fontSize)))
                .foregroundStyle(Appearance.text(note.colorToken))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .scrollDismissesKeyboard(.interactively)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .background(Appearance.background(note.colorToken).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Appearance.background(note.colorToken), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .onChange(of: note.content) { scheduleSave() }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { saveNow(); dismiss() }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        colorMenu
                        Button { showFormat = true } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("Text format")
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete note")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { editing = false }
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showFormat) { formatSheet }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                saveTask?.cancel()
                model.delete(note)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from all your devices.")
        }
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

    private var formatSheet: some View {
        NavigationStack {
            Form {
                Section("Font") {
                    Picker("Typeface", selection: fontBinding) {
                        ForEach(FontCatalog.options, id: \.id) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Size") {
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: sizeBinding, in: FontCatalog.minSize...FontCatalog.maxSize, step: 1)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                    }
                    Text("The quick brown fox")
                        .font(Appearance.font(note.fontName, size: CGFloat(note.fontSize)))
                        .foregroundStyle(Appearance.text(note.colorToken))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Appearance.background(note.colorToken),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFormat = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var fontBinding: Binding<String> {
        Binding(get: { note.fontName }, set: { note.fontName = $0; saveNow() })
    }

    private var sizeBinding: Binding<Double> {
        // Debounced — the slider fires continuously while dragging.
        Binding(get: { note.fontSize }, set: { note.fontSize = FontCatalog.clampSize($0); scheduleSave() })
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
