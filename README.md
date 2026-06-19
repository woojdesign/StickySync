# StickySync

A modern, sync-ready sticky-notes app for macOS. Like the built-in Stickies,
but with a cleaner UI, on-note color and font controls, and an architecture
built so cross-device sync drops in without a rewrite.

## Status

**Phase 1 — local, runs today.** Everything works on one Mac, no account, no
network. The data model and the store seam are already sync-shaped, so Phase 2
(iCloud sync) is an additive change, not a rewrite.

## Run it

```sh
swift run --package-path ~/Developer/StickySync
# or, after a build:
~/Developer/StickySync/.build/debug/StickySync
```

Or open it in Xcode: `open ~/Developer/StickySync/Package.swift`.

### What you can do

- **New note** — ⌘N. Notes cascade onto the screen.
- **Edit** — just type. Plain text, full undo/redo, cut/copy/paste.
- **Recolor** — hover a note, click the palette button, pick a color. Seven
  curated tints, each with a readable text color in both light and dark mode.
- **Change font** — hover, click **Aa**, pick a font (previewed in itself) and
  nudge the size. Curated, platform-safe fonts only.
- **Move** — drag the title bar.
- **Resize** — drag any edge.
- **Roll up / down** — double-click the title bar.
- **Delete** — hover, click ✕ (a recoverable soft-delete).

Notes, colors, fonts, sizes, collapse state, and per-window geometry persist
across launches.

### Where data lives

`~/Library/Application Support/StickySync/store.json`

## Architecture

```
Package.swift
Sources/
  NotesKit/        ← platform-agnostic: Foundation only, no AppKit
    Note            synced fields (id, content, colorToken, fontName, …)
    NoteLayout      device-local window geometry (never synced)
    Palette         curated colors as light/dark hex pairs
    FontCatalog     curated, cross-device-safe fonts
    NoteStore       the persistence protocol — the seam sync slots into
    JSONNoteStore   Phase 1 local implementation
  StickySync/      ← the macOS app (AppKit)
    main / AppDelegate         app + window lifecycle, menu
    NoteWindow / NoteContentView   borderless rounded note, hover chrome
    NoteWindowController       binds a note to its window and the store
    ColorPaletteController     on-note color popover
    FontPickerController       on-note font + size popover
    Appearance                 NotesKit data → NSColor / NSFont
```

The rule that makes everything later cheap: **`NotesKit` imports only
Foundation.** A future iPhone app and the CloudKit layer reuse it untouched —
only the UI is platform-specific.

Two deliberate decisions baked into the model:

- **Window position/size is device-local** (`NoteLayout`), never synced — your
  screens differ. Content, color, font, and collapse state sync.
- **Colors and fonts are stored as stable tokens, not values/indexes.** Lets
  light/dark mode remap colors, keeps the palette reorder-safe, and keeps a
  note rendering identically on every device.

## Roadmap

### Phase 2 — iCloud sync (needs an Apple Developer account)

Sync is gated on two things that can't be done from a plain SwiftPM binary:
an Apple Developer Program membership ($99/yr) and a code-signed app bundle
with the iCloud capability. The code change itself is small because of the
`NoteStore` seam.

1. In Xcode, make a macOS **app target** (or add an app target to this package)
   and add `NotesKit` as a local package dependency.
2. Signing & Capabilities → add **iCloud** → **CloudKit**, create a container
   like `iCloud.design.wooj.StickySync`. This writes the entitlements
   (`com.apple.developer.icloud-container-identifiers`, `icloud-services`,
   plus `aps-environment` for push).
3. Add a Core Data model (programmatic or `.xcdatamodeld`) with a `CDNote`
   entity mirroring `Note`, and write a `CloudKitNoteStore: NoteStore` backed
   by `NSPersistentCloudKitContainer`. CloudKit constraints: every attribute
   optional or defaulted, no unique constraints.
4. Point `AppDelegate.store` at `CloudKitNoteStore()` instead of
   `JSONNoteStore()`. Nothing else in the UI changes. Fire `onChange` when the
   container posts `NSPersistentStoreRemoteChange` so incoming edits refresh
   open windows (the hook is already wired in `AppDelegate.reconcileWindows`).

Conflict policy for v1: last-writer-wins per note (we already stamp
`modifiedAt`). Single user across your own devices rarely edits the same note
within seconds, so this is fine. Character-level CRDT merging is a later option
only if live collaborative editing is ever wanted.

### Phase 3 — iPhone

Add an iOS app target on top of the same `NotesKit`. Sync is already there via
CloudKit. iOS has no floating desktop windows, so the phone UI is a grid/list
(plus a home-screen widget) — a new view layer, not new data.

### Phase 4 — sharing

`NSPersistentCloudKitContainer` supports a shared database scope. Adding "share
this note with someone" is enabling that scope + a share sheet — a supported
extension point, not a re-architecture.
