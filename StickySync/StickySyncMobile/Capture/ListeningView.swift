import SwiftUI
import WoojTokens

/// The listening state: full-bleed warm ground, the live transcript settling in
/// as you speak, a soft breathing dot, a mono timer, a Done pill, and a quiet
/// cancel.
struct ListeningView: View {
    @ObservedObject var vm: CaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(.vertical, showsIndicators: false) {
                transcript
                    .frame(maxWidth: WoojMeasure.reading * 10, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, WoojSpace.xl)
            }

            Spacer(minLength: WoojSpace.lg)

            BreathingDot(level: vm.level)
                .padding(.bottom, WoojSpace.lg)

            donePill
                .padding(.bottom, WoojSpace.xl)
        }
        .padding(.horizontal, WoojSpace.xl)
    }

    private var topBar: some View {
        HStack {
            Button(action: vm.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(WoojColor.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")

            Spacer()

            Text(timeString)
                .woojStyle(WoojType.mono)
                .monospacedDigit()
                .foregroundColor(WoojColor.muted)
        }
        .padding(.top, WoojSpace.sm)
    }

    @ViewBuilder private var transcript: some View {
        if vm.partialText.isEmpty {
            Text("Listening…")
                .woojStyle(WoojType.reading)
                .foregroundColor(WoojColor.faint)
                .lineSpacing(WoojType.reading.lineSpacing)
        } else {
            Text(vm.partialText)
                .woojStyle(WoojType.reading)
                .foregroundColor(WoojColor.reading)
                .lineSpacing(WoojType.reading.lineSpacing)
        }
    }

    private var donePill: some View {
        Button(action: vm.done) {
            Text("Done")
                .woojStyle(WoojType.label)
                .foregroundColor(WoojColor.onClay)
                .padding(.horizontal, WoojSpace.xl)
                .padding(.vertical, WoojSpace.sm)
                .background(WoojColor.clay, in: RoundedRectangle(cornerRadius: WoojRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var timeString: String {
        let s = Int(vm.elapsed)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}

/// One soft dot that breathes at rest and swells with the input level — the
/// quiet sign that Capture is hearing you.
struct BreathingDot: View {
    let level: Float
    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(WoojColor.clay)
            .frame(width: 14, height: 14)
            .scaleEffect(1 + CGFloat(level) * 0.7 + (breathe ? 0.12 : 0))
            .opacity(0.55 + Double(level) * 0.45)
            .animation(.easeOut(duration: 0.12), value: level)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            .accessibilityHidden(true)
    }
}
