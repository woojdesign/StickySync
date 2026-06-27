import SwiftUI
import NotesKit

/// The one CloudKit-backed store per process, shared by the UI (`NotesModel`) and
/// the background `SaveNoteIntent`. Routing both through a single instance avoids
/// two `NSPersistentCloudKitContainer`s opening the same store file in one
/// process (e.g. a Siri capture while the app is foreground).
enum NoteStoreProvider {
    static let shared: NoteStore = CloudKitNoteStore()
}

@main
struct StickySyncApp: App {
    // Same NotesKit store + CloudKit container as the Mac app, so notes sync
    // across all of your devices.
    @StateObject private var model = NotesModel(store: NoteStoreProvider.shared)

    init() {
        // Drop a "what's new in X.Y.0" release sticky if we've crossed a
        // minor/major bump since the last launch. Patch versions don't
        // surface; fresh installs treat current as seen.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        MainActor.assumeIsolated {
            ReleaseNotes.dropStickyIfNeeded(into: NoteStoreProvider.shared,
                                            currentVersion: version)
        }
    }

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environmentObject(model)
        }
    }
}
