import Foundation

/// How to resolve a font without naming a specific installed typeface.
/// The UI layer maps these to concrete `NSFont`s. Using system designs
/// (plus a couple of safe named fonts) keeps notes rendering identically
/// across devices — the cross-device gotcha with "any installed font".
public enum FontKind: Equatable {
    case system
    case rounded
    case serif
    case monospaced
    case named(String)
}

public struct FontOption: Equatable {
    public let id: String
    public let displayName: String
    public let kind: FontKind

    public init(id: String, displayName: String, kind: FontKind) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
    }
}

public enum FontCatalog {
    public static let defaultID = "system"
    public static let minSize: Double = 11
    public static let maxSize: Double = 36

    public static let options: [FontOption] = [
        FontOption(id: "system", displayName: "System", kind: .system),
        FontOption(id: "rounded", displayName: "Rounded", kind: .rounded),
        FontOption(id: "serif", displayName: "Serif", kind: .serif),
        FontOption(id: "mono", displayName: "Mono", kind: .monospaced),
        FontOption(id: "marker", displayName: "Marker", kind: .named("Marker Felt"))
    ]

    public static func option(for id: String) -> FontOption {
        options.first { $0.id == id } ?? options[0]
    }

    public static func clampSize(_ size: Double) -> Double {
        min(maxSize, max(minSize, size))
    }
}
