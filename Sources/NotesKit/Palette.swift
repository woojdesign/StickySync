import Foundation

/// A curated note color. Each token carries its own readable text color for
/// both light and dark appearance, so notes are never illegible and the app
/// stays visually cohesive. Colors are stored as hex strings here (no AppKit
/// dependency); the UI layer turns them into `NSColor`.
public struct PaletteColor: Equatable {
    public let token: String
    public let displayName: String
    public let lightBackgroundHex: String
    public let lightTextHex: String
    public let darkBackgroundHex: String
    public let darkTextHex: String

    public init(
        token: String,
        displayName: String,
        lightBackgroundHex: String,
        lightTextHex: String,
        darkBackgroundHex: String,
        darkTextHex: String
    ) {
        self.token = token
        self.displayName = displayName
        self.lightBackgroundHex = lightBackgroundHex
        self.lightTextHex = lightTextHex
        self.darkBackgroundHex = darkBackgroundHex
        self.darkTextHex = darkTextHex
    }
}

public enum Palette {
    public static let defaultToken = "butter"

    public static let colors: [PaletteColor] = [
        PaletteColor(token: "butter", displayName: "Butter",
                     lightBackgroundHex: "#FFF1B8", lightTextHex: "#7A5D00",
                     darkBackgroundHex: "#524319", darkTextHex: "#F6E6A8"),
        PaletteColor(token: "peach", displayName: "Peach",
                     lightBackgroundHex: "#FFE0CC", lightTextHex: "#9A4A1F",
                     darkBackgroundHex: "#5A3522", darkTextHex: "#FAD3BC"),
        PaletteColor(token: "rose", displayName: "Rose",
                     lightBackgroundHex: "#FBD5E4", lightTextHex: "#99355A",
                     darkBackgroundHex: "#55243A", darkTextHex: "#F6C2D6"),
        PaletteColor(token: "lilac", displayName: "Lilac",
                     lightBackgroundHex: "#E7DBF7", lightTextHex: "#5A3F93",
                     darkBackgroundHex: "#3C2F5A", darkTextHex: "#DAC9F4"),
        PaletteColor(token: "sky", displayName: "Sky",
                     lightBackgroundHex: "#D4E9FF", lightTextHex: "#1F5DA5",
                     darkBackgroundHex: "#1E3855", darkTextHex: "#C2DDF7"),
        PaletteColor(token: "mint", displayName: "Mint",
                     lightBackgroundHex: "#D2F0DD", lightTextHex: "#1F7A4D",
                     darkBackgroundHex: "#1E4633", darkTextHex: "#BFE8CF"),
        PaletteColor(token: "sand", displayName: "Sand",
                     lightBackgroundHex: "#ECEAE2", lightTextHex: "#5F5E58",
                     darkBackgroundHex: "#3E3D38", darkTextHex: "#DAD8CF")
    ]

    public static func color(for token: String) -> PaletteColor {
        colors.first { $0.token == token } ?? colors[0]
    }
}
