// ArrangeStickies.swift
//
// "Window → Tidy Stickies" and "Window → Arrange in Grid" — two commands
// with different opinions on what to do with your sticky-note placements.
//
// Tidy: respect what you've already placed. Only fix the stickies that
//   have drifted off-screen or are overlapping another sticky by more than
//   30% of their area. Drifted ones land in a tidy cascade slot on the
//   screen they were on. Hidden stickies untouched.
//
// Grid: full reset. Every visible sticky on each screen gets a fresh
//   row-major position. The layout math is factored into the pure
//   `GridLayout` enum so it's testable without standing up real
//   NSWindows.
//
// Architecture note (post-0.7.3): the visual layout math was getting
// tested only by "does it compile and look right when I eyeball it,"
// which the 0.7.3 ship demonstrated isn't enough. Split into:
//   - `GridLayout` (pure NSRect math) — covered by unit tests
//   - `apply(...)` (animates NSWindows) — verified by launching the app
// so a bad change in the math fails a test before it ever ships.

import AppKit
import NotesKit

@MainActor
enum ArrangeStickies {

    /// Move only the "out of place" stickies — off-screen or overlapping
    /// another sticky by more than 30% of their area — into empty space
    /// on their screen. Well-placed stickies are not touched. If there
    /// isn't enough empty space on screen for a badly-placed sticky, it
    /// falls back to the top-left corner (and accepts overlap rather
    /// than vanishing off-screen).
    static func tidy(_ controllers: [NoteWindowController]) {
        let visible = controllers.filter { $0.window.isVisible }
        guard !visible.isEmpty else { return }

        for (screen, group) in self.group(visible) {
            let badlyPlaced = group.filter {
                isOutOfBounds($0.window, on: screen) ||
                overlapsSibling($0.window, siblings: group)
            }
            guard !badlyPlaced.isEmpty else { continue }

            // The "fixed" set: every well-placed sticky on this screen,
            // whose position we promise not to touch.
            let badIDs = Set(badlyPlaced.map { ObjectIdentifier($0) })
            let fixed = group
                .filter { !badIDs.contains(ObjectIdentifier($0)) }
                .map { $0.window.frame }

            let toPlace = badlyPlaced.sortedNewestFirst()
            let sizes = toPlace.map { $0.window.frame.size }
            let positions = TidyLayout.places(
                sizesToPlace: sizes,
                avoiding: fixed,
                in: screen.visibleFrame)
            for (controller, target) in zip(toPlace, positions) {
                animate(controller.window, to: target)
            }
        }
    }

    /// Repack every visible sticky into a row-major grid on its current
    /// screen. Newest-modified lands at the top-left so what you're
    /// working on stays close to the cursor.
    static func grid(_ controllers: [NoteWindowController]) {
        let visible = controllers.filter { $0.window.isVisible }
        guard !visible.isEmpty else { return }

        for (screen, group) in group(visible) {
            let sortedControllers = group.sortedNewestFirst()
            let sizes = sortedControllers.map { $0.window.frame.size }
            let positions = GridLayout.frames(forSizes: sizes,
                                              in: screen.visibleFrame)
            for (controller, frame) in zip(sortedControllers, positions) {
                animate(controller.window, to: frame)
            }
        }
    }

    // MARK: - Helpers

