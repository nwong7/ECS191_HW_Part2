import Foundation

/// One choice in the Add Entry section picker.
public struct DestinationOption: Identifiable, Hashable, Sendable {
    public let destination: EntryDestination
    /// Heading text, or "End of Note".
    public let title: String
    /// Disambiguating path such as "Family › Cousins".
    public let path: String
    /// 0 for end of note, 1 for headings, 2 for subheadings (used for indentation).
    public let level: Int

    public var id: EntryDestination { destination }
}

/// Builds Add Entry destinations from a note's current structure.
///
/// Recomputed from the note every time, so a picker that is open while the
/// note changes never offers a section that no longer exists.
public enum AddEntryDestinations {
    public static let endOfNoteTitle = "End of Note"

    /// Every section in document order, followed by "End of Note".
    public static func options(for note: Note) -> [DestinationOption] {
        let sections = SectionIndex.sections(in: note)
        let sectionOptions = sections.map { section in
            DestinationOption(
                destination: .section(section.id),
                title: section.displayTitle,
                path: SectionIndex.path(for: section, in: sections),
                level: section.level)
        }
        let end = DestinationOption(destination: .endOfNote, title: endOfNoteTitle, path: endOfNoteTitle, level: 0)
        return sectionOptions + [end]
    }

    /// Pre-selected destination. End of note is always valid, so the default
    /// can never point at a missing section; users pick a section explicitly.
    public static func defaultDestination(for note: Note) -> EntryDestination {
        .endOfNote
    }

    /// True if `destination` can currently receive an entry in `note`.
    public static func isValid(_ destination: EntryDestination, in note: Note) -> Bool {
        options(for: note).contains { $0.destination == destination }
    }

    /// Human-readable target such as "Birthdays › Friends" for confirmations,
    /// or nil if the section no longer exists.
    public static func describe(_ destination: EntryDestination, in note: Note) -> String? {
        guard let option = options(for: note).first(where: { $0.destination == destination }) else { return nil }
        return "\(note.displayTitle) › \(option.path)"
    }
}
