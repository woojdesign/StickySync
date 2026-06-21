import SwiftUI
import NotesKit

// wooj-tokens test: map NotesKit's note tokens onto the WoojSticky range and use
// wooj ink for text. WoojColor/WoojSticky are already SwiftUI Colors, so there's
// no bridge here (unlike the macOS AppKit side).
enum Appearance {
    private static let woojSticky: [String: Color] = [
        "butter": WoojSticky.butter, "peach": WoojSticky.apricot, "rose": WoojSticky.rose,
        "lilac": WoojSticky.lilac, "sky": WoojSticky.sky, "mint": WoojSticky.sage, "sand": WoojSticky.cream
    ]

    static func background(_ token: String) -> Color { woojSticky[token] ?? WoojSticky.butter }

    static func text(_ token: String) -> Color { WoojColor.ink }

    static func font(_ id: String, size: CGFloat) -> Font {
        switch FontCatalog.option(for: id).kind {
        case .system:          return .system(size: size)
        case .rounded:         return .system(size: size, design: .rounded)
        case .serif:           return .system(size: size, design: .serif)
        case .monospaced:      return .system(size: size, design: .monospaced)
        case .named(let name): return .custom(name, size: size)
        }
    }
}