    private static func screen(for window: NSWindow) -> NSScreen {
        // The screen whose visibleFrame contains the center of the window,
        // falling back to the main screen if the window isn't on any
        // screen (i.e., it has drifted off completely).
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        for screen in NSScreen.screens where screen.visibleFrame.contains(center) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private static func group(_ controllers: [NoteWindowController])
        -> [(NSScreen, [NoteWindowController])] {
        var result: [(NSScreen, [NoteWindowController])] = []
        for controller in controllers {
            let s = screen(for: controller.window)
            if let idx = result.firstIndex(where: { $0.0 === s }) {
                result[idx].1.append(controller)
            } else {
                result.append((s, [controller]))
            }
        }
        return result
    }

    private static func isOutOfBounds(_ window: NSWindow, on screen: NSScreen) -> Bool {
        // "Out of bounds" = significantly off-screen. Allow up to 40pt of
        // overhang before we move it; users dragging windows to a corner
        // shouldn't trigger Tidy.
        let frame = window.frame
        let visible = screen.visibleFrame.insetBy(dx: -40, dy: -40)
        return !visible.contains(frame)
    }

    private static func overlapsSibling(_ window: NSWindow,
                                        siblings: [NoteWindowController]) -> Bool {
        let frame = window.frame
        for other in siblings where other.window !== window {
            let inter = frame.intersection(other.window.frame)
            guard !inter.isNull, !inter.isEmpty else { continue }
            let smaller = min(frame.width * frame.height,
                              other.window.frame.width * other.window.frame.height)
            let ratio = (inter.width * inter.height) / max(smaller, 1)
            if ratio > 0.3 { return true }
        }
        return false
    }

    /// Animate the window to its new frame using `NSAnimationContext` —
    /// `window.animator().setFrame(_:display:)` honors the context's
    /// duration / timing, unlike the `setFrame(_:display:animate:)` form
    /// which uses NSWindow's own (and ignores ours).
    private static func animate(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

private extension Array where Element == NoteWindowController {
    /// Order stickies by modified-time, newest first.
    func sortedNewestFirst() -> [NoteWindowController] {
        sorted { $0.note.modifiedAt > $1.note.modifiedAt }
    }
}

// MARK: - Pure layout (testable)

/// The pure math for "Arrange in Grid", lifted out of the window-handling
/// code so it can be unit-tested without an NSWindow. Bin-packing-lite:
/// each row is laid out left-to-right at natural widths; we wrap to the
/// next row when the next sticky wouldn't fit. Within a row every sticky
/// aligns at the row's *top*; the row's height is the max sticky height
/// in that row (so the next row starts at the bottom of the tallest one).
/// Overflow rows clamp into the visible area at the bottom edge so
/// stickies stay reachable instead of vanishing off-screen.
/// First-fit empty-space search. Used by Tidy: each badly-placed
/// sticky finds the first on-screen position that doesn't overlap any
/// "fixed" rect (well-placed stickies you're leaving alone) or any
/// already-placed rect from this same call.
///
/// Scan order is top-down, left-to-right at a 20pt grid resolution —
/// fine enough to find space between awkwardly-placed stickies, coarse
/// enough that the scan is cheap for a few dozen rects.
enum TidyLayout {
    static let margin: CGFloat = 24
    static let step: CGFloat = 20

    /// Place each size from `sizesToPlace`, in order, in the first free
    /// position within `bounds` that doesn't overlap `fixed` rects or
    /// any previously-placed result. Falls back to the top-left if no
    /// free position fits — accepting overlap is better than vanishing
    /// off-screen.
    static func places(sizesToPlace: [NSSize],
                       avoiding fixed: [NSRect],
                       in bounds: NSRect) -> [NSRect] {
        var occupied = fixed
        var out: [NSRect] = []
        for size in sizesToPlace {
            let placed = firstFreePosition(for: size, in: bounds, avoiding: occupied)
            occupied.append(placed)
            out.append(placed)
        }
        return out
    }

    private static func firstFreePosition(for size: NSSize,
                                          in bounds: NSRect,
                                          avoiding occupied: [NSRect]) -> NSRect {
        let minX = bounds.minX + margin
        let maxX = bounds.maxX - margin - size.width
        let minY = bounds.minY + margin
        let maxY = bounds.maxY - margin - size.height
        guard maxX >= minX, maxY >= minY else {
            return NSRect(origin: NSPoint(x: bounds.minX + margin,
                                          y: bounds.maxY - margin - size.height),
                          size: size)
        }

        // Top-down, left-to-right.
        var y = maxY
        while y >= minY {
            var x = minX
            while x <= maxX {
                let candidate = NSRect(x: x, y: y, width: size.width, height: size.height)
                if !overlapsAny(candidate, occupied) {
                    return candidate
                }
                x += step
            }
            y -= step
        }
        // Couldn't fit — fall back to top-left.
        return NSRect(x: minX, y: maxY, width: size.width, height: size.height)
    }

    private static func overlapsAny(_ rect: NSRect, _ others: [NSRect]) -> Bool {
        for other in others {
            let inter = rect.intersection(other)
            if !inter.isNull && !inter.isEmpty { return true }
        }
        return false
    }
}

enum GridLayout {
    static let margin: CGFloat = 24
    static let spacing: CGFloat = 14

    /// Compute target frames for `sizes`, in the same order, fitting them
    /// row-major into `bounds`. `bounds` is a screen-space NSRect (i.e.,
    /// `NSScreen.visibleFrame` — bottom-left origin, Y increases upward).
    static func frames(forSizes sizes: [NSSize], in bounds: NSRect) -> [NSRect] {
        guard !sizes.isEmpty, bounds.width > margin * 2 else { return [] }
        let usableWidth = bounds.width - margin * 2

        var frames: [NSRect] = []
        var cursorX = bounds.minX + margin
        var topOfRow = bounds.maxY - margin
        var maxHeightInRow: CGFloat = 0
        let bottomLimit = bounds.minY + margin

        for size in sizes {
            // Would adding this sticky overflow the row's right edge?
            // If yes AND there's at least one sticky in the current row,
            // wrap. (If a single sticky is wider than the screen, we
            // still place it; it spills past the right edge.)
            let wouldOverflow = cursorX + size.width > bounds.minX + margin + usableWidth
            let rowHasItems = cursorX > bounds.minX + margin
            if wouldOverflow && rowHasItems {
                topOfRow -= (maxHeightInRow + spacing)
                cursorX = bounds.minX + margin
                maxHeightInRow = 0
            }

            // Top-aligned within the row: window's *top* sits at
            // `topOfRow`, so its bottom-left origin Y = topOfRow - height.
            // If we'd land below the screen, clamp to the bottom margin —
            // overflow stickies pile up there but stay visible.
            let originY = max(bottomLimit, topOfRow - size.height)
            frames.append(NSRect(
                x: cursorX,
                y: originY,
                width: size.width,
                height: size.height))

            cursorX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
        return frames
    }
}
