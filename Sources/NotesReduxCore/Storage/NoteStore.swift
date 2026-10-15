import Foundation

/// Result of loading all notes. Unreadable files are reported, not fatal.
public struct NoteLoadResult: Sendable {
    public var notes: [Note]
    /// Files that could not be decoded. `JSONFileNoteStore` moves them aside.
    public var unreadableFiles: [String]

    public init(notes: [Note], unreadableFiles: [String] = []) {
        self.notes = notes
        self.unreadableFiles = unreadableFiles
    }
}

/// Persistence boundary. Each note is saved and deleted independently, so
/// writing one note can never corrupt another.
public protocol NoteStore: Sendable {
    func loadAll() throws -> NoteLoadResult
    func save(_ note: Note) throws
    func delete(noteID: UUID) throws
}

/// Volatile store for tests and SwiftUI previews.
public final class InMemoryNoteStore: NoteStore, @unchecked Sendable {
    // @unchecked: all access to `notes` goes through `lock`.
    private let lock = NSLock()
    private var notes: [UUID: Note]

    public init(notes: [Note] = []) {
        self.notes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    }

    public func loadAll() throws -> NoteLoadResult {
        lock.withLock { NoteLoadResult(notes: Array(notes.values)) }
    }

    public func save(_ note: Note) throws {
        lock.withLock { notes[note.id] = note }
    }

    public func delete(noteID: UUID) throws {
        lock.withLock { _ = notes.removeValue(forKey: noteID) }
    }
}
