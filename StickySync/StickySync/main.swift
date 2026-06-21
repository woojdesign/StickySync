import AppKit

// Top-level main.swift code runs on the main thread, but the compiler treats
// it as nonisolated — so assert main-actor isolation. Otherwise AppDelegate's
// main-actor-isolated conformance to NSApplicationDelegate can't be used here
// (flagged by SWIFT_APPROACHABLE_CONCURRENCY / the Swift 6 language mode).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let delegate = AppDelegate()
    app.delegate = delegate

    app.run()
}
