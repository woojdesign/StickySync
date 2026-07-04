import SwiftUI
import UIKit
import NotesKit
import WoojTokens
import OSLog

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
    /// 0.12.15: `/remind` sheet presentation state. `pendingTrigger`
    /// captures the trigger-line range so we can strip it after the
    /// user confirms a time.
    @State private var showRemindSheet: Bool = false
    @State private var pendingTrigger: RemindTrigger.Match?
    @State private var confirmationText: String?
    @State private var confirmationTask: Task<Void, Never>?

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
            // 0.12.15: /remind detection. Mirrors the Mac path in
            // NoteWindowController.textDidChange — same trigger
            // regex, same NL parser fall-through, same strip-line
            // + confirmation flow. Presents a SwiftUI sheet instead
            // of an AppKit popover.
            maybeHandleRemindTrigger()
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
                    SyncLog.gate.info("flush \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
                    applyRemote(pending)
                } else {
                    SyncLog.gate.info("flush \(SyncLog.short(self.note.id), privacy: .public): drop-overtaken, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
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
        .sheet(isPresented: $showRemindSheet) {
            RemindPickerSheet(
                onConfirm: { fireAt in confirmReminder(fireAt: fireAt) },
                onCancel: { pendingTrigger = nil }
            )
        }
        .overlay(alignment: .top) {
            if let text = confirmationText {
                ReminderConfirmationChip(text: text)
                    .padding(.top, WoojSpace.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        // Per-slot ink color — was hardcoded WoojColor.clay. On dark
        // slots (Bold Berry's Burgundy, Sunny Beach's Slate, Earthy
        // Forest's Deep Pine) the brand-clay orange blended into the
        // dark sticky bg and the back / share / ⋯ controls were nearly
        // invisible. Per-slot ink follows the same pattern body text +
        // the captured-saved view already use (0.7.8 / 0.7.10).
        let chromeColor = Appearance.text(note.colorToken)
        return HStack {
            Button { saveNow(); dismiss() } label: {
                HStack(spacing: 1) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium))
                    Text("Notes").font(.system(size: 17))
                }
                .foregroundStyle(chromeColor)
            }
            Spacer()
            HStack(spacing: WoojSpace.lg) {
                ShareLink(item: note.content) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(chromeColor)
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
                        .foregroundStyle(chromeColor)
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
            guard !Task.isCancelled else { return }
            SyncLog.gate.info("save \(SyncLog.short(snapshot.id), privacy: .public): snapshot=\(SyncLog.ts(snapshot.modifiedAt), privacy: .public)")
            model.save(snapshot)
            hasLocalEdits = false
            // Save just landed → local store now matches our editor
            // state. If a remote update was held during typing and is
            // still newer than what we just saved, it's safe to apply
            // now (modifiedAt comparison drops anything stale).
            flushPendingRemoteIfNewer()
        }
    }

    private func saveNow() {
        note.modifiedAt = Date()
        saveTask?.cancel()
        model.save(note)
        hasLocalEdits = false
        flushPendingRemoteIfNewer()
    }

    /// Drop the pending remote if local state has overtaken it; apply
    /// otherwise. Called after every save completes (the other natural
    /// quiescence point besides focus-loss).
    private func flushPendingRemoteIfNewer() {
        guard let pending = pendingRemoteUpdate else { return }
        pendingRemoteUpdate = nil
        if pending.modifiedAt > note.modifiedAt {
            SyncLog.gate.info("post-save \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
            applyRemote(pending)
        } else {
            SyncLog.gate.info("post-save \(SyncLog.short(self.note.id), privacy: .public): drop-overtaken, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) pending=\(SyncLog.ts(pending.modifiedAt), privacy: .public)")
        }
    }

    /// Pull the model's current copy of this note. If it's newer than
    /// what the editor is showing, apply it (no local edits) or stash
    /// it for later (we have local edits worth protecting).
    ///
    /// The gate is `hasLocalEdits` *alone* — NOT `hasLocalEdits && focused`.
    /// The earlier two-part gate had a race:
    ///   1. user types (hasLocalEdits = true, focused = true)
    ///   2. orientation rotates → focused = false (but local edits not saved)
    ///   3. sync delivers a stale remote
    ///   4. with the focus-check, we'd hit the `else` branch and apply,
    ///      wiping the local edits
    /// Local edits are what we're protecting; focus is just *one* signal
    /// the user has paused. We hold-and-flush-on-pause, but we shouldn't
    /// flush just because focus left for an unrelated reason.
    private func refreshFromStoreIfNewer() {
        guard let modelVersion = model.notes.first(where: { $0.id == note.id }) else {
            return
        }
        // No remote-newer signal — nothing to do.
        guard modelVersion.modifiedAt > note.modifiedAt else { return }

        if hasLocalEdits {
            SyncLog.gate.info("refresh \(SyncLog.short(self.note.id), privacy: .public): editing → stash, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) remote=\(SyncLog.ts(modelVersion.modifiedAt), privacy: .public)")
            // Hold off so we don't drop the user's in-flight characters.
            // Flushed when the debounced save completes (saveNow clears
            // hasLocalEdits) or focus leaves the text view, whichever
            // comes first — both gated on `modifiedAt > note.modifiedAt`
            // so a since-overtaken pending is dropped rather than
            // applied.
            pendingRemoteUpdate = modelVersion
        } else {
            SyncLog.gate.info("refresh \(SyncLog.short(self.note.id), privacy: .public): apply, local=\(SyncLog.ts(self.note.modifiedAt), privacy: .public) remote=\(SyncLog.ts(modelVersion.modifiedAt), privacy: .public)")
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

    // MARK: - /remind trigger handling (0.12.15)

    private func maybeHandleRemindTrigger() {
        // Only detect on newly-completed trigger lines, and don't
        // re-detect while the sheet is already up.
        guard !showRemindSheet, pendingTrigger == nil else { return }
        // SwiftUI's TextEditor binding doesn't expose the cursor
        // cheaply; use end-of-content as the cursor. Trigger fires
        // when the user has just typed `/remind …` at the end.
        let cursor = (note.content as NSString).length
        guard let match = RemindTrigger.detect(in: note.content, at: cursor) else { return }

        // NL parser first: `/remind tomorrow 9am` skips the sheet.
        if let parsed = RemindNLParser.parse(match.freeText, now: Date()) {
            pendingTrigger = match
            confirmReminder(fireAt: parsed)
        } else {
            pendingTrigger = match
            showRemindSheet = true
        }
    }

    private func confirmReminder(fireAt: Date) {
        guard let match = pendingTrigger else { return }
        // Strip the /remind line from the content.
        let ns = note.content as NSString
        let stripped = ns.replacingCharacters(in: match.lineRangeToStrip, with: "")
        note.content = stripped
        note.modifiedAt = Date()
        scheduleSave()

        // Persist the reminder + schedule the notification.
        let reminder = Reminder(id: UUID(), noteID: note.id, fireAt: fireAt,
                                 isUrgent: false, firedAt: nil)
        ReminderStoreProvider.shared.set(reminder)

        // Ask for permission on first schedule; schedule regardless
        // — a denied auth still leaves the reminder in the store, so
        // Phase B (cross-device sync) picks it up on the Mac.
        let previewNote = note
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    scheduleUN(reminder: reminder, notePreview: previewNote.content)
                }
            } else {
                scheduleUN(reminder: reminder, notePreview: previewNote.content)
            }
        }

        // Confirmation chip
        confirmationText = "Reminder set · \(formatFireAt(fireAt))"
        confirmationTask?.cancel()
        confirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { confirmationText = nil }
        }

        pendingTrigger = nil
    }

    private func formatFireAt(_ date: Date) -> String {
        let df = DateFormatter()
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: Date()) {
            df.dateFormat = "'today at' h:mm a"
        } else if cal.isDateInTomorrow(date) {
            df.dateFormat = "'tomorrow at' h:mm a"
        } else {
            df.dateFormat = "EEE, MMM d 'at' h:mm a"
        }
        return df.string(from: date)
    }
}

// Free helper — keeps notifier calls out of the main body.
@MainActor private func scheduleUN(reminder: Reminder, notePreview: String) {
    let content = UNMutableNotificationContent()
    content.title = "StickySync reminder"
    content.body = ReminderNotifier.previewBody(from: notePreview)
    content.sound = .default
    let comps = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute], from: reminder.fireAt)
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    let request = UNNotificationRequest(
        identifier: reminder.id.uuidString,
        content: content,
        trigger: trigger)
    UNUserNotificationCenter.current().add(request) { _ in }
}

/// Simple toast chip. Mirrors Mac ReminderConfirmationChip.
struct ReminderConfirmationChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(WoojColor.line))
            .shadow(color: WoojColor.ink.opacity(0.15), radius: 8, y: 2)
    }
}
