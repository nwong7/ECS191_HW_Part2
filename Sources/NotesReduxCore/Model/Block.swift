import Foundation

/// Paragraph style of a block.
public enum BlockStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case body
    case heading
    case subheading

    /// Outline depth: 1 for headings, 2 for subheadings, nil for body text.
    public var headingLevel: Int? {
        switch self {
        case .body: nil
        case .heading: 1
        case .subheading: 2
        }
    }

    public var isHeading: Bool { headingLevel != nil }
}

/// One paragraph of a note.
///
/// A note's content is an ordered list of blocks, each with a stable `id`. Section
/// identity is the `id` of the heading block, so renaming a heading or having two
/// headings with the same text never redirects an Add Entry insertion.
public struct Block: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var style: BlockStyle
    public var runs: [TextRun]

    public init(id: UUID = UUID(), style: BlockStyle = .body, runs: [TextRun]) {
        self.id = id
        self.style = style
        self.runs = runs.normalized()
    }

    /// Convenience for unformatted text. `text` must not contain line breaks.
    public init(id: UUID = UUID(), style: BlockStyle = .body, text: String) {
        self.init(id: id, style: style, runs: [TextRun(text)])
    }

    public var plainText: String { runs.plainText }

    /// True for empty or whitespace-only paragraphs, which act as visual separators.
    public var isBlank: Bool {
        plainText.allSatisfy(\.isWhitespace)
    }
}
