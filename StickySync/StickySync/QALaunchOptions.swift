// QALaunchOptions.swift
//
// 0.11.0: parse DEBUG-only launch args that let me screencap the
// sticky chrome deterministically before shipping. When we're not
// in a Debug build (or the flag isn't present), returns nil and
// AppDelegate proceeds as normal.
//
// Usage:
//
//   open /path/to/StickySync.app --args --qa-sticky
//   open ... --args --qa-sticky --qa-sticky-color 3 --qa-sticky-text "hello"
//   open ... --args --qa-sticky --qa-chrome-visible
//   open ... --args --qa-sticky --qa-frame 200,200,400,300
//
// The QASticky option makes AppDelegate:
//   1. Skip the welcome-sticky and existing-notes restoration
//   2. Create one sticky with the given content + color
//   3. Position it at a known screen-relative frame (default:
//      (100, 100, 400, 300) in bottom-left coord system)
//   4. Optionally force the chrome hover state visible so tests
//      can screencap the icons without simulating hover

import Foundation
import AppKit

struct QALaunchOptions {
    /// The content of the seeded sticky. Multi-line supported.
    var text: String
    /// Palette slot 1…7. Default 1 (yellow).
    var colorSlot: Int
    /// Window frame in screen coords. Bottom-left origin (AppKit).
    var frame: NSRect
    /// If true, chrome is forced visible so screencaps show the
    /// icons + band without needing to simulate hover.
    var chromeVisible: Bool

    /// Returns options if `--qa-sticky` was passed AND we're in a
    /// DEBUG build. Otherwise returns nil.
    static func fromCommandLine() -> QALaunchOptions? {
        #if DEBUG
        return parse(args: CommandLine.arguments)
        #else
        return nil
        #endif
    }

    /// Pure parser — testable without touching CommandLine.
    /// Returns nil if `--qa-sticky` is not present in args.
    static func parse(args: [String]) -> QALaunchOptions? {
        guard args.contains("--qa-sticky") else { return nil }

        var opts = QALaunchOptions(
            text: "QA sticky\nline two\nline three",
            colorSlot: 1,
            frame: NSRect(x: 100, y: 100, width: 400, height: 300),
            chromeVisible: false
        )

        if let idx = args.firstIndex(of: "--qa-sticky-color"),
           idx + 1 < args.count,
           let slot = Int(args[idx + 1]), (1...7).contains(slot) {
            opts.colorSlot = slot
        }
        if let idx = args.firstIndex(of: "--qa-sticky-text"),
           idx + 1 < args.count {
            opts.text = args[idx + 1]
        }
        if let idx = args.firstIndex(of: "--qa-frame"),
           idx + 1 < args.count {
            let parts = args[idx + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                opts.frame = NSRect(x: parts[0], y: parts[1],
                                    width: parts[2], height: parts[3])
            }
        }
        if args.contains("--qa-chrome-visible") {
            opts.chromeVisible = true
        }
        return opts
    }
}
