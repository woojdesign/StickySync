// ArrangeStickies.swift
//
// "Window → Tidy Stickies" and "Window → Arrange in Grid" — two related
// commands with different opinions on what to do with your sticky-note
// placements.
//
// Tidy: respect what you've already arranged. Only fix the ones that
//   have drifted off-screen or are overlapping another sticky. The
//   thoughtful-coworker hand on a messy desk.
// Grid: full reset. Every visible sticky gets a fresh position on its
//   current screen. For the moments of genuine chaos.
//
// Hidden stickies are left hidden in both — you chose to hide them,
// arrange doesn't override that intent. Multi-monitor: each sticky stays
// on the screen it's currently on; we never gather across displays.

import AppKit
import NotesKit

@MainActor
enum ArrangeStickies {

    /// Animate every "out of place" sticky into a tidy cascade slot,
    /// leaving the rest alone.
    static func tidy(_ controllers: [NoteWindowController]) {
        let visible = controllers.filter { $0.window.isVisible }
        guard !visible.isEmpty else { return }

        // Group by current screen so the tidy cascade stays on the screen
        // each sticky is already on.
        let byScreen = group(visible)

        for (screen, group) in byScreen {
            let badlyPlaced = group.filter {
                isOutOfBounds($0.window, on: screen) ||
                overlapsSibling($0.window, siblings: group)
            }
            guard !badlyPlaced.isEmpty else { continue }

            var slot = startSlot(on: screen)
            for controller in badlyPlaced.sortedNewestFirst() {
                let size = controller.window.frame.size
                let origin = NSPoint(x: slot.x, y: slot.y - size.height)
                animate(controller.window, to: NSRect(origin: origin, size: size))
                slot = nextSlot(after: slot, on: screen)
            }
        }
    }

    /// Repack every visible sticky into a row-major grid on its current
    /// screen. Newest-modified land at the top-left.
    static func grid(_ controllers: [NoteWindowController]) {
        let visible = controllers.filter { $0.window.isVisible }
        guard !visible.isEmpty else { return }

        let byScreen = group(visible)

        for (screen, group) in byScreen {
            layoutGrid(group.sortedNewestFirst(), on: screen)
        }
    }

    // MARK: - Cascade

    /// Where the cascade starts on a screen — a margin in from the top-left.
    private static func startSlot(on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        return NSPoint(x: frame.minX + 24, y: frame.maxY - 24)
    }

    private static func nextSlot(after p: NSPoint, on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        let step: CGFloat = 28
        var next = NSPoint(x: p.x + step, y: p.y - step)
        if next.y < frame.minY + 200 {
            // Reached the bottom — wrap to a new column further right,
            // back near the top.
            next = NSPoint(x: p.x + step * 6, y: frame.maxY - 24)
        }
        if next.x > frame.maxX - 200 {
            // Reached the right edge — wrap back to the left edge near
            // the top. This is the "we have way too many stickies" path.
            next = startSlot(on: screen)
        }
        return next
    }

    // MARK: - Grid

    private static func layoutGrid(_ controllers: [NoteWindowController],
                                   on screen: NSScreen) {
        let frame = screen.visibleFrame
        let margin: CGFloat = 24
        let spacing: CGFloat = 14

        // Use the max sticky size as the cell so nothing crops. Natural
        // sticky default is 240×180; rounding up gives wiggle room for
        // user-resized notes without forcing a uniform crop.
        let maxWidth  = max(240, controllers.map { $0.window.frame.width  }.max() ?? 240)
        let maxHeight = max(180, controllers.map { $0.window.frame.height }.max() ?? 180)

        let cellW = maxWidth + spacing
        let cellH = maxHeight + spacing
        let cols = max(1, Int((frame.width - margin * 2) / cellW))

        for (index, controller) in controllers.enumerated() {
            let row = index / cols
            let col = index % cols
            let size = controller.window.frame.size

            let originX = frame.minX + margin + CGFloat(col) * cellW
            let originY = frame.maxY - margin - CGFloat(row + 1) * cellH

            // If we've run off the bottom of the screen, wrap by stacking
            // overflow back near the top-left in a tighter cascade. Not
            // ideal, but better than putting stickies off-screen.
            let safeOrigin: NSPoint
            if originY < frame.minY {
                let cascadeIdx = index - (rowCount(cols: cols, screen: frame, cellH: cellH) * cols)
                safeOrigin = NSPoint(
                    x: frame.minX + margin + CGFloat(cascadeIdx) * 18,
                    y: frame.maxY - margin - 18 - CGFloat(cascadeIdx) * 18 - size.height)
            } else {
                safeOrigin = NSPoint(x: originX, y: originY)
            }
            animate(controller.window, to: NSRect(origin: safeOrigin, size: size))
        }
    }

    private static func rowCount(cols: Int, screen: NSRect, cellH: CGFloat) -> Int {
        max(1, Int((screen.height - 48) / cellH))
    }

    // MARK: - Helpers

    private static func screen(for window: NSWindow) -> NSScreen {
        // The screen whose visibleFrame contains the center of the window,
        // falling back to the main screen if the window isn't on any
        // screen at all (i.e., it's drifted off).
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
        // "Out of bounds" = significantly off-screen, not just touching
        // the edge. Allow up to 40pt overhang before we move it.
        let frame = window.frame
        let visible = screen.visibleFrame.insetBy(dx: -40, dy: -40)
        return !visible.contains(frame)
    }

    private static func overlapsSibling(_ window: NSWindow,
                                        siblings: [NoteWindowController]) -> Bool {
        // Significant overlap: more than ~30% of the smaller of the two
        // window areas. Touching corners doesn't count.
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

    /// Animate the window into its new frame at the calm-motion duration.
    /// Uses NSAnimationContext so the move tracks AppKit's standard
    /// timing curve.
    private static func animate(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true, animate: true)
        }
    }
}

private extension Array where Element == NoteWindowController {
    /// Order stickies by modified-time, newest first — for cascades and
    /// grids alike, the most-recently-touched lands first so what you're
    /// working on stays close to the cursor.
    func sortedNewestFirst() -> [NoteWindowController] {
        sorted { $0.note.modifiedAt > $1.note.modifiedAt }
    }
}
