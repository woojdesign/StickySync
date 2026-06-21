import SwiftUI
import Combine
import NotesKit
import WoojTokens

/// The capture state machine. Owns the recorder, the live transcriber, the
/// finalizer, and the NotesKit writer, and exposes just enough published state
/// for the two-state UI.
///
/// Flow: trigger → `listening` (recording already started) → `done()`/auto-stop
/// → write note → `saved` → auto-dismiss back to `idle`. `cancel()` discards.
@MainActor
final class CaptureViewModel: ObservableObject {
    enum Phase: Equatable { case idle, listening, saved, denied }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partialText: String = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var savedText: String = ""
    @Published private(set) var savedAt: Date?

    private let recorder = AudioRecorder()
    private let speech = SpeechTranscriber()
    private let writer: NoteWriter
    // High-fidelity final pass (WhisperKit base.en). Falls back to the SFSpeech
    // partial whenever it can't run, so capture never depends on it.
    private let finalizer: TranscriptionFinalizer = WhisperKitFinalizer()

    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?
    private var dismissTask: Task<Void, Never>?
    private var lastNote: Note?
    private var starting = false

    private let tick: TimeInterval = 0.05
    private let savedDwell: TimeInterval = 1.8

    init(store: NoteStore? = nil) {
        // Write through the app's shared store when given one, so captured notes
        // land in the list and we avoid a second CloudKit container; fall back to
        // the standalone container otherwise.
        writer = store.map { NoteWriter(store: $0) } ?? NoteWriter()
        speech.$partial.receive(on: RunLoop.main)
            .assign(to: \.partialText, on: self).store(in: &cancellables)
        recorder.$level.receive(on: RunLoop.main)
            .assign(to: \.level, on: self).store(in: &cancellables)
    }

    /// Entry point for every trigger route. Safe to call repeatedly.
    func startIfNeeded() {
        guard phase != .listening, !starting else { return }
        starting = true
        dismissTask?.cancel()
        Task { await begin() }
    }

    /// Tapping the saved card before it dismisses re-records.
    func recapture() {
        dismissTask?.cancel()
        startIfNeeded()
    }

    func done() { Task { await finish() } }

    func cancel() {
        stopEngines()
        reset()
        phase = .idle
    }

    func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Lifecycle

    private func begin() async {
        defer { starting = false }
        let mic = await AudioRecorder.requestMicPermission()
        let granted = await SpeechTranscriber.requestAuthorization()
        guard mic, granted else { phase = .denied; return }

        do {
            try speech.begin()
            try recorder.start { [weak self] buffer in self?.speech.append(buffer) }
        } catch {
            phase = .denied
            return
        }

        partialText = ""; elapsed = 0; lastNote = nil
        // Load the WhisperKit model while the user talks, so the final pass is
        // ready the instant they stop.
        finalizer.prewarm()
        withAnimation(WoojMotion.calm.animation) { phase = .listening }
        startTicker()
    }

    private func finish() async {
        guard phase == .listening else { return }
        stopEngines()

        let fast = speech.end()
        let text = (fast.isEmpty ? partialText : fast)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing was said → silent discard, no note.
        guard !text.isEmpty else { reset(); phase = .idle; return }

        // Show immediately with the fast text; write the note now.
        savedText = text
        savedAt = Date()
        lastNote = writer.write(text)
        withAnimation(WoojMotion.settle.animation) { phase = .saved }
        scheduleDismiss()

        // Finalize asynchronously and silently replace (Phase 3: WhisperKit).
        let refined = await finalizer.finalize(audioURL: recorder.fileURL, fastPartial: text)
        if refined != text, !refined.isEmpty {
            savedText = refined
            if let note = lastNote { writer.update(note, content: refined) }
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [savedDwell] in
            try? await Task.sleep(nanoseconds: UInt64(savedDwell * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.phase == .saved else { return }
                self.reset()
                withAnimation(WoojMotion.calm.animation) { self.phase = .idle }
            }
        }
    }

    // MARK: - Ticker (timer + silence auto-stop)

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
    }

    private func onTick() {
        // Just the elapsed timer now. Capture ends only when the user taps Done —
        // never automatically on silence — so a thinking pause can't cut a note
        // short or create one on its own.
        guard phase == .listening else { return }
        elapsed += tick
    }

    private func stopEngines() {
        ticker?.invalidate(); ticker = nil
        recorder.stop()
    }

    private func reset() {
        partialText = ""; savedText = ""; savedAt = nil
        elapsed = 0; level = 0; lastNote = nil
    }
}
