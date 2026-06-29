import Foundation
import OSLog
import WhisperKit

/// The high-fidelity final pass: re-transcribes the captured `.m4a` on the
/// Neural Engine with WhisperKit (base.en), then silently replaces the live
/// SFSpeech partial. Every decision point now logs via `SyncLog.voice` so
/// we can reconstruct what happened — pre-0.8.3 the catch swallowed all
/// errors and "Whisper agreed with SFSpeech" looked identical to "Whisper
/// errored on model load" to the user (Sean's 0.8.2 report).
///
/// Query the trail (Mac):
///   log show --predicate 'subsystem == "wooj.voice"' --last 10m
final class WhisperKitFinalizer: TranscriptionFinalizer {
    /// base.en: ~145MB, English, fully offline once present. Bundle the model
    /// folder (`openai_whisper-base.en`) into the app to make the first capture
    /// instant; otherwise WhisperKit downloads it once and caches it.
    private static let modelName = "base.en"
    private static let bundledModelFolder = "openai_whisper-base.en"

    // Memoized single instance — the first access starts the expensive load.
    private var loader: Task<WhisperKit, Error>?

    /// Outcome of the last `finalize` call — exposed so the controller can
    /// surface failures (visible indicator state, marker line) rather than
    /// the user seeing "polish didn't change anything" indistinguishable
    /// from a real silent error.
    enum LastOutcome: Equatable {
        case notRunYet
        case noAudio                     // audioURL was nil
        case modelLoadFailed(String)     // pipeline().value threw
        case transcribeFailed(String)    // whisper.transcribe threw
        case emptyTranscript             // succeeded but text was whitespace
        case identicalToSFSpeech         // Whisper agreed with SFSpeech
        case polished                    // text actually changed
    }
    private(set) var lastOutcome: LastOutcome = .notRunYet

    /// Start loading the model early (when listening begins) so it's ready by
    /// the time the user stops.
    func prewarm() {
        SyncLog.voice.info("prewarm: starting model load")
        _ = pipeline()
    }

    func finalize(audioURL: URL?, fastPartial: String) async -> String {
        guard let audioURL else {
            SyncLog.voice.error("finalize: audioURL nil → returning fast partial")
            lastOutcome = .noAudio
            return fastPartial
        }
        let exists = FileManager.default.fileExists(atPath: audioURL.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        SyncLog.voice.info("finalize: audio at \(audioURL.path, privacy: .public) exists=\(exists, privacy: .public) bytes=\(size, privacy: .public)")

        let whisper: WhisperKit
        do {
            SyncLog.voice.info("finalize: awaiting model pipeline…")
            whisper = try await pipeline().value
            SyncLog.voice.info("finalize: model ready")
        } catch {
            let msg = "\(error)"
            SyncLog.voice.error("finalize: model load FAILED: \(msg, privacy: .public)")
            lastOutcome = .modelLoadFailed(msg)
            return fastPartial
        }

        let results: [TranscriptionResult]
        do {
            SyncLog.voice.info("finalize: transcribing…")
            results = try await whisper.transcribe(audioPath: audioURL.path)
            SyncLog.voice.info("finalize: transcribed \(results.count, privacy: .public) segments")
        } catch {
            let msg = "\(error)"
            SyncLog.voice.error("finalize: transcribe FAILED: \(msg, privacy: .public)")
            lastOutcome = .transcribeFailed(msg)
            return fastPartial
        }

        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            SyncLog.voice.notice("finalize: empty transcript → returning fast partial")
            lastOutcome = .emptyTranscript
            return fastPartial
        }
        if text == fastPartial {
            SyncLog.voice.notice("finalize: Whisper text == SFSpeech text — no change")
            lastOutcome = .identicalToSFSpeech
            return text
        }
        SyncLog.voice.info("finalize: polished — SFSpeech \(fastPartial.count, privacy: .public)ch → Whisper \(text.count, privacy: .public)ch")
        lastOutcome = .polished
        return text
    }

    private func pipeline() -> Task<WhisperKit, Error> {
        if let loader { return loader }
        let task = Task<WhisperKit, Error> {
            let config: WhisperKitConfig
            if let folder = Bundle.main.url(forResource: Self.bundledModelFolder, withExtension: nil)?.path {
                SyncLog.voice.info("pipeline: bundled model at \(folder, privacy: .public)")
                config = WhisperKitConfig(model: Self.modelName, modelFolder: folder)
            } else {
                SyncLog.voice.info("pipeline: no bundled model → WhisperKit will download/cache")
                config = WhisperKitConfig(model: Self.modelName)
            }
            return try await WhisperKit(config)
        }
        loader = task
        return task
    }
}
