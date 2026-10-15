import Foundation

/// Preset tint for a note's grid icon.
public enum NoteColor: String, Codable, CaseIterable, Hashable, Sendable {
    case yellow, orange, red, pink, purple, blue, teal, green, gray
}

/// Visual customisation shown in the grid view. Presets only in v1.
public struct NoteAppearance: Codable, Hashable, Sendable {
    /// A preset emoji, or nil to show the title's first letter.
    public var icon: String?
    public var color: NoteColor

    public init(icon: String? = nil, color: NoteColor = .yellow) {
        self.icon = icon
        self.color = color
    }

    public static let presetIcons = ["📝", "📚", "🎂", "🍳", "💡", "✅", "🎵", "✈️", "💼", "❤️", "⭐️", "🔖"]
}

/// A single note: an explicit title plus an ordered list of paragraph blocks.
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var blocks: [Block]
    public var createdAt: Date
    public var modifiedAt: Date
    public var appearance: NoteAppearance

    public init(
        id: UUID = UUID(),
        title: String = "",
        blocks: [Block] = [],
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        appearance: NoteAppearance = NoteAppearance()
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.appearance = appearance
    }

    /// Title for lists and pickers; untitled notes still need a visible label.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    /// First non-blank line of content, used as the list subtitle.
    public var preview: String {
        blocks.first(where: { !$0.isBlank })?.plainText
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Whole note as plain text, one block per line. Used for search.
    public var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    /// Case- and diacritic-insensitive match on title or body.
    public func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return title.range(of: q, options: options) != nil
            || plainText.range(of: q, options: options) != nil
    }

    // Decoding tolerates a missing `appearance` so older files keep loading.
    private enum CodingKeys: String, CodingKey {
        case id, title, blocks, createdAt, modifiedAt, appearance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        appearance = try c.decodeIfPresent(NoteAppearance.self, forKey: .appearance) ?? NoteAppearance()
    }
}
