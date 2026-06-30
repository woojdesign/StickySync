import SwiftUI
import NotesKit
import WoojTokens

/// The saved state: the transcript settles into a colored sticky with a calm
/// spring, a clay check, a `voice · {time}` footer, and an "Saved" hint.
/// Tappable (on the sticky body) to re-record before it auto-dismisses;
/// the swatch dock below lets the user pick a color while WhisperKit polishes.
struct SavedView: View {
    @ObservedObject var vm: CaptureViewModel
    @ObservedObject private var theme = ThemeStore.shared
    @State private var landed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: WoojSpace.lg) {
                sticky
                    .scaleEffect(landed ? 1 : 0.92)
                    .opacity(landed ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.recapture() }

                paletteDock
                    .opacity(landed ? 1 : 0)

                // Once polish completes (refining flips false) the
                // dismiss timer pauses (CaptureViewModel.scheduleDismiss)
                // and the user gets explicit actions. 0.9.1: mirrors
                // Mac's PostPolishChip — Copy hands the polished text
                // to the pasteboard + deletes the sticky; Delete
                // discards without copying.
                if !vm.refining && landed {
                    postPolishActions
                        .transition(.opacity)
                } else {
                    hint
                        .opacity(landed ? 1 : 0)
                }
            }
            .padding(.horizontal, WoojSpace.xl)

            // Explicit dismiss-without-action (X) — needed because the
            // post-polish state pauses auto-dismiss. Top-right corner so
            // it's discoverable without competing with the sticky.
            if !vm.refining && landed {
                Button { vm.dismissNow() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(WoojColor.muted)
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .transition(.opacity)
            }
        }
        .animation(WoojMotion.calm.animation, value: vm.refining)
        .onAppear {
            withAnimation(WoojMotion.settle.animation) { landed = true }
        }
    }

    private var postPolishActions: some View {
        HStack(spacing: WoojSpace.md) {
            actionButton(title: "Copy",
                         symbol: "doc.on.doc",
                         tint: WoojColor.clay) { vm.copyAndDelete() }
            actionButton(title: "Delete",
                         symbol: "trash",
                         tint: WoojColor.muted) { vm.deleteSaved() }
        }
    }

    private func actionButton(title: String,
                              symbol: String,
                              tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WoojSpace.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .woojStyle(WoojType.label)
            }
            .foregroundColor(tint)
            .padding(.horizontal, WoojSpace.lg)
            .padding(.vertical, WoojSpace.sm)
            .background(WoojColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(WoojColor.line))
        }
        .buttonStyle(.plain)
    }

    /// Color picker shown beneath the saved sticky. The dock isn't part of
    /// the tap-to-recapture surface — tapping a swatch only changes the
    /// color, never starts a new take.
    private var paletteDock: some View {
        HStack(spacing: WoojSpace.sm) {
            ForEach(Palette.colors, id: \.token) { c in
                Circle()
                    .fill(Appearance.background(c.token))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(
                            vm.savedColorToken == c.token ? WoojColor.clay : WoojColor.line,
                            lineWidth: vm.savedColorToken == c.token ? 2 : 1)
                    )
                    .onTapGesture { vm.pickColor(c.token) }
            }
        }
        .padding(.horizontal, WoojSpace.md)
        .padding(.vertical, WoojSpace.sm)
        .background(WoojColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(WoojColor.line))
        .shadow(color: WoojColor.ink.opacity(0.08), radius: 8, y: 2)
        .animation(WoojMotion.calm.animation, value: vm.savedColorToken)
    }

    private var sticky: some View {
        // Per-slot text color (same pattern as the index NoteCard in
        // 0.7.8). When the user picks a dark swatch from the SavedView
        // dock (Bold Berry's Burgundy, Sunny Beach's Slate, etc.) the
        // body text + footer follow the palette's white-ink pair instead
        // of staying hardcoded dark. The check brand-color stays clay
        // since it reads as identity, not text.
        let textColor = Appearance.text(vm.savedColorToken)
        return VStack(alignment: .leading, spacing: WoojSpace.md) {
            Text(vm.savedText)
                .woojStyle(WoojType.reading)
                .foregroundColor(textColor)
                .lineSpacing(WoojType.reading.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(WoojMotion.calm.animation, value: vm.savedText)

            HStack(spacing: WoojSpace.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WoojColor.clay)
                Text(footer)
                    .woojStyle(WoojType.mono)
                    .foregroundColor(textColor.opacity(0.6))
            }
        }
        .padding(WoojSpace.lg)
        .background(
            Appearance.background(vm.savedColorToken),
            in: RoundedRectangle(cornerRadius: WoojRadius.lg, style: .continuous)
        )
        .shadow(color: WoojColor.ink.opacity(0.08), radius: 12, y: 6)
        .frame(maxWidth: WoojMeasure.reading * 10)
        .animation(WoojMotion.calm.animation, value: vm.savedColorToken)
    }

    private var hint: some View {
        HStack(spacing: WoojSpace.xxs) {
            if vm.refining {
                ProgressView()
                    .controlSize(.mini)
                    .tint(WoojColor.clay)
                Text("Polishing transcript…")
                    .woojStyle(WoojType.caption)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Saved")
                    .woojStyle(WoojType.caption)
            }
        }
        .foregroundColor(WoojColor.tertiary)
        .animation(WoojMotion.calm.animation, value: vm.refining)
    }

    private var footer: String {
        let time = vm.savedAt ?? Date()
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "voice · \(f.string(from: time))"
    }
}
