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
        // Platform-agnostic model + persistence (Foundation + CoreData, no UI
        // framework) so the macOS app and a future iOS app reuse it unchanged.
        // The app itself lives in the Xcode project (StickySync/) and links
        // this NotesKit library product.
        .target(
            name: "NotesKit",
            // CloudKit.framework must be explicitly linked, or a sandboxed app
            // can't reach the CloudKit daemon (cloudd) — the "error 159 sandbox
            // restriction" failure. NSPersistentCloudKitContainer lives in
            // CoreData, so CloudKit isn't pulled in automatically.
            linkerSettings: [
                .linkedFramework("CloudKit")
            ]
        ),
        .testTarget(
            name: "NotesKitTests",
            dependencies: ["NotesKit"]
        )
    ]
)
