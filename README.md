# StickySync

A modern, sync-ready sticky-notes app for macOS — like the built-in Stickies,
but with iCloud sync across your devices, on-note color and font controls, and
a cleaner UI.

## Status

- **Local app** — done: borderless rounded notes, hover-revealed color palette
  and font/size pickers, drag / resize / double-click-to-roll-up, soft-delete,
  persistence.
- **iCloud sync** — working: notes sync across your Macs via CloudKit
  (`NSPersistentCloudKitContainer`). Window geometry stays device-local.

## Layout

```
.
├── Package.swift          # NotesKit Swift package (model + stores)
├── Sources/NotesKit/      # platform-agnostic: Note, NoteStore, palette, fonts
├── Tests/NotesKitTests/   # round-trip tests (swift test)
└── StickySync/            # the macOS app (Xcode project)
    ├── StickySync.xcodeproj
    └── StickySync/        # AppKit UI; links NotesKit; carries the entitlements
```

`NotesKit` is a Swift package (Foundation + CoreData, no UI framework) so the
Mac app — and a future iOS app — reuse it unchanged. Persistence sits behind a
`NoteStore` protocol with two implementations: `JSONNoteStore` (local) and
`CloudKitNoteStore` (Core Data + CloudKit). The Xcode app links the `NotesKit`
library product and supplies the AppKit UI.

Two deliberate model decisions: window geometry is device-local (never synced);
colors and fonts are stored as stable tokens (not values/indexes) for light/dark
theming, palette reorder-safety, and cross-device font fidelity.

## Build & run

```sh
open StickySync/StickySync.xcodeproj   # then ⌘R, destination: My Mac
```

For sync, the app target needs (already configured):
- **iCloud → CloudKit** capability, container `iCloud.design.wooj.StickySync`
- **Push Notifications** capability
- **App Sandbox → Outgoing Connections (Client)**
- the **`CLOUDKIT`** flag in *Active Compilation Conditions* (Debug + Release).
  Without it the app falls back to the local `JSONNoteStore`.
- the Mac signed into iCloud.

Test the model layer without Xcode:

```sh
swift test     # NotesKit round-trip tests
```

## Distributing it to someone else

A direct-download Mac app must be **signed with a Developer ID Application
certificate and notarized by Apple**, or Gatekeeper blocks it. High level:

1. Make sure `CLOUDKIT` is set for the **Release** config too.
2. **Deploy the CloudKit schema to Production** (CloudKit Console → Deploy
   Schema Changes) — distributed builds use the Production environment, not
   Development.
3. Xcode → **Product ▸ Archive** → **Distribute App ▸ Direct Distribution**
   (Developer ID). Xcode signs, uploads for notarization, and staples.
4. Export the notarized `.app`, zip or wrap it in a `.dmg`, and host it.
5. Each recipient signs into their own iCloud account; their notes sync across
   their own devices (shared notes would be a later CloudKit-sharing feature).

The Mac App Store is a separate path (App Store Connect + review).

## Roadmap

- iPhone app on the same `NotesKit`.
- CloudKit sharing — share a note with another person.
