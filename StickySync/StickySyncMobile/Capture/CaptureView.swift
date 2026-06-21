import SwiftUI
import WoojTokens

/// The whole app: one screen that swaps between calm states. Opens straight
/// into listening (cold launch via `onAppear`; warm trigger via notification).
struct CaptureView: View {
    @ObservedObject var vm: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            WoojColor.ground.ignoresSafeArea()

            switch vm.phase {
            case .idle:      IdleView()
            case .listening: ListeningView(vm: vm)
            case .saved:     SavedView(vm: vm)
            case .denied:    DeniedView(openSettings: vm.openSettings)
            }
        }
        .overlay(alignment: .topLeading) {
            // Only the denied state needs a close here — ListeningView has its own.
            if vm.phase == .denied {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(WoojColor.muted)
                        .frame(width: 40, height: 40)
                        .background(WoojColor.surface, in: Circle())
                }
                .padding(WoojSpace.md)
                .accessibilityLabel("Close")
            }
        }
        .animation(WoojMotion.calm.animation, value: vm.phase)
        .onAppear { vm.startIfNeeded() }
        .onChange(of: vm.phase) { newPhase in
            // After a save (saved → idle) or a cancel, close the sheet.
            if newPhase == .idle { dismiss() }
        }
        .onDisappear { vm.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .startCapture)) { _ in
            vm.startIfNeeded()
        }
    }
}

/// Quiet ready state — shown briefly after a save dismisses. (iOS can't send
/// the app back to the previous app programmatically, so "dismiss" lands here.)
private struct IdleView: View {
    var body: some View {
        VStack(spacing: WoojSpace.md) {
            Image(systemName: "mic")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(WoojColor.faint)
            Text("Press to capture")
                .woojStyle(WoojType.label)
                .foregroundColor(WoojColor.muted)
        }
    }
}

/// Graceful permission-denied state.
private struct DeniedView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: WoojSpace.lg) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(WoojColor.clay)
            Text("Capture needs the microphone and speech recognition to hear you.")
                .woojStyle(WoojType.body)
                .foregroundColor(WoojColor.reading)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: openSettings) {
                Text("Open Settings")
                    .woojStyle(WoojType.label)
                    .foregroundColor(WoojColor.onClay)
                    .padding(.horizontal, WoojSpace.lg)
                    .padding(.vertical, WoojSpace.sm)
                    .background(WoojColor.clay, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(WoojSpace.xl)
    }
}
