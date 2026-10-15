import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct AddEntryDestinationsTests {
    @Test func birthdaysOffersEachSectionThenEndOfNote() {
        let note = SampleNotes.birthdays()
        let options = AddEntryDestinations.options(for: note)
        #expect(options.map(\.title) == ["Family", "Friends", "School", "Work", "End of Note"])
        #expect(options.last?.destination == .endOfNote)
        #expect(options[1].destination == .section(heading(note, "Friends").id))
        #expect(Set(options.map(\.id)).count == options.count)
    }

    @Test func noteWithoutHeadingsOffersOnlyEndOfNote() {
        let options = AddEntryDestinations.options(for: SampleNotes.recipes())
        #expect(options.map(\.destination) == [.endOfNote])
    }

    @Test func subheadingsAreIndentedAndShowTheirPath() {
        let note = Note(title: "Birthdays", blocks: [
            Block(style: .heading, text: "Family"),
            Block(style: .subheading, text: "Cousins"),
            Block(style: .heading, text: ""),
        ])
        let options = AddEntryDestinations.options(for: note)
        #expect(options.map(\.level) == [1, 2, 1, 0])
        #expect(options[1].path == "Family › Cousins")
        #expect(options[2].title == "Untitled Section")
        #expect(AddEntryDestinations.describe(options[1].destination, in: note) == "Birthdays › Family › Cousins")
    }

    @Test func defaultIsAlwaysValid() {
        for note in SampleNotes.all() + [Note()] {
            let destination = AddEntryDestinations.defaultDestination(for: note)
            #expect(AddEntryDestinations.isValid(destination, in: note))
        }
    }

    @Test func removedSectionIsNoLongerValidOrDescribed() {
        var note = SampleNotes.birthdays()
        let friends = heading(note, "Friends")
        #expect(AddEntryDestinations.isValid(.section(friends.id), in: note))
        note.blocks[4].style = .body
        #expect(!AddEntryDestinations.isValid(.section(friends.id), in: note))
        #expect(AddEntryDestinations.describe(.section(friends.id), in: note) == nil)
        #expect(AddEntryDestinations.describe(.endOfNote, in: note) == "Birthdays › End of Note")
    }
}
