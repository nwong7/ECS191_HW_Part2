import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct EntryInserterTests {

    /// The worked example from Project_Notes.txt, checked line by line.
    @Test func projectNotesBirthdayExample() throws {
        let before = SampleNotes.birthdays()
        let friends = heading(before, "Friends")

        let (after, receipt) = try EntryInserter.inserting(
            Entry(plainText: " Josh B - 5/28/2004"), into: before, at: .section(friends.id))

        #expect(lines(after) == [
            "Family", "Dad [1/1/1111]", "Mom [1/1/1111]", "",
            "Friends", "Lucas H - 1/1/1111", "Emma S - 1/1/1111", "Josh B - 5/28/2004", "",
            "School", "Froilan F - 1/1/1111 ", "",
            "Work", "Gregory R - 1/1/1111",
        ])
        // Every pre-existing block is still present, identical, and in order.
        #expect(after.blocks.filter { !receipt.insertedBlockIDs.contains($0.id) } == before.blocks)
        #expect(receipt.insertionIndex == 7)
        #expect(after.blocks[7].style == .body)
    }

    @Test func emptySectionInsertsDirectlyAfterHeading() throws {
        let note = Note(blocks: [
            Block(style: .heading, text: "A"),
            Block(text: ""),
            Block(style: .heading, text: "B"),
        ])
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "x"), into: note, at: .section(note.blocks[0].id))
        #expect(lines(after) == ["A", "x", "", "B"])
    }

    @Test func entryGoesBeforeFirstSubheading() throws {
        let note = Note(blocks: [
            Block(style: .heading, text: "Family"),
            Block(text: "Dad"),
            Block(style: .subheading, text: "Cousins"),
            Block(text: "Ann"),
        ])
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "Mom"), into: note, at: .section(note.blocks[0].id))
        #expect(lines(after) == ["Family", "Dad", "Mom", "Cousins", "Ann"])

        let (after2, _) = try EntryInserter.inserting(Entry(plainText: "Bob"), into: note, at: .section(note.blocks[2].id))
        #expect(lines(after2) == ["Family", "Dad", "Cousins", "Ann", "Bob"])
    }

    @Test func lastSectionWithoutTrailingBlankAppendsAtEnd() throws {
        let note = SampleNotes.birthdays()
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "Pat"), into: note, at: .section(heading(note, "Work").id))
        #expect(lines(after).suffix(3) == ["Work", "Gregory R - 1/1/1111", "Pat"])
    }

    @Test func multiLineEntryPreservesLineBreaksAndInnerBlankLines() throws {
        let note = SampleNotes.birthdays()
        let entry = Entry(plainText: "\n\nLine one\r\n\n  indented line\nlast  \n\n")
        let (after, receipt) = try EntryInserter.inserting(entry, into: note, at: .section(heading(note, "School").id))
        #expect(receipt.insertedBlockIDs.count == 4)
        #expect(lines(after)[8...15] == ["School", "Froilan F - 1/1/1111 ", "Line one", "", "  indented line", "last", "", "Work"])
    }

    @Test func inlineFormattingIsPreserved() throws {
        let note = SampleNotes.birthdays()
        let entry = Entry(runs: [TextRun("Josh B", traits: [.bold]), TextRun(" - 5/28/2004\nnote", traits: [.italic])])
        let (after, receipt) = try EntryInserter.inserting(entry, into: note, at: .section(heading(note, "Friends").id))
        let inserted = after.blocks[receipt.insertionIndex]
        #expect(inserted.runs == [TextRun("Josh B", traits: [.bold]), TextRun(" - 5/28/2004", traits: [.italic])])
        #expect(after.blocks[receipt.insertionIndex + 1].runs == [TextRun("note", traits: [.italic])])
    }

    @Test(arguments: ["", "   ", "\n\n", " \t\r\n "])
    func emptyEntryIsRejected(text: String) {
        let note = SampleNotes.birthdays()
        #expect(throws: InsertionError.emptyEntry) {
            try EntryInserter.inserting(Entry(plainText: text), into: note, at: .section(heading(note, "Friends").id))
        }
    }

    @Test func unknownSectionIsRejected() {
        let note = SampleNotes.birthdays()
        #expect(throws: InsertionError.sectionNotFound) {
            try EntryInserter.inserting(Entry(plainText: "x"), into: note, at: .section(UUID()))
        }
    }

    @Test func headingDemotedToBodyIsNoLongerADestination() {
        var note = SampleNotes.birthdays()
        let friends = heading(note, "Friends")
        note.blocks[4].style = .body
        #expect(throws: InsertionError.sectionNotFound) {
            try EntryInserter.inserting(Entry(plainText: "x"), into: note, at: .section(friends.id))
        }
    }

    @Test func renamedHeadingIsStillFoundById() throws {
        var note = SampleNotes.birthdays()
        let friends = heading(note, "Friends")
        note.blocks[4].runs = [TextRun("Close Friends")]
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "x"), into: note, at: .section(friends.id))
        #expect(lines(after)[4...7] == ["Close Friends", "Lucas H - 1/1/1111", "Emma S - 1/1/1111", "x"])
    }

    @Test func endOfNoteKeepsTrailingBlankLinesLast() throws {
        let note = Note(blocks: [Block(text: "a"), Block(text: ""), Block(text: "")])
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "b"), into: note, at: .endOfNote)
        #expect(lines(after) == ["a", "b", "", ""])

        let (empty, _) = try EntryInserter.inserting(Entry(plainText: "first"), into: Note(), at: .endOfNote)
        #expect(lines(empty) == ["first"])
    }

    @Test func insertionUpdatesModifiedDateOnly() throws {
        let created = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 2000)
        let note = Note(title: "T", blocks: [Block(text: "a")], createdAt: created)
        let (after, _) = try EntryInserter.inserting(Entry(plainText: "b"), into: note, at: .endOfNote, now: now)
        #expect(after.modifiedAt == now)
        #expect(after.createdAt == created)
        #expect(after.title == "T")
        #expect(after.id == note.id)
    }

    @Test func undoRestoresTheOriginalNoteExactly() throws {
        let before = SampleNotes.birthdays()
        let (after, receipt) = try EntryInserter.inserting(
            Entry(plainText: "a\nb"), into: before, at: .section(heading(before, "Family").id))
        let undone = try EntryInserter.undoing(receipt, in: after, now: before.modifiedAt)
        #expect(undone == before)
    }

    @Test func undoRefusesWhenInsertedBlocksAreGone() throws {
        let before = SampleNotes.birthdays()
        var (after, receipt) = try EntryInserter.inserting(Entry(plainText: "a\nb"), into: before, at: .endOfNote)
        after.blocks.removeAll { $0.id == receipt.insertedBlockIDs[0] }
        #expect(throws: InsertionError.nothingToUndo) { try EntryInserter.undoing(receipt, in: after) }
        #expect(throws: InsertionError.nothingToUndo) { try EntryInserter.undoing(receipt, in: SampleNotes.recipes()) }
    }
}
