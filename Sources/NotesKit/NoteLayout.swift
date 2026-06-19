import Foundation

/// Device-local window geometry for a note.
///
/// Deliberately NOT part of `Note`: a note's position on a 6K display is
/// meaningless on a laptop (or a future iPhone), so geometry stays local to
/// each device and is never synced. Each device remembers where its own copy
/// of a given note sits.
///
/// `expandedHeight` remembers how tall the note was before it was collapsed,
/// so expanding restores the right size.
public struct NoteLayout: Codable, Equatable {
    public var noteID: UUID
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var expandedHeight: Double?

    public init(
        noteID: UUID,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        expandedHeight: Double? = nil
    ) {
        self.noteID = noteID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.expandedHeight = expandedHeight
    }
}
