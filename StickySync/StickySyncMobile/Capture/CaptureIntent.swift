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

/// Registers the intent for the Action Button and "Hey Siri" without the user
/// having to build a Shortcut by hand. Phrases resolve `applicationName` to
/// "StickySync".
struct CaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Capture with \(.applicationName)",
                "New \(.applicationName) note",
                "Take a note with \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "mic.fill"
        )
    }
}
