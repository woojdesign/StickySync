// WoojTokens.swift — AUTO-GENERATED from tokens.json. Do not edit by hand.
// Regenerate:  make tokens   (or: node build.mjs)
//
// Pure token values: colors, spacing, radii, and text styles. The WoojUI
// component layer wraps these (Dynamic Type, materials, motion).

import SwiftUI

public enum WoojColor {
    /// primary warm app background (bone) — #F3EFE4
    public static let ground = Color(.sRGB, red: 0.9529, green: 0.9373, blue: 0.8941, opacity: 1)
    /// lighter warm white — cards, sheets, elevated/alt surfaces — #FBFAF5
    public static let surface = Color(.sRGB, red: 0.9843, green: 0.9804, blue: 0.9608, opacity: 1)
    /// lightest warm white — note paper — #FFFEFB
    public static let paper = Color(.sRGB, red: 1, green: 0.9961, blue: 0.9843, opacity: 1)
    /// primary text — #1C1B1A
    public static let ink = Color(.sRGB, red: 0.1098, green: 0.1059, blue: 0.102, opacity: 1)
    /// long-form body text — #3F3D38
    public static let reading = Color(.sRGB, red: 0.2471, green: 0.2392, blue: 0.2196, opacity: 1)
    /// #57554E
    public static let secondary = Color(.sRGB, red: 0.3412, green: 0.3333, blue: 0.3059, opacity: 1)
    /// smoke — labels, captions — #8B887F
    public static let tertiary = Color(.sRGB, red: 0.5451, green: 0.5333, blue: 0.498, opacity: 1)
    /// #9A958A
    public static let muted = Color(.sRGB, red: 0.6039, green: 0.5843, blue: 0.5412, opacity: 1)
    /// #B7B3A9
    public static let faint = Color(.sRGB, red: 0.7176, green: 0.702, blue: 0.6627, opacity: 1)
    /// hairline (ink @ ~12%) — #1C1B1A20
    public static let line = Color(.sRGB, red: 0.1098, green: 0.1059, blue: 0.102, opacity: 0.1255)
    /// the one confident accent — #C2674F
    public static let clay = Color(.sRGB, red: 0.7608, green: 0.4039, blue: 0.3098, opacity: 1)
    /// clay, pressed/active — #A8543E
    public static let clayPressed = Color(.sRGB, red: 0.6588, green: 0.3294, blue: 0.2431, opacity: 1)
    /// text/icons on clay — #FFF8F1
    public static let onClay = Color(.sRGB, red: 1, green: 0.9725, blue: 0.9451, opacity: 1)
    /// lamp amber — alternate accent, available — #D98F43
    public static let amber = Color(.sRGB, red: 0.851, green: 0.5608, blue: 0.2627, opacity: 1)
}

public enum WoojSticky {
    /// #EAD79A
    public static let butter = Color(.sRGB, red: 0.9176, green: 0.8431, blue: 0.6039, opacity: 1)
    /// #EBC8A2
    public static let apricot = Color(.sRGB, red: 0.9216, green: 0.7843, blue: 0.6353, opacity: 1)
    /// #E7B6A6
    public static let rose = Color(.sRGB, red: 0.9059, green: 0.7137, blue: 0.651, opacity: 1)
    /// #E8BFC8
    public static let blush = Color(.sRGB, red: 0.9098, green: 0.749, blue: 0.7843, opacity: 1)
    /// #D2C6DE
    public static let lilac = Color(.sRGB, red: 0.8235, green: 0.7765, blue: 0.8706, opacity: 1)
    /// #C6D2AE
    public static let sage = Color(.sRGB, red: 0.7765, green: 0.8235, blue: 0.6824, opacity: 1)
    /// #B7CDD6
    public static let sky = Color(.sRGB, red: 0.7176, green: 0.8039, blue: 0.8392, opacity: 1)
    /// #F1E9D5
    public static let cream = Color(.sRGB, red: 0.9451, green: 0.9137, blue: 0.8353, opacity: 1)
    /// Every note color, in palette order.
    public static let all: [Color] = [butter, apricot, rose, blush, lilac, sage, sky, cream]
}

public enum WoojSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    public static let xxxl: CGFloat = 64
    public static let huge: CGFloat = 96
}

public enum WoojRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let pill: CGFloat = 999
}

public enum WoojMeasure {
    /// max reading line length, in ch
    public static let reading: CGFloat = 65
}

/// A text style token: raw values + a convenience fixed-size font.
/// WoojUI layers Dynamic Type on top via `relativeTo:`.
public struct WoojTextStyle {
    public let family: String
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: Font.Weight
    public let tracking: CGFloat
    /// Extra line spacing to reach `lineHeight` (for SwiftUI `.lineSpacing`).
    public var lineSpacing: CGFloat { max(0, lineHeight - size) }
    public var font: Font { .custom(family, fixedSize: size).weight(weight) }
}

public enum WoojType {
    public static let display = WoojTextStyle(family: "Fraunces", size: 40, lineHeight: 44, weight: .medium, tracking: -0.5)
    public static let title = WoojTextStyle(family: "Fraunces", size: 28, lineHeight: 34, weight: .medium, tracking: -0.25)
    public static let heading = WoojTextStyle(family: "Apercu", size: 20, lineHeight: 26, weight: .semibold, tracking: 0)
    public static let reading = WoojTextStyle(family: "Charter", size: 21, lineHeight: 34, weight: .regular, tracking: 0)
    public static let body = WoojTextStyle(family: "Apercu", size: 16, lineHeight: 22, weight: .regular, tracking: 0)
    public static let label = WoojTextStyle(family: "Apercu", size: 13, lineHeight: 18, weight: .medium, tracking: 0.3)
    public static let caption = WoojTextStyle(family: "Apercu", size: 11, lineHeight: 14, weight: .regular, tracking: 0.4)
    public static let mono = WoojTextStyle(family: "ABCDiatypeMono", size: 13, lineHeight: 18, weight: .regular, tracking: 0)
}

public extension Text {
    /// Apply a Wooj text style (font, weight, tracking) in one call.
    func woojStyle(_ s: WoojTextStyle) -> Text { self.font(s.font).tracking(s.tracking) }
}

