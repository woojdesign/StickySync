import SwiftUI
import WoojTokens

/// The saved state: the transcript settles into a butter sticky with a calm
/// spring, a clay check, a `voice · {time}` footer, and an "Saved" hint.
/// Tappable to re-record before it auto-dismisses.
struct SavedView: View {
    @ObservedObject var vm: CaptureViewModel
    @State private var landed = false

    var body: some View {
        VStack(spacing: WoojSpace.lg) {
            sticky
                .scaleEffect(landed ? 1 : 0.92)
                .opacity(landed ? 1 : 0)

            hint
                .opacity(landed ? 1 : 0)
        }
        .padding(.horizontal, WoojSpace.xl)
        .contentShape(Rectangle())
        .onTapGesture { vm.recapture() }
        .onAppear {
            withAnimation(WoojMotion.settle.animation) { landed = true }
        }
    }

    private var sticky: some View {
        VStack(alignment: .leading, spacing: WoojSpace.md) {
            Text(vm.savedText)
                .woojStyle(WoojType.reading)
                .foregroundColor(WoojColor.reading)
                .lineSpacing(WoojType.reading.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: WoojSpace.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WoojColor.clay)
                Text(footer)
                    .woojStyle(WoojType.mono)
                    .foregroundColor(WoojColor.muted)
            }
        }
        .padding(WoojSpace.lg)
        .background(WoojSticky.butter, in: RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous))
        .shadow(color: WoojColor.ink.opacity(0.08), radius: 12, y: 6)
        .frame(maxWidth: WoojMeasure.reading * 10)
    }

    private var hint: some View {
        HStack(spacing: WoojSpace.xxs) {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 10, weight: .semibold))
            Text("Saved")
                .woojStyle(WoojType.caption)
        }
        .foregroundColor(WoojColor.tertiary)
    }

    private var footer: String {
        let time = vm.savedAt ?? Date()
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "voice · \(f.string(from: time))"
    }
}
