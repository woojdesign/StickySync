import Foundation

/// A single sticky note.
///
/// These are exactly the fields that should sync across devices. Notably
/// absent: window position and size. Those are device-local (your screens
/// differ), so they live in `NoteLayout` instead.
///
/// Offline-first details that matter for sync later:
/// - `id` is a client-generated UUID, so notes can be created offline and
///   still merge cleanly.
/// - Deletes are soft (`deletedAt` tombstone), so a delete on one device can
///   propagate instead of a row silently vanishing.
/// - `modifiedAt` gives last-writer-wins a field to compare.
public struct Note: Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: String
    /// Stable palette token (e.g. "butter"), never a positional index — so
    /// reordering the palette can't silently recolor existing notes.
    public var colorToken: String
    /// A curated `FontOption.id`. Curated (not "any installed font") so a note
    /// styled on one device renders identically on another.
    public var fontName: String
    public var fontSize: Double
    public var collapsed: Bool
    public let createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        content: String = "",
        colorToken: String = Palette.defaultToken,
        fontName: String = FontCatalog.defaultID,
        fontSize: Double = 15,
        collapsed: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.colorToken = colorToken
        self.fontName = fontName
        self.fontSize = fontSize
        self.collapsed = collapsed
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}
