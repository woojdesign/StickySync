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
    /// Observed so the editor background, palette dock swatches, and the
    /// MarkdownTextView reactor (via the `theme.current.id` change-key)
    /// re-render when the user picks a new theme on this device or the
    /// other one syncs in.
    @ObservedObject private var theme = ThemeStore.shared
    @State private var note: Note
    @State private var saveTask: Task<Void, Never>?
    @State private var landed = false
    @State private var focused: Bool = false
    @State private var showShareSheet = false
    /// A remote update (CloudKit import, MCP write from another device)
    /// that arrived while the user was typing. We don't apply it
    /// immediately — that would yank the cursor — but we don't drop it
    /// either (the previous silent-drop behavior is what caused the
    /// "Mac MCP edit lost on iOS" reports). Applied when the user pauses
    /// typing (focus leaves the text view).
    @State private var pendingRemoteUpdate: Note?
    /// True once the user has typed in this editor session. Lets us
    /// distinguish "no local changes worth keeping, just refresh to
    /// remote" from "user has typed, be careful with their edits."
    @State private var hasLocalEdits: Bool = false

    init(note: Note) {
        _note = State(initialValue: note)
    }

    var body: some View {
        ZStack {
            Appearance.background(note.colorToken).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                MarkdownTextView(
                    text: $note.content,
                    isFocused: $focused,
                    font: Appearance.uiFont(note.fontName, size: CGFloat(note.fontSize)),
                    // Per-slot text color (resolved through the current theme)
                    // so a saturated theme can ride white-on-punch, etc.
                    textColor: Appearance.uiText(note.colorToken),
                    tintColor: UIColor(WoojColor.clay),
                    noteID: note.id,
                    noteStore: model.sharedStore as AnyObject
                )
                .padding(.horizontal, WoojSpace.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom) { paletteDock }
        .scaleEffect(landed ? 1 : 0.98)
        .opacity(landed ? 1 : 0)
        .onAppear {
            withAnimation(WoojMotion.settle.animation) { landed = true }
            // Take the store's current view of the note as our starting
            // point — model.notes may have refreshed via sync between the
            // list-view tap and this editor materializing.
            refreshFromStoreIfNewer()
        }
        .onChange(of: note.content) { _ in
            hasLocalEdits = true
            // Bump modifiedAt synchronously per keystroke so the LWW
            // gate in the pending-remote flush sees our local state as
            // newer immediately — not 400ms later when the debounced
            // save fires. Without this, a stale-remote refresh arriving
            // during the debounce window passes the "is remote newer?"
            // check and wipes the in-flight paste/typing.
            note.modifiedAt = Date()
            scheduleSave()
        }
        .onChange(of: model.notes) { _ in
            // Sync brought in a newer version. Apply it if we don't have
            // unsaved local edits OR if the user isn't actively typing
            // (focus left the text view). Otherwise stash it and apply
            // when focus leaves.
            refreshFromStoreIfNewer()
        }
        .onChange(of: focused) { isFocused in
            // Focus left the text view — the user has paused. Apply any
            // pending remote update we held back during typing — but
            // *only* if it's still newer than our current local state.
            // The dabi paste-image-loss shape: pasted image at T0,
            // stale-remote refresh arrived at T0+200ms and was held
            // during typing, then flushed on focus-loss — wiping the
            // paste. Now we drop the stale pending and let the next
            // save push our newer state to CloudKit.
            if !isFocused, let pending = pendingRemoteUpdate {
                pendingRemoteUpdate = nil
                if pending.modifiedAt > note.modifiedAt {
                    applyRemote(pending)
                }
            }
        }
        .onDisappear { saveNow() }
        .sheet(isPresented: $showShareSheet) {
            CloudShareSheet(note: note) { _ in
                // Refresh so the shared-state indicator updates on the list.
                model.reload()
            }
        }
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
                    Button { showShareSheet = true } label: {
                        Label("Share with someone…", systemImage: "person.badge.plus")
                    }
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
        hasLocalEdits = false
    }

    /// Pull the model's current copy of this note. If it's newer than
    /// what the editor is showing, either apply it (no local edits or
    /// no focus) or stash it for later (user is typing).
    private func refreshFromStoreIfNewer() {
        guard let modelVersion = model.notes.first(where: { $0.id == note.id }) else {
            return
        }
        // No remote-newer signal — nothing to do.
        guard modelVersion.modifiedAt > note.modifiedAt else { return }

        if hasLocalEdits && focused {
            // Mid-typing: hold off so we don't yank the cursor or drop the
            // user's in-flight characters. Apply when focus leaves.
            pendingRemoteUpdate = modelVersion
        } else {
            applyRemote(modelVersion)
        }
    }

    private func applyRemote(_ remote: Note) {
        // Replace local working copy with the remote. Bail-out path for
        // the field-merge cases (e.g., user only changed colorToken, remote
        // only changed content) would go here in a future revision; for
        // now we take the remote whole-note because LWW with the
        // hasLocalEdits guard already handles the bulk of cases without
        // the merge-complexity tax.
        note = remote
        hasLocalEdits = false
    }
}
