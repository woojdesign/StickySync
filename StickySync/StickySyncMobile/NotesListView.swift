import SwiftUI
import NotesKit

/// Root screen, styled to the wooj index mockup: a serif "Notes" header + count,
/// a search field, and a grid of note cards (title + time footer) on the warm
/// ground, with a bottom capture bar. Presentation only — no model change.
/// (Voice capture, and the pushed editor + bottom palette dock, are deferred.)
struct NotesListView: View {
    @EnvironmentObject private var model: NotesModel
    @State private var editing: Note?
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var filtered: [Note] {
        guard !search.isEmpty else { return model.notes }
        return model.notes.filter { $0.content.localizedCaseInsensitiveContains(search) }
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
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filtered) { note in
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
        .sheet(item: $editing) { note in
            NoteEditorView(note: note)
                .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Charter stands in for the wooj display face (Fraunces) until the
            // custom faces are bundled; it renders as a real serif today.
            Text("Notes")
                .font(.custom(WoojType.reading.family, size: 34).weight(.semibold))
                .foregroundStyle(WoojColor.ink)
            Text("^[\(model.notes.count) note](inflect: true)")
                .font(.system(size: 13))
                .foregroundStyle(WoojColor.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom(WoojType.reading.family, size: 16))
                .foregroundStyle(Appearance.text(note.colorToken))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 10)
            Text(Self.relativeTime(note.modifiedAt))
                .font(.system(size: 11))
                .foregroundStyle(Appearance.text(note.colorToken).opacity(0.6))
        }
        .frame(minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(Appearance.background(note.colorToken))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WoojColor.line, lineWidth: 1))
    }

    private var title: String {
        let first = note.content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return first.isEmpty ? "New note" : first
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
