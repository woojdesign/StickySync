# StickySync — testing discipline

The shape of regression testing as we move toward public release. Tight rules
that fit a solo-founder cadence; nothing here should slow a release by more
than a minute on the happy path.

## The one rule

**Every bug gets a failing test before it gets a fix.**

Workflow on a reported bug:

1. Reproduce by hand, just enough to be sure of the symptom.
2. Write a test that asserts the *correct* behavior.
3. Run the test. **Watch it fail.** This is the most important step — it
   proves the test would have caught the bug, and that it isn't accidentally
   asserting the buggy behavior. Skipping this is how "fake coverage"
   accumulates: tests that pass against broken code because they were
   written by the same person who wrote the broken code.
4. Fix the code.
5. Run the test. Watch it pass.
6. Commit the test and the fix in the same change so the failing-then-passing
   pair is reviewable in one diff.

This rule is non-negotiable. New bugs don't ship without a regression test
that locks them out.

## Layers, and what each one catches

### 1. NotesKit unit tests — `Tests/NotesKitTests/`

Pure-logic stuff that doesn't depend on UI or sync. Runs in milliseconds, no
fixtures. Today this covers:

- `PaletteTests` — slot canonicalization, legacy name → slot mapping, theme
  fallback, shipped-hex pinning for Original.
- `ReleaseNotesTests` — upgrader vs fresh-install vs patch-bump branches,
  dedup, sticky deletion preserving the won't-come-back invariant.
- `AttachmentTests` — `attachment://UUID` URL round-trip, scheme validation.
- `NoteStoreTests` — CRUD + soft-delete on both store backends.

Run with `cd ~/dev/noteskit && swift test`. Sub-second.

Add a test here whenever:
- A bug lives in NotesKit (most model bugs do).
- You add a public-API method to `NoteStore`, `Theme`, `Palette`,
  `ReleaseNotes`, or `Attachment`.
- You discover a non-obvious invariant worth pinning (e.g. "every theme must
  cover every slot" caught issues that would have silently broken theme
  switching).

### 2. Snapshot tests

Catches the class of bugs that compile-pass, build green, run zero-exit, and
*look wrong*. Recent examples that snapshot tests would have caught the
first time they shipped:

- Right-edge text bleed past the rounded corner (0.6.2 regression).
- The 0.6.0 release-sticky never dropping for upgraders.
- `restyleBacking` clobbering `.attachment` attributes — first paste rendered
  nothing.
- Resize grip default 8×8 hit zone with click-through to the window behind.

The library is `swift-snapshot-testing` (Pointfree, currently 1.19.2).
Industry usage: Airbnb's iOS app has ~30,000 snapshot tests, ~3× their
unit-test count; Spotify and Shopify are in the 1,000+ range each.

**Mac (live)**: `StickySyncTests` target. Today covers `NoteContentView` at
several sizes / themes / states. Run with `xcodebuild test -scheme StickySync`,
sub-second per case. Baselines live next to the tests under
`__Snapshots__/StickySyncTests/*.png` and are checked into the repo.

**iOS (live)**: `StickySyncMobileTests` target. Covers `NoteCard` (the
list-grid surface where the 0.5.21 thumbnail-render and preview-text bugs
landed). The sim's filesystem *does* mount the host source tree at the
same path, so baselines live next to the tests just like on Mac. The
real wrinkle: **SwiftUI's renderer on iOS Simulator has non-deterministic
anti-aliasing and subpixel rounding**, so strict byte-exact comparison
flaps on imperceptible differences. All iOS snapshots use
`precision: 0.99` + `perceptualPrecision: 0.97` (encapsulated in the
`assertCard(…)` helper) — tight enough to catch every visible regression
we've shipped, loose enough to survive renderer jitter. Bump those
numbers if a real visual diff starts reading as noise.

Snapshot-test cadence: every visual bug fixed adds a baseline. Don't try to
snapshot every view in the app — focus on the high-traffic surfaces (note
window, list grid, capture flow) where regressions actually hurt.

### 3. Manual smoke checklist — `docs/smoke-test.md`

The "feel" stuff that doesn't automate well: focus, animation, latency,
CloudKit sync between two real devices. Run by hand before each minor
release (0.6 → 0.7 → 1.0). Patches don't need the full run.

Lives in its own doc so we can keep it short and current.

## What we deliberately don't automate

- **CloudKit sync across real devices.** Too expensive to fake convincingly;
  two-device manual verification at release time is the ceiling.
- **Whisper transcription accuracy.** Non-deterministic; we own the
  pipeline (no-empty-discard, length-floor) but not the model.
- **Apple's window-management quirks.** Borderless windows, sleep/wake,
  Stage Manager — too platform-implementation-dependent.

## AI-assist patterns

The "AI writes code, AI tests its own code" loop has a well-known failure
mode: the same model that introduces a subtle bug doesn't catch it in the
review pass, because the systematic blind spot transfers. The most common
form: fix the production path, forget the matching test path; or vice
versa.

Counters we adopt:

1. **Write the test first, watch it fail, then fix.** This is the rule
   above. It mechanically rules out the "I wrote a test that passes against
   my broken code" failure mode because the failing assertion is in the
   commit message's diff.

2. **Treat snapshot diffs as required review.** Don't auto-accept on
   anyone's machine, including mine. Visual changes get eyeballed before
   the baseline updates. Otherwise the snapshot tests turn into rubber
   stamps.

3. **Use a different model for review when the stakes are high.** For
   schema changes, CloudKit migrations, or anything touching `NotesKit`'s
   public surface, run a second pass with `/ultrareview` or a fresh
   `claude -p` invocation that hasn't seen the implementation context.
   Cheap second opinion.

4. **One claim per test.** Each test should assert one behavior with a
   descriptive name (`testDeletedStickyDoesNotComeBackOnRelaunch`). Avoid
   "test everything about X" omnibus tests — when they fail, the cause is
   ambiguous and the next AI session that touches them will guess wrong.

5. **Pin shipped values explicitly.** Tests like
   `testOriginalThemeMatchesShippedHexValues` capture the
   "we promised users this exact hex" invariant. Any drift, even
   intentional, requires editing the test — which forces an explicit
   acknowledgement of the breaking change.

## What lands on the CI checklist next

In rough order:

- [x] Add `StickySyncTests` + `StickySyncMobileTests` Xcode test targets.
- [x] Pin `swift-snapshot-testing` as a dependency on both.
- [x] Seed Mac snapshot baselines for `NoteContentView` (7 cases).
- [x] Seed iOS snapshot baselines for `NoteCard` (4 cases) with the
      `precision: 0.99 / perceptualPrecision: 0.97` jitter tolerance.
- [ ] Write `docs/smoke-test.md` with the pre-release manual run.
- [ ] Add a GitHub Action that runs `swift test` (NotesKit) + the
      Mac snapshot tests on every push to `main`.
- [ ] `make test` in the repo root that runs everything in one command.
