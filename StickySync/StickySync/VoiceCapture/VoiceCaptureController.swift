// VoiceCaptureController.swift
//
// Coordinator for the Mac voice-to-sticky feature. Owns the hotkey,
// the audio recorder, and the live transcriber; wires them into the
// target sticky (key window if any, else fresh sticky).
//
// Phase 1 + 2 (this file's current scope):
//   - Hotkey hold-to-record gesture
//   - AVAudioEngine recording → CAF on disk
//   - SFSpeechRecognizer live partial transcripts appended into the
//     target sticky as the user talks
//
// Phase 3 (planned): WhisperKit final pass on the saved CAF, replacing
// SFSpeechRecognizer's output with higher-accuracy text on stop.
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
    private let recorder = MacAudioRecorder()
    private let transcriber = SpeechTranscriber()
    private let store: NoteStore

    var resolveKeyStickyID: (() -> UUID?)?
    var openNoteWindow: ((Note, _ focus: Bool) -> Void)?
    var appendToOpenNote: ((UUID, String) -> Void)?

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

    init(store: NoteStore) {
        self.store = store
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
        guard let id = activeNoteID else { return }
        recorder.stop()
        let final = transcriber.end()
        partialSubscription = nil
        // Final flush: write the remainder if SFSpeechRecognizer's
        // last partial hadn't fully landed before we tore down. The
        // `final` string is the complete transcript; subtract what
        // we've already written to compute the tail.
        if final.count > committedPartialLength {
            let tail = String(final.suffix(final.count - committedPartialLength))
            appendToOpenNote?(id, tail)
        }
        activeNoteID = nil
        committedPartialLength = 0
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
