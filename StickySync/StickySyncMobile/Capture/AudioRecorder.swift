import AVFoundation
import Speech
import Combine

/// Captures microphone audio with AVAudioEngine. It does three jobs at once:
/// forwards live buffers to the speech recognizer for the on-screen partial,
/// writes a compressed `.m4a` to disk (for the WhisperKit final pass and the
/// Phase-2 audio attachment), and publishes a smoothed input level for the
/// breathing dot.
///
/// Slimmed from Quick Transcript's AudioRecorder — the FFT/visualizer is gone;
/// only an RMS level survives.
final class AudioRecorder: ObservableObject {
    /// 0…1, smoothed — drives the soft level indicator.
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording = false

    /// URL of the `.m4a` being written; kept for the final pass + attachment.
    private(set) var fileURL: URL?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    /// Begins recording. Each captured buffer is handed to `onBuffer` (for live
    /// transcription) as well as written to the `.m4a` and metered.
    @discardableResult
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws -> URL {
        let session = AVAudioSession.sharedInstance()
        // Allow Bluetooth input so AirPods (and other Bluetooth mics) get
        // picked up when connected — without `.allowBluetoothHFP`, iOS
        // falls back to the phone's built-in mic even with AirPods on,
        // forcing the user to hold the phone up to talk (Sean's
        // 0.7.27 report). The Hands-Free Profile is what carries the
        // mic signal from BT devices; without explicitly opting in,
        // AVAudioSession.record refuses to route through it. iOS 17
        // renamed `.allowBluetooth` → `.allowBluetoothHFP` (same
        // semantics, clearer name); we target iOS 26 so the new name
        // is what compiles.
        try session.setCategory(
            .record,
            mode: .default,
            options: [.allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // .m4a (AAC) destination in tmp. `.completeUnlessOpen` keeps writes
        // working if the device locks mid-capture.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        FileManager.default.createFile(
            atPath: url.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        // Write the tap's *native* PCM format. Deriving AAC settings (as before)
        // could leave the file's processing format mismatched against the float
        // tap buffers — `write(from:)` then throws, the `try?` silently drops every
        // buffer, and the recording is empty. WhisperKit then hallucinates a short
        // phrase ("here and i") over a perfectly good live transcript. Native PCM
        // in a CAF always matches the buffer, so nothing is dropped; WhisperKit
        // reads CAF fine. Bigger temp file, but it's transcribed once and tossed.
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        fileURL = url

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            onBuffer(buffer)
            try? self.file?.write(from: buffer)
            self.updateLevel(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        return url
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        DispatchQueue.main.async { self.level = 0 }
    }

    /// Microphone permission. Speech permission is requested separately.
    static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { let s = data[i]; sum += s * s }
        let rms = sqrt(sum / Float(max(1, n)))
        let db = 20 * log10(max(rms, 0.000_01))
        let norm = max(0, min(1, (db + 50) / 45))   // -50dB…-5dB → 0…1
        DispatchQueue.main.async {
            self.level += (norm - self.level) * 0.3   // ease toward the new value
        }
    }
}
