// VoiceCaptureController.swift
//
// Coordinator for the Mac voice-to-sticky feature. Owns the hotkey,
// the audio recorder, and the live transcriber; wires them into the
// target sticky (key window if any, else fresh sticky).
//
// Phase 1 + 2 (this file's current scope):
//   - Hotkey tap-or-hold gesture (latch on quick tap, hold to talk)
//   - AVAudioEngine recording → CAF on disk
//   - SFSpeechRecognizer live partial transcripts appended into the
//     target sticky as the user talks
//   - WhisperKit final pass on the saved CAF replaces the SFSpeech
//     tail with higher-accuracy text a beat after stop (0.8.1)
//
// Targeting policy: if a StickySync sticky is the key window when the
// hotkey fires, capture appends into *that* sticky. Otherwise a fresh
// sticky is created and focused.

import AppKit
import AVFoundation
import Combine
import NotesKit
import Speech

final class VoiceCaptureController {

    private let hotkey = HotkeyController()
    // Lazy: AVAudioEngine + SFSpeechRecognizer init abort under XCTest
    // (no audio device + no speech-recognition context bootstrapped).
    // Real-use path always goes through handleStarted which accesses
    // both before any audio runs; tests of the polish-finalize layer
    // call finalizeSession directly and never touch them.
    private lazy var recorder = MacAudioRecorder()
    private lazy var transcriber = SpeechTranscriber()
    private let finalizer: TranscriptionFinalizer
    private let store: NoteStore

    var resolveKeyStickyID: (() -> UUID?)?
    var openNoteWindow: ((Note, _ focus: Bool) -> Void)?
    var appendToOpenNote: ((UUID, String) -> Void)?
    /// Replace `expected` at the end of the given sticky with `with` —
    /// or no-op if the user has typed past it. Used by the WhisperKit
    /// polish path. Set by AppDelegate.
    var replaceTrailingInNote: ((UUID, _ expected: String, _ with: String) -> Void)?
    /// Returns the NSWindow for a given sticky id, used to anchor the
    /// recording indicator. Set by AppDelegate.
    var windowForSticky: ((UUID) -> NSWindow?)?

    private let indicator = RecordingIndicator()

    /// Active session state. nil between captures.
    private var activeNoteID: UUID?
    /// Length of partial text already written into the sticky, so each
    /// SFSpeechRecognizer update only appends the *new* characters.
    private var committedPartialLength: Int = 0
    /// Anchor in the target sticky's content where this session's
    /// transcript begins — used as the cursor for live updates so we
    /// can reflow only this session's text, not the whole note.
    private var insertionAnchor: Int = 0
    private var partialSubscription: AnyCancellable?

    init(store: NoteStore,
         finalizer: TranscriptionFinalizer = WhisperKitFinalizer()) {
        self.store = store
        self.finalizer = finalizer
        hotkey.onEvent = { [weak self] event in
            switch event {
            case .started: self?.handleStarted()
            case .stopped: self?.handleStopped()
            }
        }
    }


    func start() { hotkey.register() }
    func stop()  { hotkey.unregister() }

    // MARK: - Hotkey handling

