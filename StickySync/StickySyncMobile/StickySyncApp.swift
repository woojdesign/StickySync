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

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environmentObject(model)
        }
    }
}
