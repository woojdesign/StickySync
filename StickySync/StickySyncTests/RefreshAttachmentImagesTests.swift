// RefreshAttachmentImagesTests.swift
//
// Pins the contract of `MarkdownTextStorage.refreshAttachmentImages()`:
// finds FFFCs whose NSTextAttachment.image is nil and re-loads them
// via attachmentLoader. Replaces the no-op 0.7.26 path that called
// substituteAttachmentReferences against a backing that no longer
// had any raw markdown to match.

import XCTest
import AppKit
@testable import StickySync

final class RefreshAttachmentImagesTests: XCTestCase {

    private func storage(loader: ((UUID) -> NSImage?)?) -> MarkdownTextStorage {
        let s = MarkdownTextStorage(
            baseFont: NSFont.systemFont(ofSize: 14),
            textColor: NSColor.black,
            markerColor: NSColor.gray)
        s.attachmentLoader = loader
        return s
    }

    private func smallPNG() -> Data {
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }

    /// When an FFFC was inserted with a nil image (because the
    /// attachment wasn't available yet) and the loader later starts
    /// returning data, refresh swaps the image in.
    func testRefresh_FillsInPreviouslyMissingImage() {
        var loaderAvailable = false
        let attachmentID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        let png = smallPNG()
        let s = storage { id in
            loaderAvailable && id == attachmentID ? NSImage(data: png) : nil
        }
        // Stand the FFFC up with no image — mirrors the post-open
        // state when the parent note arrived before the attachment.
        s.replaceCharacters(in: NSRange(location: 0, length: 0),
                            with: "![](attachment://\(attachmentID.uuidString))")
        s.substituteAttachmentReferences()  // raw → FFFC, image nil

        // Pre-condition: the attachment exists but its image is nil.
        let pre = s.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(pre)
        XCTAssertNil(pre?.image, "FFFC's image should be nil before the loader gets data")

        // Loader now has the data — refresh should pick it up.
        loaderAvailable = true
        s.refreshAttachmentImages()

        let post = s.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(post?.image, "refreshAttachmentImages must populate the image once the loader has it")
    }

    /// FFFCs whose image is ALREADY set should not be touched — refresh
    /// is meant to recover from the nil-image case, not churn working
    /// attachments.
    func testRefresh_SkipsAlreadyHydratedAttachments() {
        let attachmentID = UUID()
        let png = smallPNG()
        var loaderCalls = 0
        let s = storage { _ in
            loaderCalls += 1
            return NSImage(data: png)
        }
        s.replaceCharacters(in: NSRange(location: 0, length: 0),
                            with: "![](attachment://\(attachmentID.uuidString))")
        s.substituteAttachmentReferences()  // first call: hydrates the image
        let firstCallCount = loaderCalls

        // Now refresh — should be a no-op for the already-hydrated FFFC.
        s.refreshAttachmentImages()
        XCTAssertEqual(loaderCalls, firstCallCount,
                       "refresh must skip FFFCs whose image is already set")
    }

    /// When the loader still can't fetch the attachment, refresh leaves
    /// the placeholder alone — no crash, image stays nil.
    func testRefresh_NoOpWhenLoaderStillReturnsNil() {
        let attachmentID = UUID()
        let s = storage { _ in nil }
        s.replaceCharacters(in: NSRange(location: 0, length: 0),
                            with: "![](attachment://\(attachmentID.uuidString))")
        s.substituteAttachmentReferences()

        s.refreshAttachmentImages()  // must not crash

        let att = s.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(att)
        XCTAssertNil(att?.image)
    }
}
