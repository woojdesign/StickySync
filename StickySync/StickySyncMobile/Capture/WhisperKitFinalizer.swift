import Foundation
import WhisperKit

/// The high-fidelity final pass: re-transcribes the captured `.m4a` on the
/// Neural Engine with WhisperKit (base.en), then silently replaces the live
/// SFSpeech partial. On any failure — model still loading, missing model,
/// decode error — it returns the fast partial, so a cold start never costs the
/// user their note.
final class WhisperKitFinalizer: TranscriptionFinalizer {
    /// base.en: ~145MB, English, fully offline once present. Bundle the model
    /// folder (`openai_whisper-base.en`) into the app to make the first capture
    /// instant; otherwise WhisperKit downloads it once and caches it.
    private static let modelName = "base.en"
    private static let bundledModelFolder = "openai_whisper-base.en"

    // Memoized single instance — the first access starts the expensive load.
    private var loader: Task<WhisperKit, Error>?

    /// Start loading the model early (when listening begins) so it's ready by
    /// the time the user stops.
    func prewarm() { _ = pipeline() }

    func finalize(audioURL: URL?, fastPartial: String) async -> String {
        guard let audioURL else { return fastPartial }
        do {
            let whisper = try await pipeline().value
            let results: [TranscriptionResult] = try await whisper.transcribe(audioPath: audioURL.path)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fastPartial : text
        } catch {
            return fastPartial
        }
    }

    private func pipeline() -> Task<WhisperKit, Error> {
        if let loader { return loader }
        let task = Task<WhisperKit, Error> {
            let config: WhisperKitConfig
            if let folder = Bundle.main.url(forResource: Self.bundledModelFolder, withExtension: nil)?.path {
                // Bundled model — no download, works offline on first launch.
                config = WhisperKitConfig(model: Self.modelName, modelFolder: folder)
            } else {
                // Download once from the WhisperKit model repo, then cache.
                config = WhisperKitConfig(model: Self.modelName)
            }
            return try await WhisperKit(config)
        }
        loader = task
        return task
    }
}
