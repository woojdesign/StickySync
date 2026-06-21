import Foundation
import Speech
import Combine
import AVFoundation

/// On-device live transcription via `SFSpeechRecognizer`. Drives the on-screen
/// partial and the v1 final text (until WhisperKit takes over in Phase 3).
/// `requiresOnDeviceRecognition` is forced on: nothing leaves the device.
///
/// **Pauses are handled by accumulation.** SFSpeech ends a segment on silence and
/// its `formattedString` then restarts from empty — which on its own would
/// *overwrite* what came before. So each finalized segment is folded into
/// `committed` and a fresh segment is opened immediately; the live `partial` is
/// `committed` plus the current segment. Nothing said is lost across a pause, and
/// the session ends only when the caller calls `end()` — it never self-terminates
/// on silence.
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var partial: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var committed = ""     // finalized segments, joined with spaces
    private var segment = ""       // the current (live) segment's text
    private var running = false

    /// Starts a session. Feed captured audio with `append(_:)`, read `partial`
    /// for the live text, and call `end()` to stop and get the full transcript.
    func begin() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Capture.Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition unavailable"])
        }
        task?.cancel(); task = nil
        committed = ""; segment = ""; partial = ""
        running = true
        startSegment()
    }

    /// Forwards a captured audio buffer to the active recognition request. Called
    /// on the audio tap thread; `request` is only swapped on the main thread, so a
    /// buffer at the swap boundary simply reaches an adjacent (still-valid) request.
    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    /// Stops recognition and returns everything captured, pauses included.
    func end() -> String {
        running = false
        request?.endAudio(); request = nil
        task?.finish(); task = nil
        commit()
        return committed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    // MARK: - Segments (all main-thread)

    private func startSegment() {
        guard running, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Guarded so we never silently fall back to the network.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req
        segment = ""
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async { self.handle(result, error) }
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        guard running else { return }
        if let result { segment = result.bestTranscription.formattedString }
        partial = joined()

        // A finalized segment is the recognizer's response to a pause. Fold it in
        // and open a fresh one so dictation continues seamlessly. Some iOS builds
        // surface a pause as an error instead of `isFinal`; treat that the same
        // way *if the segment actually heard speech*, so a hard failure (e.g. the
        // recognizer going unavailable) can't spin a restart loop.
        let heardSpeech = !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if result?.isFinal == true {
            restartSegment()
        } else if error != nil {
            if heardSpeech { restartSegment() } else { commit(); request = nil; task = nil; running = false }
        }
    }

    private func restartSegment() {
        commit()
        request = nil; task = nil
        startSegment()
    }

    private func joined() -> String {
        let seg = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty { return seg }
        if seg.isEmpty { return committed }
        return committed + " " + seg
    }

    private func commit() {
        let seg = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seg.isEmpty { committed = committed.isEmpty ? seg : committed + " " + seg }
        segment = ""
    }
}
