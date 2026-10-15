import Foundation

/// A heading-delimited region of a note, derived from its blocks.
///
/// Sections are never stored. They are recomputed from `Note.blocks` whenever
/// needed, so the outline panel and Add Entry picker cannot drift out of sync
/// with the document.
public struct Section: Identifiable, Hashable, Sendable {
    /// The heading block's id; this is the stable identity of the section.
    public let id: UUID
    /// 1 for headings, 2 for subheadings.
    public let level: Int
    /// Heading text as typed (may be empty).
    public let title: String
    /// Nearest preceding level-1 heading for subheadings, else nil.
    public let parentID: UUID?
    /// Index of the heading block in `Note.blocks`.
    public let headingIndex: Int
    /// The section's *own* content: blocks after the heading up to (not including)
    /// the next heading of any level. Subsections are not part of this range.
    public let contentRange: Range<Int>

    /// Title for UI, with a placeholder for empty headings.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Section" : trimmed
    }
}

public enum SectionIndex {
    /// All sections of `blocks`, in document order.
    public static func sections(in blocks: [Block]) -> [Section] {
        var result: [Section] = []
        var currentParent: UUID?

        for (index, block) in blocks.enumerated() {
            guard let level = block.style.headingLevel else { continue }
            let end = blocks[(index + 1)...].firstIndex(where: { $0.style.isHeading }) ?? blocks.endIndex
            if level == 1 { currentParent = block.id }
            result.append(Section(
                id: block.id,
                level: level,
                title: block.plainText,
                parentID: level == 1 ? nil : currentParent,
                headingIndex: index,
                contentRange: (index + 1)..<end
            ))
        }
        return result
    }

    public static func sections(in note: Note) -> [Section] {
        sections(in: note.blocks)
    }

    /// Human-readable path such as "Family › Cousins", used to tell apart
    /// sections that share a heading name.
    public static func path(for section: Section, in sections: [Section]) -> String {
        guard let parentID = section.parentID,
              let parent = sections.first(where: { $0.id == parentID })
        else { return section.displayTitle }
        return "\(parent.displayTitle) › \(section.displayTitle)"
    }

    /// The section containing block index `blockIndex` (the heading itself counts),
    /// or nil for content before the first heading. Used to highlight the outline.
    public static func section(containing blockIndex: Int, in sections: [Section]) -> Section? {
        sections.last(where: { $0.headingIndex <= blockIndex })
    }

    /// Section for a UTF-16 offset in editor text whose paragraphs are
    /// `paragraphs` (one per block, in order). Used to highlight the section at
    /// the top of the screen in the outline. Returns nil before the first
    /// heading, or if `paragraphs` and `blocks` are out of step.
    public static func section(
        atTextOffset offset: Int,
        paragraphs: [ParagraphRange],
        blocks: [Block]
    ) -> Section? {
        guard !paragraphs.isEmpty, paragraphs.count == blocks.count else { return nil }
        let index = ParagraphSplitter.index(containing: offset, in: paragraphs)
        return section(containing: index, in: sections(in: blocks))
    }
}
