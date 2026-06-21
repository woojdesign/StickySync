import SwiftUI

/// Local motion tokens, mirroring Capture's `Motion.swift`, until WoojTokens
/// ships `WoojMotion`. `settle` is the calm spring a sticky lands with; `calm`
/// is a soft cross-fade. (Belongs upstream in ~/dev/wooj-tokens so both apps
/// share one definition rather than two hand-copied ones.)
enum WoojMotion {
    static let settle = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let calm = Animation.easeInOut(duration: 0.45)
}