    private func handleStarted() {
        guard activeNoteID == nil else { return }   // ignore re-press during active session
        Task { @MainActor in
            // Resolve target sticky FIRST so we know the anchor before
            // any audio starts. New stickies start with empty content,
            // so the anchor is 0; existing stickies anchor at end-of-
            // current-text + a leading newline.
            // Targeting policy: only append into the key sticky.
            // Anything else (no sticky key, app backgrounded, sticky
            // window minimized) → fresh sticky. Sean's 0.7.39 follow-
            // up: "if we're not in the stickies we should default to
            // a new note rather than the last note." Pre-fix the
            // branch tried to bring the most-recently-modified open
            // sticky forward, which surprised the user — they
            // expected a fresh capture when they weren't actively in
            // a sticky.
            let separator = "\n"
            let targetID: UUID
            if let keyID = resolveKeyStickyID?() {
                targetID = keyID
                appendToOpenNote?(keyID, separator)
            } else {
                let note = Note(content: "", colorToken: "1")
                store.add(note)
                openNoteWindow?(note, true)
                targetID = note.id
            }
            // Surface the indicator anchored to whichever sticky we
            // ended up with so the user sees "I'm listening" even when
            // they're not looking at the editor (cursor elsewhere,
            // window in a different Space, etc.).
            if let anchorWindow = windowForSticky?(targetID) {
                indicator.showListening(over: anchorWindow)
            }
            activeNoteID = targetID
            committedPartialLength = 0
            insertionAnchor = 0  // we always append at end-of-storage from here

            // Permissions — both mic AND speech. iOS asks at app launch;
            // on Mac we lazy-ask the first time the user hits the hotkey.
            let micOK = await MacAudioRecorder.requestMicPermission()
            let speechOK = await SpeechTranscriber.requestAuthorization()
            guard micOK, speechOK else {
                appendToOpenNote?(targetID,
                    "[voice capture: \(micOK ? "speech" : "microphone") permission denied]")
                activeNoteID = nil
                return
            }

            do {
                try transcriber.begin()
            } catch {
                appendToOpenNote?(targetID, "[voice capture: \(error.localizedDescription)]")
                activeNoteID = nil
                return
            }

            // Kick off the WhisperKit model load now so it's ready by
            // the time the user stops talking — no extra wait at the
            // end. First call also triggers the ~150MB model download
            // if it isn't cached yet (~/Library/Application Support/…).
            finalizer.prewarm()

            // Stream live partials into the sticky as they grow. Use
            // Combine on the @Published `partial` (KVO doesn't observe
            // @Published — would need @objc dynamic for that). We
            // track the length already written so each callback
            // appends only the delta.
            partialSubscription = transcriber.$partial
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.flushPartial() }

            do {
                _ = try recorder.start(onBuffer: { [weak self] buffer in
                    self?.transcriber.append(buffer)
                })
            } catch {
                appendToOpenNote?(targetID, "[voice capture: \(error.localizedDescription)]")
                _ = transcriber.end()
                partialSubscription = nil
                activeNoteID = nil
            }
        }
    }

    private func handleStopped() {
        let audioURL = recorder.fileURL
        recorder.stop()
        let speechFinal = transcriber.end()
        partialSubscription = nil
        finalizeSession(speechFinal: speechFinal, audioURL: audioURL)
    }

    /// The post-recording orchestration — flushing the SFSpeech tail
    /// into the sticky and kicking off the WhisperKit polish pass.
    /// Internal so tests can pin the indicator state-transition
    /// contract (Listening → Polishing → none) without driving the
    /// real audio recorder / SFSpeech recognizer.
    func finalizeSession(speechFinal: String, audioURL: URL?) {
        guard let id = activeNoteID else { return }
        // Final flush: write the remainder if SFSpeechRecognizer's
        // last partial hadn't fully landed before we tore down.
        if speechFinal.count > committedPartialLength {
            let tail = String(speechFinal.suffix(speechFinal.count - committedPartialLength))
            appendToOpenNote?(id, tail)
        }
        activeNoteID = nil
        committedPartialLength = 0

        // No transcript → no polish to run; hide the indicator now.
        guard !speechFinal.isEmpty else {
            indicator.hide()
            return
        }

        // Transition Listening → Polishing instead of hiding. The
        // user sees a spinner + "Polishing…" until the WhisperKit pass
        // returns. Sean's 0.8.1 report: on first-run the model
        // download (~150MB) happens silently during polish and the
        // user assumes polish is broken because the SFSpeech text
        // never updates. The visible "Polishing…" state covers both
        // the transcribe wait (a couple seconds) AND the first-run
        // download wait (tens of seconds) without us needing to
        // distinguish them in copy.
        indicator.showPolishing()

        Task { [finalizer, replaceTrailingInNote, indicator] in
            let polished = await finalizer.finalize(audioURL: audioURL,
                                                    fastPartial: speechFinal)
            await MainActor.run {
                if polished != speechFinal {
                    replaceTrailingInNote?(id, speechFinal, polished)
                }
                // Inspect the finalizer's last outcome to differentiate
                // genuine no-improvement from silent error — Sean's 0.8.2
                // report flagged that they look identical to the user.
                // WhisperKitFinalizer is the only finalizer that
                // populates lastOutcome; for SpeechFinalizer (iOS fast
                // path) the cast just fails and we hide silently.
                if let wk = finalizer as? WhisperKitFinalizer {
                    switch wk.lastOutcome {
                    case .noAudio:
                        indicator.showFailed(detail: "no audio recorded")
                    case .modelLoadFailed:
                        indicator.showFailed(detail: "model loading…")
                    case .transcribeFailed:
                        indicator.showFailed(detail: "transcribe failed")
                    case .emptyTranscript:
                        indicator.showFailed(detail: "no speech detected")
                    case .polished, .identicalToSFSpeech, .notRunYet:
                        indicator.hide()
                    }
                } else {
                    indicator.hide()
                }
            }
        }
    }

    /// Called whenever `transcriber.partial` updates. Writes just the
    /// new tail (the characters past what we've already committed).
    private func flushPartial() {
        guard let id = activeNoteID else { return }
        let current = transcriber.partial
        guard current.count > committedPartialLength else { return }
        let tail = String(current.suffix(current.count - committedPartialLength))
        appendToOpenNote?(id, tail)
        committedPartialLength = current.count
    }
}
