// StickySyncMobileTests.swift
//
// Snapshot baselines for the iOS list grid (NoteCard). The surface where
// the 0.5.21 thumbnail-render and preview-text bugs landed.
//
// All iOS snapshots use `precision: 0.99` + `perceptualPrecision: 0.97`
// because SwiftUI's renderer on iOS Simulator has non-determinism in
// anti-aliasing and subpixel rounding — strict byte-exact comparison
// fails on minor render wiggles that are visually identical. The
// thresholds here are tight enough to catch every visible regression
// we've shipped (the 90pt thumb appearing, the shared indicator, the
// image-Markdown strip in the preview) without flapping on
// imperceptible differences.

import XCTest
import SwiftUI
import SnapshotTesting
import NotesKit
@testable import StickySyncMobile

/// Minimal NoteStore stub — `attachments(for:)` returns empty so NoteCard's
/// `.task` doesn't try to load thumbnails (separate baselines cover the
/// with-thumbnail path with a real-bytes injection).
@MainActor
final class EmptyStubStore: NoteStore {
    var onChange: (() -> Void)?
    private var notes: [Note] = []

    func allNotes() -> [Note] { notes }
    func note(id: UUID) -> Note? { notes.first { $0.id == id } }
    func layout(for id: UUID) -> NoteLayout? { nil }
    func add(_ note: Note) { notes.append(note) }
    func update(_ note: Note) {}
    func setLayout(_ layout: NoteLayout) {}
    func softDelete(id: UUID) {}

    func attachments(for noteID: UUID) -> [Attachment] { [] }
    func attachment(id: UUID) -> Attachment? { nil }
    func addImageAttachment(for noteID: UUID, imageData: Data, mimeType: String,
                            originalFilename: String?, altText: String?) -> Attachment? { nil }
    func update(_ attachment: Attachment) {}
    func softDeleteAttachment(id: UUID) {}
    func imageData(for attachmentID: UUID) -> Data? { nil }
    func thumbnailData(for attachmentID: UUID) -> Data? { nil }
}

final class NoteCardSnapshotTests: XCTestCase {

    /// Wrapped view at a fixed size with a stable system-background fill,
    /// so the snapshot frame doesn't fluctuate with the device's default
    /// background or trait collection.
    @MainActor
    private func wrap(_ card: NoteCard) -> some View {
        card
            .frame(width: 180, height: 200)
            .background(Color(.systemBackground))
    }

    /// Single source of truth for iOS snapshot thresholds — bumped here
    /// if a real visual regression starts looking like noise (or vice
    /// versa). Tight enough to catch the regressions we've actually
    /// shipped; loose enough to ignore renderer jitter.
    @MainActor
    private func assertCard(_ view: some View,
                            file: StaticString = #filePath,
                            testName: String = #function,
                            line: UInt = #line) {
        assertSnapshot(of: view,
                       as: .image(precision: 0.99,
                                  perceptualPrecision: 0.97,
                                  layout: .fixed(width: 180, height: 200)),
                       file: file,
                       testName: testName,
                       line: line)
    }

    // MARK: - Baselines

    @MainActor
    func testEmptyNote() {
        let card = NoteCard(note: Note(content: "", colorToken: "1"),
                            isShared: false,
                            store: EmptyStubStore())
        assertCard(wrap(card))
    }

    @MainActor
    func testShortTextNote() {
        let card = NoteCard(note: Note(content: "buy milk\noranges\nflowers",
                                       colorToken: "1"),
                            isShared: false,
                            store: EmptyStubStore())
        assertCard(wrap(card))
    }

    @MainActor
    func testSharedIndicator() {
        let card = NoteCard(note: Note(content: "shared with mom",
                                       colorToken: "3"),
                            isShared: true,
                            store: EmptyStubStore())
        assertCard(wrap(card))
    }

    /// Pins the per-slot text-color behavior added 0.7.8: when the user
    /// picks a theme whose slot has a *dark* background (e.g. Bold Berry's
    /// Burgundy on slot 7), the card's preview text must render with the
    /// palette's white-ink pair, not the wooj reading color (which is
    /// hardcoded dark and reads as illegible black-on-near-black).
    @MainActor
    func testDarkSlot_UsesPaletteWhiteText() {
        ThemeStore.shared.select("bold-berry")
        defer { ThemeStore.shared.select("original") }
        let card = NoteCard(
            note: Note(content: "Should render in white ink — Burgundy slot.",
                       colorToken: "7"),
            store: EmptyStubStore())
        assertCard(wrap(card))
    }

    /// Regression test for the 0.5.21 preview-text strip pass: image
    /// Markdown refs (`![alt](attachment://UUID)`) should be replaced with
    /// the alt text in the card preview, not show the raw URL.
    @MainActor
    func testImageMarkdownStrippedFromPreview() {
        let id = UUID().uuidString
        let body = """
        Some context
        ![sketch](attachment://\(id))
        and a few words after
        """
        let card = NoteCard(note: Note(content: body, colorToken: "1"),
                            isShared: false,
                            store: EmptyStubStore())
        assertCard(wrap(card))
    }

    /// Regression test for the 0.7.10 "orphan thumb" bug: deleting the
    /// `![](attachment://UUID)` text from a sticky orphans the underlying
    /// CDAttachment (it isn't soft-deleted, just unreferenced). The card
    /// must not show an orphan as a thumb — only attachments whose UUID
    /// is still mentioned in note.content count as covers.
    @MainActor
    func testOrphanAttachment_NotShownAsThumb() {
        let card = NoteCard(
            note: Note(content: "Used to have an image; now just text.",
                       colorToken: "1"),
            isShared: false,
            store: OrphanAttachmentStubStore())
        assertCard(wrap(card))
    }
}

/// Returns one non-deleted attachment for any note, with image bytes.
/// Mimics the post-bug state: the editor deleted the markdown reference
/// but the CDAttachment row survived as an orphan.
@MainActor
final class OrphanAttachmentStubStore: NoteStore {
    var onChange: (() -> Void)?

    func allNotes() -> [Note] { [] }
    func note(id: UUID) -> Note? { nil }
    func layout(for id: UUID) -> NoteLayout? { nil }
    func add(_ note: Note) {}
    func update(_ note: Note) {}
    func setLayout(_ layout: NoteLayout) {}
    func softDelete(id: UUID) {}

    func attachments(for noteID: UUID) -> [Attachment] {
        // Single non-deleted attachment — but the test note's content
        // doesn't reference this UUID, so it should be ignored.
        [Attachment(noteID: noteID, mimeType: "image/png")]
    }
    func attachment(id: UUID) -> Attachment? { nil }
    func addImageAttachment(for noteID: UUID, imageData: Data, mimeType: String,
                            originalFilename: String?, altText: String?) -> Attachment? { nil }
    func update(_ attachment: Attachment) {}
    func softDeleteAttachment(id: UUID) {}
    // Return a 1×1 PNG so if the gate fails, the thumb path actually
    // produces a UIImage and the snapshot regression is visible.
    func imageData(for attachmentID: UUID) -> Data? { Self.onePixelPNG }
    func thumbnailData(for attachmentID: UUID) -> Data? { nil }

    /// Smallest valid PNG bytes — a 1×1 black pixel.
    static let onePixelPNG: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    ])
}
