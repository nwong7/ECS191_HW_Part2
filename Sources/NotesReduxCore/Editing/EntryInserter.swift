import Foundation

/// Where an Add Entry should go.
public enum EntryDestination: Hashable, Sendable {
    /// End of the own content of the section whose heading block has this id.
    case section(UUID)
    /// End of the note; used for notes without headings.
    case endOfNote
}

public enum InsertionError: Error, Equatable, Sendable {
    case emptyEntry
    case noteNotFound
    case sectionNotFound
    case nothingToUndo

    /// Short message suitable for an alert.
    public var message: String {
        switch self {
        case .emptyEntry: "The entry is empty. Type something to add."
        case .noteNotFound: "That note no longer exists. It may have been deleted."
        case .sectionNotFound: "That section no longer exists. Its heading may have been removed or changed to normal text."
        case .nothingToUndo: "The entry can no longer be undone because it was already changed or removed."
        }
    }
}

/// Proof of a successful insertion, used for "View in Note" and "Undo".
public struct InsertionReceipt: Hashable, Sendable {
    public let noteID: UUID
    public let destination: EntryDestination
    /// Ids of the new blocks, in order. Exactly these are removed by undo.
    public let insertedBlockIDs: [UUID]
    /// Index in `Note.blocks` of the first inserted block.
    public let insertionIndex: Int
}

/// Pure functions that implement Add Entry.
///
/// They take a `Note` value and return a new one, touching nothing else, so a
/// failed or cancelled insertion cannot partially modify anything. Persisting the
/// result is the caller's job (see `NotesLibrary.addEntry`).
public enum EntryInserter {

    /// Returns `note` with `entry` inserted at `destination`.
    ///
    /// Placement rule for a section: directly after the last non-blank block of the
    /// section's own content (or directly after the heading if it has none). Trailing
    /// blank separator lines, subheadings and later sections stay after the entry.
    public static func inserting(
        _ entry: Entry,
        into note: Note,
        at destination: EntryDestination,
        now: Date = Date()
    ) throws(InsertionError) -> (note: Note, receipt: InsertionReceipt) {
        guard !entry.isEmpty else { throw .emptyEntry }
        let index = try insertionIndex(for: destination, in: note.blocks)

        let newBlocks = entry.lines.map { Block(style: .body, runs: $0) }
        var updated = note
        updated.blocks.insert(contentsOf: newBlocks, at: index)
        updated.modifiedAt = now

        let receipt = InsertionReceipt(
            noteID: note.id,
            destination: destination,
            insertedBlockIDs: newBlocks.map(\.id),
            insertionIndex: index
        )
        return (updated, receipt)
    }

    /// Block index at which new content for `destination` is inserted.
    public static func insertionIndex(
        for destination: EntryDestination,
        in blocks: [Block]
    ) throws(InsertionError) -> Int {
        switch destination {
        case .endOfNote:
            // After the last non-blank block so trailing blank lines stay trailing.
            return (blocks.lastIndex(where: { !$0.isBlank }).map { $0 + 1 }) ?? blocks.endIndex

        case .section(let headingID):
            // Lookup is by block id only; heading text is never matched.
            guard let section = SectionIndex.sections(in: blocks).first(where: { $0.id == headingID })
            else { throw .sectionNotFound }
            let lastContent = section.contentRange.last(where: { !blocks[$0].isBlank })
            return (lastContent ?? section.headingIndex) + 1
        }
    }

    /// Removes exactly the blocks created by `receipt`.
    ///
    /// Refuses (throws `.nothingToUndo`) if any of those blocks is gone, so undo
    /// never deletes something the user has since replaced.
    public static func undoing(
        _ receipt: InsertionReceipt,
        in note: Note,
        now: Date = Date()
    ) throws(InsertionError) -> Note {
        guard note.id == receipt.noteID else { throw .nothingToUndo }
        let ids = Set(receipt.insertedBlockIDs)
        let present = Set(note.blocks.lazy.map(\.id).filter(ids.contains))
        guard !ids.isEmpty, present == ids else { throw .nothingToUndo }

        var updated = note
        updated.blocks.removeAll { ids.contains($0.id) }
        updated.modifiedAt = now
        return updated
    }
}
