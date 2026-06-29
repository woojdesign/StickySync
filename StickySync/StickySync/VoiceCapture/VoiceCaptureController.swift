// VoiceCaptureController.swift
//
// Coordinator for the Mac voice-to-sticky feature. Owns the hotkey
// and (in later phases) the audio recorder + Whisper transcription.
//
// Phase 1 (this file's scope): wire hotkey events to sticky creation /
// append. No audio yet — placeholder text markers prove the trigger
// pipeline end-to-end so the audio + transcription layers in Phase
// 2 / 3 can drop into a known-working integration.
//
// Targeting policy: if a StickySync sticky is the key window when the
// hotkey fires, the capture appends into *that* sticky. Otherwise a
// new sticky is created and focused. This is the only context
// modifier (per the design conversation 2026-06-28) — "talk to the
// thing in front of you," no separate UI gate.

import AppKit
import NotesKit

final class VoiceCaptureController {

    private let hotkey = HotkeyController()
    private let store: NoteStore

    /// Set by AppDelegate so we can target the key NoteWindowController.
    /// Returns the note id of the currently key sticky window, or nil
    /// when something else (or nothing) is key.
    var resolveKeyStickyID: (() -> UUID?)?

    /// Set by AppDelegate so we can open a freshly-created sticky as a
    /// window (otherwise the new note exists in the store but no UI
    /// surfaces it).
    var openNoteWindow: ((Note, _ focus: Bool) -> Void)?

    /// Set by AppDelegate so we can append text into an existing sticky
    /// window's editor — going through the controller lets the editor's
    /// own save / sync path handle persistence (vs. mutating the note
    /// record behind the editor's back).
    var appendToOpenNote: ((UUID, String) -> Void)?

    /// Active session's target note id. nil between captures. The
    /// hotkey state machine guarantees at most one session at a time
    /// (started ⇒ stopped ⇒ started ⇒ stopped …).
    private var activeNoteID: UUID?
    private var sessionStartedAt: Date?

    init(store: NoteStore) {
        self.store = store
        hotkey.onEvent = { [weak self] event in
            switch event {
            case .started: self?.handleStarted()
            case .stopped: self?.handleStopped()
            }
        }
    }

    func start() {
        hotkey.register()
    }

    func stop() {
        hotkey.unregister()
    }

    // MARK: - Hotkey handling

    private func handleStarted() {
        sessionStartedAt = Date()
        if let keyID = resolveKeyStickyID?() {
            activeNoteID = keyID
            appendToOpenNote?(keyID, listeningMarker())
        } else {
            let note = Note(content: listeningMarker(), colorToken: "1")
            store.add(note)
            activeNoteID = note.id
            openNoteWindow?(note, true)
        }
    }

    private func handleStopped() {
        guard let id = activeNoteID else { return }
        let duration = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        appendToOpenNote?(id, stoppedMarker(duration: duration))
        activeNoteID = nil
        sessionStartedAt = nil
    }

    // MARK: - Placeholder markers (Phase 1 only)

    /// Visible text while a recording session is active. Phase 2 swaps
    /// this for the AudioRecorder's "Listening…" UI and Phase 3 replaces
    /// it with live partial transcripts from WhisperKit.
    private func listeningMarker() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "\n🎤 listening… (\(f.string(from: Date())))"
    }

    private func stoppedMarker(duration: TimeInterval) -> String {
        let ms = Int(duration * 1000)
        return " ← stopped (\(ms)ms)"
    }
}
