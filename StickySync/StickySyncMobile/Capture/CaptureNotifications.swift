import Foundation

extension Notification.Name {
    /// Posted by the Capture App Intent (Phase 2) when capture is triggered while
    /// StickySync is already running — `CaptureView` observes it to start a take.
    /// Defined here in Phase 1 so the observer compiles before the Intent lands.
    static let startCapture = Notification.Name("design.wooj.StickySync.startCapture")
    /// Posted by `CaptureIntent` when the user presses the Action Button while a
    /// take is already in progress. `CaptureViewModel` observes this and ends
    /// the take just as if the user had tapped Done.
    static let stopCapture = Notification.Name("design.wooj.StickySync.stopCapture")
}
