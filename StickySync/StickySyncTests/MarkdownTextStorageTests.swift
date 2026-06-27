// MarkdownTextStorageTests.swift
//
// Regression coverage for the deferred-invalidation race that crashed 0.7.3
// at launch. Sequence:
//   1. Note window opens, `textView.string = note.content` fires a
//      processEditing with a large `touched` range. Invalidation is
//      deferred to the next runloop via DispatchQueue.main.async.
//   2. NoteWindowController then calls substituteAttachmentReferences(),
//      which collapses each `![](attachment://UUID)` source span into a
//      single FFFC character — shrinking the backing.
//   3. The deferred async from step 1 fires with the now-stale `touched`
//      range; AppKit's `_extendedCharRangeForInvalidation` peeks past the
//      edge and reads off the end of the shrunk NSString.
//
// Fix: clamp the captured range to the current backing length inside the
// deferred block. This test exercises the same shrink-after-defer path
// and would have crashed without the fix.

import XCTest
import AppKit
@testable import StickySync
import NotesKit

final class MarkdownTextStorageTests: XCTestCase {

    @MainActor
    func testProcessEditing_AfterShrinkingSubstitution_DoesNotCrash() {
        let storage = MarkdownTextStorage(
            baseFont: .systemFont(ofSize: 14),
            textColor: .labelColor,
            markerColor: NSColor.labelColor.markerVariant()
        )
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        // Content that includes an attachment-Markdown reference.
        // substituteAttachmentReferences will collapse the 60+ chars of
        // the reference span into a single FFFC, leaving the captured
        // `touched` range from the initial replaceCharacters' processEditing
        // pointing past the end of the now-shrunk backing.
        let uuid = UUID().uuidString
        let body = """
        Some leading paragraph that establishes the lineRange.
        ![dabi](attachment://\(uuid))
        And a trailing paragraph after the reference span.
        """
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: body)
        storage.substituteAttachmentReferences()

        // The bug was inside the deferred Dispatch.async block scheduled
        // by processEditing — drain the main runloop briefly so it fires.
        // Without the clamp, this is where AppKit raises NSInvalidArgumentException.
        let drain = expectation(description: "main runloop drains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            drain.fulfill()
        }
        wait(for: [drain], timeout: 1.0)

        // If we got here, the deferred invalidation didn't crash.
        // The actual length should be roughly the prose chars + 1 FFFC for
        // the attachment span — a real shrink from the original markdown.
        XCTAssertLessThan(storage.length, body.count,
                          "substituteAttachmentReferences should have shrunk the backing")
    }

    @MainActor
    func testProcessEditing_PlainTextChange_StillWorks() {
        // Belt and braces: the clamp shouldn't break the common case.
        let storage = MarkdownTextStorage(
            baseFont: .systemFont(ofSize: 14),
            textColor: .labelColor,
            markerColor: NSColor.labelColor.markerVariant()
        )
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 200, height: 200))
        layoutManager.addTextContainer(container)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "hello world")

        let drain = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        XCTAssertEqual(storage.string, "hello world")
    }
}
