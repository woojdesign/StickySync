import AppIntents
import Foundation

/// Cold-launch handoff. When the intent runs from a cold start, `perform()` posts
/// `.startCapture` before the root view is necessarily listening, so it also
/// raises this flag; the root consumes it on appear. The notification alone
/// covers the warm case (app already running). See [CaptureNotifications] for the
/// `.startCapture` name.
enum CaptureLauncher {
    @MainActor static var pending = false
}

/// The single voice-capture entry point — Action Button, Lock-Screen /
/// Control-Center widget, or "Hey Siri". Brings StickySync forward; the capture
/// sheet then opens and starts listening on its own.
struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a Note"
    static var description = IntentDescription("Speak a thought; StickySync saves it as a note.")

    /// Bring the app forward; the root presents the capture sheet, which listens.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLauncher.pending = true
        NotificationCenter.default.post(name: .startCapture, object: nil)
        return .result()
    }
}

/// Saves dictated text straight to a note: Siri captures the words and writes the
/// note in the background — no recording screen. "Hey Siri, save the following to
/// StickySync" → Siri asks what to save → it lands as a note.
struct SaveNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Save a Note"
    static var description = IntentDescription("Save spoken text straight to a StickySync note, without opening the app.")

    /// Background: never opens the app — the note is written and synced silently.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note", requestValueDialog: "What's the note?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result(dialog: "There was nothing to save.") }
        NoteWriter(store: NoteStoreProvider.shared).write(trimmed)
        return .result(dialog: "Saved to StickySync.")
    }
}

/// Registers both intents for the Action Button and "Hey Siri" without the user
/// building a Shortcut by hand. The Action Button takes the record-screen
/// `CaptureIntent`; Siri's "save the following" phrases take the text-only
/// `SaveNoteIntent`. Phrases resolve `applicationName` to "StickySync".
struct CaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Capture with \(.applicationName)",
                "Record a \(.applicationName) note"
            ],
            shortTitle: "Capture",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: SaveNoteIntent(),
            phrases: [
                "Save a note to \(.applicationName)",
                "New \(.applicationName) note",
                "Save the following to \(.applicationName)"
            ],
            shortTitle: "Save Note",
            systemImageName: "square.and.pencil"
        )
    }
}
