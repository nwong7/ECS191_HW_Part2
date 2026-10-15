import Foundation
@testable import NotesReduxCore

/// Plain-text lines of a note, for readable before/after comparisons.
func lines(_ note: Note) -> [String] {
    note.blocks.map(\.plainText)
}

func heading(_ note: Note, _ title: String) -> Block {
    note.blocks.first { $0.style.isHeading && $0.plainText == title }!
}

func makeTempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("NotesReduxTests-\(UUID().uuidString)", isDirectory: true)
}

/// Store whose saves can be made to fail, to verify that failed writes leave
/// in-memory state untouched.
final class FailingStore: NoteStore, @unchecked Sendable {
    struct Failure: Error {}
    let inner = InMemoryNoteStore()
    var failSaves = false

    func loadAll() throws -> NoteLoadResult { try inner.loadAll() }
    func save(_ note: Note) throws {
        if failSaves { throw Failure() }
        try inner.save(note)
    }
    func delete(noteID: UUID) throws { try inner.delete(noteID: noteID) }
}
