import Foundation
import Speech
import Combine

/// On-device live transcription via `SFSpeechRecognizer`. Drives the immediate
/// on-screen partial — and, in v1, the final text too (until WhisperKit takes
/// over the final pass in Phase 3). `requiresOnDeviceRecognition` is forced on:
/// nothing leaves the device.
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var partial: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var best: String = ""

    /// Starts a recognition session and returns the request to feed audio into.
    func begin() throws -> SFSpeechAudioBufferRecognitionRequest {
        task?.cancel(); task = nil
        partial = ""; best = ""

        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Capture.Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition unavailable"])
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // The core guardrail. `supportsOnDeviceRecognition` guards locales that
        // lack an on-device model, so we never silently fall back to the network.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.best = text
                DispatchQueue.main.async { self.partial = text }
            }
            if error != nil || (result?.isFinal ?? false) { self.task = nil }
        }
        return req
    }

    /// Ends the session and returns the best transcript captured so far.
    func end() -> String {
        request?.endAudio()
        request = nil
        task?.finish()
        return best.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }
}
