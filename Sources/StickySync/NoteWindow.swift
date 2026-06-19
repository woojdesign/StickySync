import AppKit

/// Borderless windows refuse to become key by default, which would block text
/// editing. Overriding these lets the note take focus and accept typing.
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
