# Capture → StickySync merge

Fold the standalone Capture app (`~/dev/capture`) into `StickySyncMobile` as a
**capture surface + App Intent**. Capture's notes already land in StickySync's
container, so it's functionally a StickySync surface, not a standalone product.

**Status:** Step 0 (token consolidation onto `~/dev/wooj-tokens` + `~/dev/noteskit`
packages, `WoojMotion` adopted) — **DONE** (commit `601719c`, branch
`extract-noteskit`). Phases 1–3 below pending.

**Decisions (locked):** WhisperKit in **Phase 3** (not skipped). `StickySyncMobile`
stays **Swift 5** (already is; matches Capture's `AVAudioEngine` audio path).
**Retire `~/dev/capture`** after. Permissions stay **lazy** (Capture already
requests mic/speech in `CaptureViewModel.begin()`, i.e. on first record, never at
launch).

## Source files (`~/dev/capture/Capture/`)
Relocate into a new `StickySync/StickySyncMobile/Capture/` group:
- Services: `AudioRecorder.swift`, `SpeechTranscriber.swift`, `NoteWriter.swift`, `TranscriptionFinalizer.swift` (the protocol)
- Views: `CaptureView.swift`, `ListeningView.swift`, `SavedView.swift`
- `ViewModels/CaptureViewModel.swift`
- Phase 2 only: `Intents/CaptureIntent.swift`
- **Do NOT bring:** `Support/Motion.swift` (we use package `WoojMotion`), `Services/WhisperKitFinalizer.swift` (Phase 3).

## Phase 1 — relocate + SFSpeech + index mic + lazy permissions
1. Copy the source files above (minus WhisperKitFinalizer + Motion) into `StickySyncMobile/Capture/`.
2. **Finalizer (no WhisperKit yet):** add a passthrough so capture doesn't depend on WhisperKit —
   ```swift
   struct PassthroughFinalizer: TranscriptionFinalizer {
       func prewarm() {}
       func finalize(audioURL: URL?, fastPartial: String) async -> String { fastPartial }
   }
   ```
   In `CaptureViewModel`, change `= WhisperKitFinalizer()` → `= PassthroughFinalizer()`.
3. **Motion API:** the Views/VM use `WoojMotion.settle`/`.calm`; swap to `WoojMotion.settle.animation` / `WoojMotion.calm.animation` (canonical `WoojSpring`/`WoojTimingCurve` API — same as NoteEditorView already does). Each Capture file needs `import WoojTokens`.
4. `SavedView`: drop the "in StickySync" hint (you're already here) → just the checkmark / "Saved".
5. **Info.plist** (`StickySyncMobile`): add `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `UIBackgroundModes: [audio]` (copy the strings from `~/dev/capture/Capture/Support/Info.plist`). No new entitlements — iCloud container is already present.
6. **Wire the index mic:** in `NotesListView`'s `captureBar`, add a mic button beside "New note" → `fullScreenCover` hosting `CaptureView(vm: CaptureViewModel())`. VM `startIfNeeded()` on appear → `begin()` requests mic/speech (lazy). On `saved`, the VM auto-dismisses; the new note appears in the list via `NotesModel.onChange`.
7. **Verify:** build (Swift 5, no WhisperKit); launch → **no** permission prompt; tap mic → prompt (first time) → speak → saved note lands in the list.

## Phase 2 — App Intent (instant entry)
1. Bring `CaptureIntent` + `CaptureShortcuts` into `StickySyncMobile` (retitle phrases to StickySync).
2. Root view: observe `.startCapture` (when running) and present the capture sheet; cold launch presents capture on launch when the intent fired. `openAppWhenRun` brings StickySync forward → present capture directly, bypassing the list.
3. Test: Action Button / "Hey Siri, capture with StickySync".

## Phase 3 — WhisperKit
1. Add SPM package `https://github.com/argmaxinc/WhisperKit` from `0.9.0` to `StickySyncMobile`.
2. Bring `WhisperKitFinalizer.swift`; swap the VM's finalizer back to `WhisperKitFinalizer()`.
3. (Downloads a Core ML model — real binary weight, hence last.)

## After
Retire `~/dev/capture` (archive/delete). The shared-container handoff becomes
plain intra-app data. Both apps already share `~/dev/noteskit` + `~/dev/wooj-tokens`.
