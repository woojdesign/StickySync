# StickySync — operational guide

Auto-loaded by Claude Code in every session. Keep terse; link to scripts/code for details.

## Targets and layout

- **Mac app** (`StickySync` scheme, `wooj.StickySync`) — AppKit, menu bar, non-sandboxed. Distributed via direct download from GitHub Releases + Sparkle auto-update.
- **iOS app** (`StickySyncMobile` scheme, `wooj.StickySyncMobile`) — SwiftUI, iOS 26. Distributed via TestFlight; App Store path is future.
- **NotesKit** (`~/dev/noteskit`, tag 0.1.0) — model + CoreData/CloudKit, no UI. Linked as a local Swift package.
- **wooj-tokens** (`~/dev/wooj-tokens`, tag 0.2.0) — design tokens, **consumed only**. Edit via its `tokens.json` upstream, never in this repo.
- CloudKit container `iCloud.design.wooj.StickySync` shared by both apps.

## Process discipline (load-bearing — read this section)

These rules are how we ship in this repo. **Treat docs like code:** the
rules below are referenced from `docs/` because LLM-assisted coding makes
docs the source-of-truth on how we work. A drift between docs and code is
a real bug.

- **Every bug gets a failing test before it gets a fix.** Full rules:
  [`docs/testing.md`](docs/testing.md). The most-violated rule is #6 —
  read the exact failure message before guessing.
- **Tests ship in the same commit as the feature, not after.** If a code
  path is hard to test (window, audio engine, network), extract a pure
  helper for the decision logic and pin that. Pattern:
  `NoteWindowController.trailingReplacementRange` + `TrailingReplacementTests`
  (0.8.1) — turned a hard-to-test instance method into a pure static + a
  thin wrapper. Six tests in 80 lines.
- **Visually verify appearance before saying shipped.** Build-clean +
  rule-7-alive is necessary but not sufficient for UI changes. Take a
  screencap of the affected surface, open Read on the PNG, eyeball it
  before commit. When the UI genuinely can't be driven from CLI (paste,
  hover, modal, floating indicator that needs live state) — say so
  explicitly in the ship message and don't claim done. Sean's attention
  is the scarce resource.
- **MCP server lives in the running production app.** If `mcp__stickysync__*`
  tools return "Unable to connect," recover with
  `open /Applications/StickySync.app` (production app, not the Debug
  build) and retry. Don't ask Sean to reopen.
- **Docs live under `docs/`** (see `docs/README.md` for the map). Release
  notes live under `release-notes/` (pipeline artifact; intentionally
  separate).

## Release flows

Two separate flows. They share `scripts/release_notes.sh` for changelog generation but otherwise don't overlap.

### Mac → GitHub Release + Sparkle auto-update

```sh
./release.sh 0.3.2
```

What it does (see header of `release.sh`): polished changelog → notarize → EdDSA-sign → appcast → `gh release create`. Tag is `v0.3.2` (unprefixed, GH Release auto-creates from `gh release create`). Last shipped: **0.8.3**.

### iOS → TestFlight

```sh
./testflight.sh 0.3.2
```

What it does (see header of `testflight.sh`): polished changelog → archive → export IPA → `altool` upload → poll ASC for VALID → set "What to Test" via ASC API. Last shipped: **0.7.35 (191)** as `ios/v0.7.35`.

**Tag manually after a successful upload** (not yet automated):
```sh
git tag -a ios/v0.3.2 -m "iOS TestFlight 0.3.2" && git push origin ios/v0.3.2
```

Helpful flags:
- `--no-edit` — skip the `$EDITOR` pass on auto-generated notes
- `--keep-notes` — use existing `release-notes/<version>.md` instead of regenerating (lets you generate once, review/edit, then run upload)
- `--skip-upload` — build + write notes, don't upload (smoke-test the pipeline)

## Versioning + tags

- **Marketing version** is the arg to the script (`0.3.2`). It overrides `MARKETING_VERSION` at xcodebuild time.
- **Build number** is `git rev-list --count HEAD` — monotonic per commit; same on both platforms (this is fine, App Store Connect cares about per-version monotonicity, not cross-version).
- **Tags**:
  - Mac: `v0.3.1` (unprefixed). Existing convention; GH Release page lives at `releases/tag/v0.3.1`.
  - iOS: `ios/v0.3.1` (namespaced). Pure git pointer — no GH Release page. Useful so `git describe` finds the right "since" point for the next changelog.
