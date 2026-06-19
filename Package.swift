// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickySync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Expose NotesKit as a library so an external consumer — the Xcode
        // app target — can link it. Without this, Xcode sees no products.
        .library(name: "NotesKit", targets: ["NotesKit"])
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
        ),
        .testTarget(
            name: "NotesKitTests",
            dependencies: ["NotesKit"]
        )
    ]
)
