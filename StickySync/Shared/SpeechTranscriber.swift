import Foundation
import Speech
import AVFoundation
import Combine

/// Live transcription via `SFSpeechRecognizer`, modeled on Quick Transcript's
/// proven `SpeechService`: a single recognition task whose `bestTranscription`
/// accumulates across pauses, so earlier words are never dropped or overwritten.
/// The session ends only when the caller calls `end()` — there is no silence
/// auto-stop.
///
/// Deliberately does NOT force `requiresOnDeviceRecognition`. Forcing the
/// on-device path (Capture's original choice) made the recognizer aggressively
/// segment and restart its hypothesis on a pause, wiping earlier text — the bug
/// this replaces. The default keeps one cumulative transcript (Quick Transcript's
/// behavior); the tradeoff is that audio may be transcribed by the system speech
/// service rather than strictly on-device.
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var partial: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Starts a session. Feed audio with `append(_:)`, read `partial` for the
    /// live text, and call `end()` to stop and get the full transcript.
    func begin() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Capture.Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition unavailable"])
        }
        task?.cancel(); task = nil
        partial = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        // Single long-lived task: `formattedString` is the full transcript so far
        // and keeps growing across pauses — nothing is dropped or overwritten.
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            DispatchQueue.main.async { self.partial = text }
        }
    }

    /// Forwards a captured audio buffer to the recognition request.
    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    /// Stops recognition and returns the full transcript.
    func end() -> String {
        request?.endAudio(); request = nil
        task?.finish(); task = nil
        return partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }
}
