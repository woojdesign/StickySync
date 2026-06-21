import Foundation

extension Notification.Name {
    /// Posted by the Capture App Intent (Phase 2) when capture is triggered while
    /// StickySync is already running — `CaptureView` observes it to start a take.
    /// Defined here in Phase 1 so the observer compiles before the Intent lands.
    static let startCapture = Notification.Name("design.wooj.StickySync.startCapture")
}
