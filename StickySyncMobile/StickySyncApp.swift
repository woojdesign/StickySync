import SwiftUI
import NotesKit

@main
struct StickySyncApp: App {
    // Same NotesKit store + CloudKit container as the Mac app, so notes sync
    // across all of your devices.
    @StateObject private var model = NotesModel(store: CloudKitNoteStore())

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environmentObject(model)
        }
    }
}
