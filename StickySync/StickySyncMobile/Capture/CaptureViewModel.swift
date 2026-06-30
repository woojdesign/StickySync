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
    /// True while the WhisperKit second pass is refining the just-saved text, so
    /// the saved card can show it's still polishing — not a final, possibly-wrong
    /// transcript with no recourse.
    @Published private(set) var refining = false
    /// Color the saved sticky is showing. Defaults to slot 1; the user can
    /// pick a different swatch on SavedView before the dismiss timer runs out,
    /// which writes through to the persisted note.
    @Published private(set) var savedColorToken: String = Palette.defaultToken

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
    /// How long the SavedView lingers after polish completes,
    /// giving the user a chance to read the polished text + tap
    /// Copy & Delete / Delete before auto-dismiss. Bumped from
    /// the old 1.8s in 0.9.2 to match the Mac chip cadence and
    /// give comfortable reading time. The 0.9.1 indefinite-pause
    /// was Sean's first read, retracted in 0.9.2 ("Dismiss should
    /// happen after a few seconds") — long enough to act, short
    /// enough to feel calm.
    private let savedDwell: TimeInterval = 6.0

    init(store: NoteStore? = nil) {
        // Write through the app's shared store when given one, so captured notes
        // land in the list and we avoid a second CloudKit container; fall back to
        // the standalone container otherwise.
        writer = store.map { NoteWriter(store: $0) } ?? NoteWriter()
        speech.$partial.receive(on: RunLoop.main)
            .assign(to: \.partialText, on: self).store(in: &cancellables)
        recorder.$level.receive(on: RunLoop.main)
            .assign(to: \.level, on: self).store(in: &cancellables)
        // Action Button pressed mid-take: end the take just as if the user tapped
        // Done. Posted by `CaptureIntent` when it sees `CaptureLauncher.isCapturing`.
        NotificationCenter.default.publisher(for: .stopCapture)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.done() }
            .store(in: &cancellables)
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

    /// User tapped a swatch on the SavedView — recolor the visible card
    /// and write the new token through to the persisted note. Safe to call
    /// even before the WhisperKit polish finishes; the eventual `update`
    /// in `finish()` will preserve this color since it uses `lastNote`
    /// which is updated below.
    func pickColor(_ token: String) {
        savedColorToken = token
        guard let note = lastNote else { return }
        var updated = note
        updated.colorToken = token
        lastNote = updated
        writer.update(note, colorToken: token)
    }

    func cancel() {
        stopEngines()
        reset()
        phase = .idle
        CaptureLauncher.isCapturing = false
    }

    func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Post-polish actions (0.9.1)

    /// Copy the saved transcript to the system pasteboard and delete
    /// the underlying note. Mirrors Mac's PostPolishChip "Copy" —
    /// the user wanted the text somewhere else, the sticky was just
    /// a way to get it there.
    func copyAndDelete() {
        #if canImport(UIKit)
        UIPasteboard.general.string = savedText
        #endif
        deleteSaved()
    }

    /// Delete the saved note without copying. The capture is
    /// discarded entirely.
    func deleteSaved() {
        if let note = lastNote { writer.softDelete(note) }
        lastNote = nil
        dismissNow()
    }

    /// Explicit dismiss (X tap) — keep the note, just close the
    /// SavedView. Used as the "no, I'm keeping it, get out of my
    /// way" affordance now that the post-polish state pauses
    /// auto-dismiss.
    func dismissNow() {
        dismissTask?.cancel()
        reset()
        withAnimation(WoojMotion.calm.animation) { phase = .idle }
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

        partialText = ""; elapsed = 0; lastNote = nil; refining = false
        savedColorToken = Palette.defaultToken
        // Load the WhisperKit model while the user talks, so the final pass is
        // ready the instant they stop.
        finalizer.prewarm()
        withAnimation(WoojMotion.calm.animation) { phase = .listening }
        // Mirror the listening state for the Action Button intent so a second
        // press routes to `.stopCapture` instead of starting a new take.
        CaptureLauncher.isCapturing = true
        startTicker()
    }

    private func finish() async {
        guard phase == .listening else { return }
        stopEngines()
        // Listening just ended — the Action Button now starts a new take rather
        // than stopping one that's already over.
        CaptureLauncher.isCapturing = false

        let fast = speech.end()
        let text = (fast.isEmpty ? partialText : fast)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing was said → silent discard, no note.
        guard !text.isEmpty else { reset(); phase = .idle; return }

        // Show immediately with the fast text; write the note now.
        savedText = text
        savedAt = Date()
        let written = writer.write(text)
        lastNote = written
        refining = true                  // a second pass is coming — the card shows it
        withAnimation(WoojMotion.settle.animation) { phase = .saved }
        scheduleDismiss()                // holds the card while `refining`, capped

        // Second pass (WhisperKit): re-transcribe the recording and replace the
        // fast text. Runs to completion even if the card already dismissed, so the
        // note still upgrades in the list. Falls back to the fast text on any
        // failure — a note is never lost.
        let refined = await finalizer.finalize(audioURL: recorder.fileURL, fastPartial: text)
        // The polish must refine, never gut. A bad/empty recording makes Whisper
        // hallucinate a short phrase ("here and i") — only accept the refined text
        // when it kept most of the live transcript's length, else keep the (good)
        // SFSpeech text.
        let fastWords = text.split(whereSeparator: \.isWhitespace).count
        let refinedWords = refined.split(whereSeparator: \.isWhitespace).count
        let isImprovement = !refined.isEmpty && refined != text
            && refinedWords >= max(3, Int(Double(fastWords) * 0.6))
        if isImprovement {
            savedText = refined
            // Use `lastNote` (which may carry a swatch the user tapped on
            // SavedView mid-polish), not the original `written` snapshot —
            // otherwise the content update would silently revert the color.
            if let current = lastNote { writer.update(current, content: refined) }
        }
        refining = false
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Hold the saved card while the second pass runs, capped so a cold
            // model download can't pin it open. Once polish completes, we
            // now PAUSE here — the user gets the Copy/Delete affordance and
            // explicitly dismisses (Copy/Delete action or X tap). The auto-
            // dismiss after polish was Sean's call to remove in 0.9.1 so the
            // post-polish chip on iOS doesn't vanish before the user reads it.
            // Wait for polish to complete (cap so a cold model download
            // can't pin forever). Then dwell `savedDwell` so the user
            // can read + tap Copy & Delete / Delete before auto-
            // dismiss. 0.9.2 revision: dwell bumped to 6s (was 1.8s)
            // since the post-polish actions need real reading time.
            let cap = 6.0, step = 0.1
            var waited = 0.0
            while self.refining && waited < cap {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                if Task.isCancelled { return }
                waited += step
            }
            try? await Task.sleep(nanoseconds: UInt64(self.savedDwell * 1_000_000_000))
            if Task.isCancelled { return }
            guard self.phase == .saved else { return }
            self.reset()
            withAnimation(WoojMotion.calm.animation) { self.phase = .idle }
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
        elapsed = 0; level = 0; lastNote = nil; refining = false
    }
}
