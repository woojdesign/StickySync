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
    private weak var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Begins recording. Pass the recognizer's request so each captured buffer
    /// is forwarded for live transcription (or nil for audio-only).
    @discardableResult
    func start(feeding request: SFSpeechAudioBufferRecognitionRequest?) throws -> URL {
        recognitionRequest = request

        let session = AVAudioSession.sharedInstance()
        // Built-in mic is enough for v1; routing AirPods/Bluetooth input is a
        // later polish (the option constant churned across iOS versions).
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // .m4a (AAC) destination in tmp. `.completeUnlessOpen` keeps writes
        // working if the device locks mid-capture.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        FileManager.default.createFile(
            atPath: url.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        // Derive AAC settings from the input format so the file's processing
        // format matches the tap buffers (otherwise `write(from:)` fails).
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
        fileURL = url

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
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
        recognitionRequest = nil
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
