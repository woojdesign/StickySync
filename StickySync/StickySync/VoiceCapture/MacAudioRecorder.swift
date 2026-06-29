// MacAudioRecorder.swift
//
// Mac-side audio capture for VoiceCapture. Drops the AVAudioSession
// setup the iOS recorder needs (Mac uses whatever the user picked as
// their system default input — AirPods route automatically when
// selected as the input device in System Settings → Sound).
//
// Same shape as the iOS AudioRecorder: AVAudioEngine + tap + write a
// `.caf` of the native PCM format. CAF was the iOS fix for the
// silent-empty-recording bug (deriving AAC settings from the float
// tap left write(from:) throwing every buffer); keep the same here
// so we read the same path with WhisperKit at finalize time.

import AVFoundation
import Combine

final class MacAudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording = false
    private(set) var fileURL: URL?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    @discardableResult
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws -> URL {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
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
        DispatchQueue.main.async { self.level = 0 }
    }

    /// Microphone permission. Mac uses AVCaptureDevice — there's no
    /// AVAudioApplication / AVAudioSession permission API on macOS.
    /// The app's Info.plist needs `NSMicrophoneUsageDescription`.
    static func requestMicPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { let s = data[i]; sum += s * s }
        let rms = sqrt(sum / Float(max(1, n)))
        let db = 20 * log10(max(rms, 0.000_01))
        let norm = max(0, min(1, (db + 50) / 45))
        DispatchQueue.main.async {
            self.level += (norm - self.level) * 0.3
        }
    }
}
