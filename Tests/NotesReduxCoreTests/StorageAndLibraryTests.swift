import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct JSONFileNoteStoreTests {
    @Test func notesRoundTripAcrossStoreInstances() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var formatted = SampleNotes.birthdays()
        formatted.blocks[1].runs = [TextRun("Dad", traits: [.bold, .underline]), TextRun(" [1/1/1111]")]
        let notes = [formatted, SampleNotes.recipes(), Note()]
        let store = JSONFileNoteStore(directory: dir)
        for note in notes { try store.save(note) }

        // A fresh instance simulates relaunching the app.
        let loaded = try JSONFileNoteStore(directory: dir).loadAll()
        #expect(loaded.unreadableFiles.isEmpty)
        #expect(Set(loaded.notes) == Set(notes))
    }

    @Test func deleteRemovesOnlyThatNote() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileNoteStore(directory: dir)
        let a = SampleNotes.recipes(), b = SampleNotes.birthdays()
        try store.save(a)
        try store.save(b)
        let bData = try Data(contentsOf: store.fileURL(for: b.id))

        try store.delete(noteID: a.id)
        try store.delete(noteID: UUID()) // deleting a missing note is a no-op

        #expect(try store.loadAll().notes == [b])
        #expect(try Data(contentsOf: store.fileURL(for: b.id)) == bData)
    }

    @Test func unreadableFileIsSetAsideAndOthersStillLoad() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileNoteStore(directory: dir)
        let good = SampleNotes.wordList()
        try store.save(good)
        let bad = dir.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{ not json".utf8).write(to: bad)

        let result = try store.loadAll()
        #expect(result.notes == [good])
        #expect(result.unreadableFiles == [bad.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: bad.path))
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Unreadable").path)
        #expect(quarantined.count == 1)
    }

    @Test func noteWithoutAppearanceStillDecodes() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"Old","createdAt":0,
         "blocks":[{"id":"\(UUID().uuidString)","style":"heading","runs":[{"text":"H","traits":[]}]}]}
        """
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        #expect(note.id == id)
        #expect(note.appearance == NoteAppearance())
        #expect(note.modifiedAt == note.createdAt)
        #expect(note.blocks[0].style == .heading)
    }
}

@MainActor
@Suite struct NotesLibraryTests {
    @Test func addEntryPersistsAndLeavesOtherNotesByteForByteUnchanged() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileNoteStore(directory: dir)
        for note in SampleNotes.all() { try store.save(note) }

        let library = NotesLibrary(store: store)
        library.load()
        let birthdays = library.notes.first { $0.title == "Birthdays" }!
        let others = library.notes.filter { $0.id != birthdays.id }
        let othersData = try others.map { try Data(contentsOf: store.fileURL(for: $0.id)) }

        let receipt = try library.addEntry(
            Entry(plainText: "Josh B - 5/28/2004"), toNote: birthdays.id, at: .section(heading(birthdays, "Friends").id))

        // Relaunch.
        let reloaded = NotesLibrary(store: JSONFileNoteStore(directory: dir))
        reloaded.load()
        let saved = reloaded.note(id: birthdays.id)!
        #expect(saved.blocks[receipt.insertionIndex].plainText == "Josh B - 5/28/2004")
        #expect(saved.blocks.count == birthdays.blocks.count + 1)
        #expect(try others.map { try Data(contentsOf: store.fileURL(for: $0.id)) } == othersData)
        // Most recently modified note is listed first.
        #expect(reloaded.notes.first?.id == birthdays.id)
    }

    @Test func addEntryToDeletedNoteFailsSafely() throws {
        let library = NotesLibrary(store: InMemoryNoteStore(notes: SampleNotes.all()))
        library.load()
        let target = library.notes[0]
        library.delete(noteID: target.id)
        let before = library.notes
        #expect(throws: LibraryError.insertion(.noteNotFound)) {
            try library.addEntry(Entry(plainText: "x"), toNote: target.id, at: .endOfNote)
        }
        #expect(library.notes == before)
    }

    @Test func failedSaveLeavesMemoryUnchanged() throws {
        let store = FailingStore()
        try store.save(SampleNotes.birthdays())
        let library = NotesLibrary(store: store)
        library.load()
        let before = library.notes
        store.failSaves = true

        let note = before[0]
        #expect(throws: LibraryError.self) {
            try library.addEntry(Entry(plainText: "x"), toNote: note.id, at: .endOfNote)
        }
        var edited = note
        edited.title = "Changed"
        #expect(library.update(edited) == false)
        #expect(library.notes == before)
        #expect(library.lastError != nil)
    }

    @Test func lateAutosaveCannotResurrectDeletedNote() throws {
        let store = InMemoryNoteStore()
        let library = NotesLibrary(store: store)
        let note = library.createNote(title: "Temp")!
        library.delete(noteID: note.id)
        #expect(library.update(note) == false)
        #expect(try store.loadAll().notes.isEmpty)
    }

    @Test func editingOneNoteDoesNotTouchAnother() throws {
        let library = NotesLibrary(store: InMemoryNoteStore(notes: SampleNotes.all()))
        library.load()
        var recipes = library.notes.first { $0.title == "Recipes" }!
        let untouched = library.notes.filter { $0.id != recipes.id }
        recipes.blocks.append(Block(text: "Key lime pie: recipe"))
        recipes.modifiedAt = Date()
        #expect(library.update(recipes))
        #expect(Set(library.notes.filter { $0.id != recipes.id }) == Set(untouched))
        #expect(library.notes.first?.id == recipes.id)
    }

    @Test func undoAfterAddEntryRestoresSavedNote() throws {
        let store = InMemoryNoteStore(notes: [SampleNotes.birthdays()])
        let library = NotesLibrary(store: store)
        library.load()
        let original = library.notes[0]
        let receipt = try library.addEntry(Entry(plainText: "x"), toNote: original.id, at: .endOfNote)
        try library.undo(receipt)
        #expect(library.notes[0].blocks == original.blocks)
        #expect(try store.loadAll().notes[0].blocks == original.blocks)
    }

    @Test func searchMatchesTitleAndBodyIgnoringCase() {
        let library = NotesLibrary(store: InMemoryNoteStore(notes: SampleNotes.all()))
        library.load()
        #expect(library.notes(matching: "KLUDGE").map(\.title) == ["Word List"])
        #expect(library.notes(matching: "birth").map(\.title) == ["Birthdays"])
        #expect(library.notes(matching: "pie").map(\.title) == ["Recipes"])
        #expect(library.notes(matching: "  ").count == 3)
    }
}
