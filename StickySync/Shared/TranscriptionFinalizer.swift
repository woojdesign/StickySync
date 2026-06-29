import Foundation

/// The swappable final-transcription engine — the seam the brief asks for.
///
/// v1 (`SpeechFinalizer`) trusts the on-device SFSpeech result, so capture and
/// finalize are the same text. Phase 3 adds `WhisperKitFinalizer`, which
/// re-transcribes the captured `.m4a` on the Neural Engine and silently
/// replaces the partial a beat later — the user never waits.
protocol TranscriptionFinalizer {
    func finalize(audioURL: URL?, fastPartial: String) async -> String
    /// Optional: warm the engine (load models) ahead of `finalize`, so it's
    /// ready by the time the user stops talking. No-op by default.
    func prewarm()
}

extension TranscriptionFinalizer {
    func prewarm() {}
}

/// Fallback finalizer: the fast SFSpeech partial *is* the final text. Used until
/// WhisperKit is ready, and as the graceful fallback when it can't run.
struct SpeechFinalizer: TranscriptionFinalizer {
    func finalize(audioURL: URL?, fastPartial: String) async -> String { fastPartial }
}
