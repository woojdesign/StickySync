import SwiftUI
import UIKit
import NotesKit
import WoojTokens

/// Full-screen note editor in the wooj note-detail style + Capture's sticky
/// language: the note's color fills the screen, a Charter `reading` body, a
/// ‹ Notes back + ⋯ menu, and a floating bottom palette dock (color swatches +
/// Aa). Opens with a settle spring; autosaves (debounced).
struct NoteEditorView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var saveTask: Task<Void, Never>?
    @State private var landed = false
    @FocusState private var focused: Bool

    init(note: Note) {
        _note = State(initialValue: note)
    }

    var body: some View {
        ZStack {
            Appearance.background(note.colorToken).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                TextEditor(text: $note.content)
                    .font(Appearance.font(note.fontName, size: CGFloat(note.fontSize)))
                    .foregroundStyle(WoojColor.reading)
                    .lineSpacing(7)
                    .tint(WoojColor.clay)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(.horizontal, WoojSpace.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom) { paletteDock }
        .scaleEffect(landed ? 1 : 0.98)
        .opacity(landed ? 1 : 0)
        .onAppear { withAnimation(WoojMotion.settle.animation) { landed = true } }
        .onChange(of: note.content) { _ in scheduleSave() }
        .onDisappear { saveNow() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { saveNow(); dismiss() } label: {
                HStack(spacing: 1) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium))
                    Text("Notes").font(.system(size: 17))
                }
                .foregroundStyle(WoojColor.clay)
            }
            Spacer()
            HStack(spacing: WoojSpace.lg) {
                ShareLink(item: note.content) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WoojColor.clay)
                }
                Menu {
                    Button { UIPasteboard.general.string = note.content } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        model.delete(note); dismiss()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WoojColor.clay)
                }
            }
        }
        .padding(.horizontal, WoojSpace.md)
        .padding(.top, WoojSpace.sm)
        .padding(.bottom, WoojSpace.xs)
    }

    private var paletteDock: some View {
        HStack(spacing: WoojSpace.sm) {
            ForEach(Palette.colors, id: \.token) { c in
                Circle()
                    .fill(Appearance.background(c.token))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().strokeBorder(
                            note.colorToken == c.token ? WoojColor.clay : WoojColor.line,
                            lineWidth: note.colorToken == c.token ? 2 : 1)
                    )
                    .onTapGesture {
                        note.colorToken = c.token
                        saveNow()
                    }
            }
            Spacer(minLength: WoojSpace.xs)
            fontMenu
        }
        .padding(.horizontal, WoojSpace.md)
        .padding(.vertical, WoojSpace.sm)
        .background(WoojColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(WoojColor.line))
        .shadow(color: WoojColor.ink.opacity(0.10), radius: 12, y: 4)
        .padding(.horizontal, WoojSpace.md)
        .padding(.bottom, WoojSpace.xs)
    }

    private var fontMenu: some View {
        Menu {
            ForEach(FontCatalog.options, id: \.id) { o in
                Button {
                    note.fontName = o.id; saveNow()
                } label: {
                    Label(o.displayName, systemImage: note.fontName == o.id ? "checkmark" : "")
                }
            }
            Divider()
            Button { setSize(-1) } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
            Button { setSize(1) } label: { Label("Larger", systemImage: "textformat.size.larger") }
        } label: {
            Text("Aa")
                .font(.custom(WoojType.reading.family, size: 19))
                .foregroundStyle(WoojColor.ink)
        }
    }

    private func setSize(_ delta: Double) {
        note.fontSize = FontCatalog.clampSize(note.fontSize + delta)
        saveNow()
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
