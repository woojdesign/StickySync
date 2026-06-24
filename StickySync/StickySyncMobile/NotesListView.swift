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
    @State private var editing: Note?
    @State private var search = ""
    @State private var capturing = false

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
        .onReceive(NotificationCenter.default.publisher(for: .startCapture)) { _ in
            capturing = true
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
        VStack(alignment: .leading, spacing: 2) {
            // Charter stands in for the wooj display face (Fraunces) until the
            // custom faces are bundled; it renders as a real serif today.
            Text("Notes")
                .font(.custom(WoojType.reading.family, size: 34).weight(.semibold))
                .foregroundStyle(WoojColor.ink)
            HStack(spacing: 6) {
                Text("^[\(model.notes.count) note](inflect: true)")
                if sync.state != .idle {
                    Text("·")
                    syncStatus
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(WoojColor.tertiary)
            .animation(WoojMotion.calm.animation, value: sync.state)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Calm CloudKit sync state, so an eventual-consistency delay reads as
    /// "Syncing…" rather than "my note didn't save."
    /// One card with its tap target + context menu attached. Extracted from
    /// the row loop so the body stays scannable.
    @ViewBuilder private func cardWithGestures(_ note: Note) -> some View {
        NoteCard(note: note, isShared: model.sharedNoteIDs.contains(note.id))
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

    @ViewBuilder private var syncStatus: some View {
        switch sync.state {
        case .syncing:
            HStack(spacing: 4) { Image(systemName: "arrow.triangle.2.circlepath"); Text("Syncing…") }
        case .synced:
            HStack(spacing: 4) { Image(systemName: "checkmark.icloud"); Text("Synced") }
        case .error:
            HStack(spacing: 4) { Image(systemName: "exclamationmark.icloud"); Text("Sync paused") }
        case .idle:
            EmptyView()
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

private struct NoteCard: View {
    let note: Note
    var isShared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: WoojSpace.md) {
            Text(preview)
                .font(.custom(WoojType.reading.family, size: 16))
                .foregroundStyle(WoojColor.reading)
                .lineSpacing(3)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: WoojSpace.xs)
            HStack(spacing: WoojSpace.xs) {
                Text(Self.relativeTime(note.modifiedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WoojColor.muted)
                Spacer()
                if isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WoojColor.clay)
                        .accessibilityLabel("Shared note")
                }
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
        let raw = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "New note" }
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