- **`scripts/release_notes.sh` auto-filters by `--platform`** so Mac and iOS don't trip over each other's tags. Don't remove that filter logic.

## Auto-generated changelog

`scripts/release_notes.sh <version> --platform mac|ios|all` runs `git log <last-tag>..HEAD` and pipes commits through `claude -p` to produce platform-grouped, user-facing bullets, written to `release-notes/<version>.md`. The file is committed-friendly (tracked, kept across releases).

The commit-message style in this repo is already user-facing (e.g. `Mac: Share button on the note strip`), so the polish step is light. Both `release.sh` and `testflight.sh` call it, then embed the result into the GH release body / TestFlight "What to Test".

## One-time setup (for recovery / new machine)

Most of this is already done on Sean's main Mac. Recreate if you're on a fresh setup:

- **Mac signing**: Developer ID Application cert in keychain; notarytool profile `StickySync-notary` (`xcrun notarytool store-credentials`).
- **Sparkle**: EdDSA private key in keychain (`generate_keys`).
- **GitHub**: `gh auth login` for `woojdesign`.
- **App Store Connect API**: Team Key from ASC → Users and Access → Integrations. Three values in `~/.zshrc`:
  ```
  export ASC_KEY_ID=R2874DGSGN
  export ASC_ISSUER_ID=aaea5e06-a424-4055-81b4-49f47d252adb
  export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_R2874DGSGN.p8"
  ```
  The `.p8` is one-time-downloadable from Apple; back it up. The current key has **Admin** role on team BSPX8X9U4B — required for `xcodebuild -allowProvisioningUpdates` to regenerate provisioning profiles via API. (The previous CX7TU73U7D key had App Manager — works for upload but not for profile regeneration, which is what caused the 0.7.6 ship to fail until the role was upgraded.)
- **ASC Python deps**: venv at `~/.venvs/stickysync` with `PyJWT cryptography requests`. `testflight.sh` reads `$ASC_PYTHON` (defaults to that venv's python3).

## Gotchas — read before debugging these

- **CloudKit sync works.** It's eventual-consistency + push-driven; a "not syncing" report is almost always latency. Confirm via `/usr/bin/log stream --process <pid>` (the `log` alias is shadowed in Sean's zsh).
- **CloudKit Dev vs Prod**: Debug/Xcode builds → Development; notarized Release + TestFlight → Production. Don't cross-check data between them.
- **NotesKit model changes require Prod schema redeploy**: Dev build with `INIT_CK_SCHEMA=1` → `initializeCloudKitSchema` → Deploy in CloudKit Console. Skipping this silently breaks Prod sync.
- **bash 3.2 (macOS default)** is what `#!/usr/bin/env bash` resolves to. Quirks to avoid in scripts: no apostrophes inside `${VAR:?error message}` (bash 3.2 mis-parses them).
- **PTY exhaustion**: long Xcode sessions hit the 511 `kern.tty.ptmx_max` limit → "Pseudo Terminal Setup Error / Device not configured" on launch. Quit + reopen Xcode, or reboot.
- **Background bash shells don't load `~/.zshrc`** — pass `ASC_*` env vars inline when running `testflight.sh` from a non-interactive context.
- **First Beta App Review** (external testers, first build) takes 24–72h. Subsequent builds to the same group usually clear in minutes. Internal testers always skip review.

## Known open items

- **Bundle the WhisperKit model** into the iOS build: drag `WhisperModel/openai_whisper-base.en` into Xcode as a **folder reference** (blue, NOT a yellow group) on `StickySyncMobile`. Until done, first capture downloads ~150 MB before transcribing.
- Device tests still pending for: Action Button intent, Siri intent, WhisperKit accuracy, the `.caf` recording fix, polishing indicator, sync indicator, share/copy.

## Compile-check commands

```sh
# iOS (unsigned, fast)
xcodebuild build -project StickySync/StickySync.xcodeproj \
    -scheme StickySyncMobile -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/x CODE_SIGNING_ALLOWED=NO -quiet

# Mac (unsigned, fast)
xcodebuild build -project StickySync/StickySync.xcodeproj \
    -scheme StickySync -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath /tmp/x CODE_SIGNING_ALLOWED=NO -quiet
```
