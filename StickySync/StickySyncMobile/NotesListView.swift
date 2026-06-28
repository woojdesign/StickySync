import SwiftUI
import UIKit
import NotesKit
import WoojTokens

/// Root screen, styled to the wooj index mockup: a serif "Notes" header + count,
/// a search field, and a grid of note cards (title + time footer) on the warm
/// ground, with a bottom capture bar. Presentation only — no model change.
/// (Voice capture, and the pushed editor + bottom palette dock, are deferred.)
struct NotesListView: View {
    @EnvironmentObject private var model: NotesModel
    @StateObject private var sync = SyncMonitor()
    /// Observed so a theme switch (local or iCloud-arrival) re-renders the
    /// grid with the new palette. The store itself is read-only here; the
    /// header's palette button is what flips it.
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editing: Note?
    @State private var search = ""
    @State private var capturing = false
    @State private var reportingSync = false

    private var filtered: [Note] {
        guard !search.isEmpty else { return model.notes }
        return model.notes.filter { $0.content.localizedCaseInsensitiveContains(search) }
    }

    /// Group notes into 2-card rows. We pair manually instead of relying on
    /// LazyVGrid because both `.adaptive` and `.flexible()` were leaving
    /// empty cells next to taller first-row cards on real hardware in
    /// iOS 26 (the simulator showed the correct layout, real devices
    /// didn't). This is what guarantees both columns get filled.
    private var rows: [[Note]] {
        stride(from: 0, to: filtered.count, by: 2).map { idx in
            Array(filtered[idx..<min(idx + 2, filtered.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SearchField(text: $search)
                        .padding(.horizontal, 16)

                    if filtered.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(rows.indices, id: \.self) { rowIndex in
                                let row = rows[rowIndex]
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(row) { note in
                                        cardWithGestures(note)
                                            .frame(maxWidth: .infinity)
                                    }
                                    if row.count == 1 {
                                        // Odd-final-row filler — preserves the
                                        // half-width sizing without leaving an
                                        // empty column elsewhere.
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(WoojColor.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { captureBar }
        }
        .tint(WoojColor.clay)
        .fullScreenCover(item: $editing) { note in
            NoteEditorView(note: note)
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $capturing) {
            CaptureSheet(store: model.sharedStore)
        }
        .sheet(isPresented: $reportingSync) {
            SyncReportComposerView(currentSyncState: syncStateString(sync.state))
        }
        .onReceive(NotificationCenter.default.publisher(for: .startCapture)) { _ in
            // If the editor is already presented as a fullScreenCover, raising
            // the capture cover does nothing — SwiftUI shows one cover at a
            // time. Dismiss the editor first, then raise capture on the next
            // runloop tick so the dismiss animation can hand off cleanly.
            if editing != nil {
                editing = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    capturing = true
                }
            } else {
                capturing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptSharedNote)) { note in
            // Reload the list so the new shared note is in `model.notes`,
            // then route straight into the editor for it. The user just
            // tapped the share link in Messages; landing them on the note
            // itself (not the list) is the deliberate arrival moment.
            if let arrived = note.object as? Note {
                model.reload()
                editing = arrived
            }
        }
        .onAppear {
            // Cold launch via the Capture intent: the .startCapture post may have
            // fired before this view was listening, so consume the flag too.
            if CaptureLauncher.pending {
                CaptureLauncher.pending = false
                capturing = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                // Charter stands in for the wooj display face (Fraunces) until the
                // custom faces are bundled; it renders as a real serif today.
                Text("Notes")
                    .font(.custom(WoojType.reading.family, size: 34).weight(.semibold))
                    .foregroundStyle(WoojColor.ink)
                HStack(spacing: 6) {
                    Text("^[\(model.notes.count) note](inflect: true)")
                    // Only surface the sync line when there's something to
                    // say. `.harmony` is the silent-success state; rendering
                    // "Synced" was overstating what we can actually verify.
                    if sync.state != .harmony {
                        Text("·")
                        // Tap the non-harmony line → open the Tier 1 report
                        // composer. This is the always-on path; future
                        // Phase 2.d will add per-state deep-links to System
                        // Settings (network → "go online", account → "sign
                        // in", quota → "manage storage"). Reporting is the
                        // fallback when none of those fix the underlying
                        // issue.
                        syncStatus
                            .onTapGesture { reportingSync = true }
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(WoojColor.tertiary)
                .animation(WoojMotion.calm.animation, value: sync.state)
            }
            Spacer(minLength: 12)
            themePicker
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Compact swatch trio that opens a Menu of available themes. Lives in the
    /// header rather than a Settings screen because theme is the one app-wide
    /// preference, and the visual swatches read instantly as "pick a vibe."
    private var themePicker: some View {
        Menu {
            ForEach(Themes.all) { t in
                Button {
                    withAnimation(WoojMotion.calm.animation) {
                        ThemeStore.shared.select(t.id)
                    }
                } label: {
                    // SwiftUI's Menu Button label supports a custom icon
                    // via Label(title:icon:). The swatch strip turns the
                    // 15-item list into a glanceable visual menu — name
                    // + checkmark are still rendered by SwiftUI alongside.
                    Label {
                        if t.id == theme.current.id {
                            Label(t.displayName, systemImage: "checkmark")
                        } else {
                            Text(t.displayName)
                        }
                    } icon: {
                        Image(uiImage: Appearance.themeSwatchImage(for: t))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                ForEach(themeSwatchSlots, id: \.self) { slot in
                    Circle()
                        .fill(Appearance.background(slot))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(WoojColor.line.opacity(0.4), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(WoojColor.surface)
            )
            .overlay(
                Capsule().stroke(WoojColor.line, lineWidth: 0.5)
            )
        }
        .accessibilityLabel("Theme: \(theme.current.displayName)")
    }

    /// The three swatches shown in the header chip — slots 1, 4, 6 give a
    /// reasonable cross-section of warm / cool / green of any theme.
    private let themeSwatchSlots = ["1", "4", "6"]

    /// Calm CloudKit sync state, so an eventual-consistency delay reads as
    /// "Syncing…" rather than "my note didn't save."
    /// One card with its tap target + context menu attached. Extracted from
    /// the row loop so the body stays scannable.
    @ViewBuilder private func cardWithGestures(_ note: Note) -> some View {
        NoteCard(note: note,
                 isShared: model.sharedNoteIDs.contains(note.id),
                 store: model.sharedStore,
                 dataTick: model.dataTick)
            .onTapGesture { editing = note }
            .contextMenu {
                Button { UIPasteboard.general.string = note.content } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                ShareLink(item: note.content) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    model.delete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    /// Stringify the SyncMonitor state for the report header. Stable
    /// short strings so the recipient (Sean) can grep across reports.
    private func syncStateString(_ state: SyncMonitor.State) -> String {
        switch state {
        case .harmony:           return "harmony"
        case .syncing:           return "syncing"
        case .offline:           return "offline"
        case .error(let kind):   return "error.\(kind.rawValue)"
        }
    }

    /// The non-harmony copy. Cause + fix in the same sentence; word is
    /// "Couldn't sync" not "Sync error" (round-2 research convention).
    @ViewBuilder private var syncStatus: some View {
        switch sync.state {
        case .harmony:
            EmptyView()
        case .syncing:
            HStack(spacing: 4) { Image(systemName: "arrow.triangle.2.circlepath"); Text("Syncing…") }
        case .offline:
            HStack(spacing: 4) { Image(systemName: "cloud.slash"); Text("Offline — changes will sync when you're back") }
        case .error(.account):
            HStack(spacing: 4) { Image(systemName: "person.crop.circle.badge.exclamationmark"); Text("Sign in to iCloud to keep notes in sync") }
        case .error(.quota):
            HStack(spacing: 4) { Image(systemName: "externaldrive.badge.exclamationmark"); Text("iCloud storage is full") }
        case .error(.network):
            HStack(spacing: 4) { Image(systemName: "cloud.slash"); Text("Offline — changes will sync when you're back") }
        case .error(.unknown):
            HStack(spacing: 4) { Image(systemName: "exclamationmark.icloud"); Text("Couldn't sync — will retry") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "note.text" : "magnifyingglass")
                .font(.largeTitle).foregroundStyle(WoojColor.tertiary)
            Text(search.isEmpty ? "No notes yet" : "No matches")
                .foregroundStyle(WoojColor.secondary)
            if search.isEmpty {
                Text("Tap “New note” to add one.")
                    .font(.footnote).foregroundStyle(WoojColor.tertiary)
            }
        }
    }

    private var captureBar: some View {
        HStack(spacing: 10) {
            Button {
                editing = model.newNote()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New note")
                    Spacer()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WoojColor.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(WoojColor.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(WoojColor.line))
            }
            Button {
                capturing = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WoojColor.onClay)
                    .frame(width: 52, height: 52)
                    .background(WoojColor.clay, in: Circle())
            }
            .accessibilityLabel("Capture by voice")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(WoojColor.tertiary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(WoojColor.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(WoojColor.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WoojColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoojColor.line))
    }
}

/// Visible to the test target so snapshot baselines can construct it
/// directly. Stays internal to the module otherwise.
struct NoteCard: View {
    let note: Note
    var isShared: Bool = false
    let store: NoteStore
    /// Bumps when CloudKit imports a change of *any* kind — including
    /// attachments arriving for this note after the note itself synced.
    /// `note.modifiedAt` doesn't change in that parent-then-attachment
    /// race, so the cover-lookup `task(id:)` needs another signal to
    /// re-fire. Threaded in from the parent's `model.dataTick` to keep
    /// NoteCard independent of `NotesModel` (the @EnvironmentObject
    /// dependency made the tests non-renderable). Defaults to 0 for
    /// snapshot tests that don't care about late-attachment arrivals.
    var dataTick: UInt64 = 0
    /// SwiftUI skips re-running body when a struct's stored props are
    /// unchanged. `note` doesn't change on a theme switch — only the
    /// resolution of its `colorToken` does — so the card has to observe
    /// the theme directly to know its body should re-run.
    @ObservedObject private var theme = ThemeStore.shared
    /// Pre-resolved first-attachment thumbnail. Loaded on `.task` so the
    /// card body doesn't block on Core Data + thumbnail decode during
    /// each scroll re-layout.
    @State private var thumb: UIImage?
    /// Which attachment is currently rendered into `thumb`. Used to
    /// skip the reassignment when a task re-fire (dataTick bump from
    /// any CloudKit import — fires every few seconds) is just
    /// re-resolving the same attachment. Without this, every
    /// background CloudKit event reassigned `thumb` with a freshly-
    /// decoded UIImage → SwiftUI saw `@State` change → re-rendered
    /// the Image → brief layout shift → visible flicker on
    /// "all notes" cards. (The 0.7.15 "all notes flickers" report.)
    @State private var thumbAttachmentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: WoojSpace.md) {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: WoojRadius.md, style: .continuous))
            }
            // Per-slot text color (resolved through the current theme) so
            // a dark slot — Bold Berry's Burgundy, Sunny Beach's Slate,
            // Earthy Forest's Deep Pine — uses the palette's white-ink
            // pair, not the wooj reading color (which is hardcoded dark).
            // The editor already does this; the card index needs the
            // same treatment for parity and legibility.
            Text(preview)
                .font(.custom(WoojType.reading.family, size: 16))
                .foregroundStyle(Appearance.text(note.colorToken))
                .lineSpacing(3)
                .lineLimit(thumb == nil ? 5 : 3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: WoojSpace.xs)
            HStack(spacing: WoojSpace.xs) {
                Text(Self.relativeTime(note.modifiedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Appearance.text(note.colorToken).opacity(0.6))
                Spacer()
                if isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WoojColor.clay)
                        .accessibilityLabel("Shared note")
                }
            }
        }
        // Re-fire the cover lookup whenever the note's body changes — e.g.
        // the user just pasted an image inside the editor and returned to
        // the list. Keying on `note.id` alone never re-runs, so the card
        // would stay blank until the app relaunched.
        .task(id: "\(note.id)|\(note.modifiedAt.timeIntervalSince1970)|\(note.content.count)|\(dataTick)") {
            // Picks the first non-deleted attachment that's *still
            // referenced* by note.content as a cover. The reference check
            // matters because deleting the `![](attachment://UUID)` text
            // from the editor doesn't soft-delete the underlying
            // CDAttachment — it just orphans it. Without the gate, the
            // card kept showing a thumb for a sticky whose image was
            // deleted ("snapshot retained after delete" bug).
            let attachments = store.attachments(for: note.id)
            let referenced = attachments.first { att in
                guard !att.isDeleted else { return false }
                return note.content.range(
                    of: "attachment://\(att.id.uuidString)",
                    options: .caseInsensitive) != nil
            }
            guard let first = referenced,
                  let data = store.thumbnailData(for: first.id) ?? store.imageData(for: first.id),
                  let img = UIImage(data: data) else {
                if thumb != nil { thumb = nil }
                thumbAttachmentID = nil
                return
            }
            // Only reassign if the resolved attachment is actually
            // different from what we already have rendered. Equivalent
            // task re-fires (same attachment, fresh dataTick) would
            // otherwise build a new UIImage each time and cause SwiftUI
            // to redraw → visible flicker.
            if thumbAttachmentID != first.id {
                thumb = img
                thumbAttachmentID = first.id
            }
        }
        .frame(minHeight: 120, alignment: .topLeading)
        .padding(WoojSpace.md)
        .background(
            Appearance.background(note.colorToken),
            in: RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous)
                .strokeBorder(WoojColor.clay.opacity(0.35), lineWidth: isShared ? 1 : 0)
        )
        .shadow(color: WoojColor.ink.opacity(0.07), radius: 10, y: 5)
    }

    private var preview: String {
        // Strip image references (`![alt](attachment://UUID)`) — the cover
        // thumbnail above already shows the image; the alt text is enough
        // here, the URL is just visual noise.
        let withoutImages = note.content.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(attachment://[^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        let raw = withoutImages.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return thumb == nil ? "New note" : "" }
        var lines: [String] = []
        for rawLine in raw.components(separatedBy: "\n") {
            let line = Self.stripPreviewMarkers(rawLine)
            // Collapse runs of blank lines into a single blank line — the
            // user's intentional paragraph break is preserved, but extra
            // empty lines (common after `# heading` blocks) don't blow up
            // the card height.
            if line.isEmpty {
                if lines.last?.isEmpty != true { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Lightweight Markdown → preview text transform. Doesn't try to be a
    /// full renderer; just removes the noise that makes the cards look
    /// like raw source.
    private static func stripPreviewMarkers(_ raw: String) -> String {
        var s = raw
        // Heading markers — `### `, `## `, `# `.
        if s.hasPrefix("### ") { s.removeFirst(4) }
        else if s.hasPrefix("## ") { s.removeFirst(3) }
        else if s.hasPrefix("# ") { s.removeFirst(2) }
        // Checkbox / list bullets — swap for proper glyphs.
        if s.hasPrefix("- [ ] ") { s = "☐ " + s.dropFirst(6) }
        else if s.hasPrefix("- [x] ") || s.hasPrefix("- [X] ") { s = "☑ " + s.dropFirst(6) }
        else if s.hasPrefix("- ") || s.hasPrefix("* ") { s = "• " + s.dropFirst(2) }
        return s
    }

    private static func relativeTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.dateFormat = "h:mma"; return f.string(from: date).lowercased() }
        if cal.isDateInYesterday(date) { return "yest." }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            f.dateFormat = "EEE"; return f.string(from: date)
        }
        f.dateFormat = "MMM d"; return f.string(from: date)
    }
}

/// Hosts the voice-capture surface for one presentation. Owns the VM via
/// @StateObject (so re-renders don't restart the take) and routes its writes
/// through the app's shared store, so captured notes appear in the list.
private struct CaptureSheet: View {
    @StateObject private var vm: CaptureViewModel
    init(store: NoteStore) {
        _vm = StateObject(wrappedValue: CaptureViewModel(store: store))
    }
    var body: some View { CaptureView(vm: vm) }
}
