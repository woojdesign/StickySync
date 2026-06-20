import Foundation

/// Device-local window state for a note: geometry plus whether it's currently
/// shown on THIS device.
///
/// Deliberately NOT part of `Note`: where a note sits — and whether it's open
/// on a given screen — is meaningless across devices, so it stays local and is
/// never synced. Closing a note hides it here (`hidden = true`) without
/// deleting it or affecting your other Macs.
///
/// `expandedHeight` remembers how tall the note was before it was collapsed.
public struct NoteLayout: Codable, Equatable {
    public var noteID: UUID
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var expandedHeight: Double?
    /// Closed (hidden) on this device. Device-local; never synced.
    public var hidden: Bool

    public init(
        noteID: UUID,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        expandedHeight: Double? = nil,
        hidden: Bool = false
    ) {
        self.noteID = noteID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.expandedHeight = expandedHeight
        self.hidden = hidden
    }

    /// Tolerant decoding so layouts written before `hidden`/`expandedHeight`
    /// existed still load (missing keys default rather than throw).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try c.decode(UUID.self, forKey: .noteID)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}
