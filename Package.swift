// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickySync",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Platform-agnostic model + persistence.
        // This target imports only Foundation — no AppKit — so a future
        // iOS app and the CloudKit sync layer can reuse it unchanged.
        .target(
            name: "NotesKit"
        ),
        // The macOS app: AppKit floating-window UI on top of NotesKit.
        .executableTarget(
            name: "StickySync",
            dependencies: ["NotesKit"]
        )
    ]
)
