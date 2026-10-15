import Foundation
import Observation

/// The app's single source of truth for notes.
///
/// Every mutation goes through here and follows the same order: build the new
/// note value, persist it, and only then publish it in memory. If saving fails,
/// memory still matches disk and the caller is told.
///
/// The editor and Add Entry both write through this object, so an entry added
/// while its note is open shows up in the editor via observation instead of
/// being overwritten by a stale copy.
@MainActor
@Observable
public final class NotesLibrary {
    /// All notes, most recently modified first.
    public private(set) var notes: [Note] = []
    /// Set when the last load or save failed; the UI shows it once and clears it.
    public var lastError: String?

    private let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    // MARK: Loading

    /// Loads notes from the store. Unreadable files are reported via `lastError`.
    public func load() {
        do {
            let result = try store.loadAll()
            notes = result.notes
            sortNotes()
            if !result.unreadableFiles.isEmpty {
                lastError = "\(result.unreadableFiles.count) note file(s) could not be read and were set aside."
            }
        } catch {
            lastError = "Notes could not be loaded: \(error.localizedDescription)"
        }
    }

    // MARK: Queries

    public func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    public func notes(matching query: String) -> [Note] {
        notes.filter { $0.matches(search: query) }
    }

    // MARK: Mutations

    /// Creates, saves and returns a new empty note, or nil if it could not be saved.
    @discardableResult
    public func createNote(title: String = "", blocks: [Block] = [], now: Date = Date()) -> Note? {
        let note = Note(title: title, blocks: blocks, createdAt: now)
        guard persist(note) else { return nil }
        notes.insert(note, at: 0)
        return note
    }

    /// Saves and lists a fully formed note (e.g. sample notes on first launch).
    /// Refuses ids that already exist so nothing is overwritten.
    @discardableResult
    public func add(_ note: Note) -> Bool {
        guard self.note(id: note.id) == nil, persist(note) else { return false }
        notes.append(note)
        sortNotes()
        return true
    }

    /// Saves an edited note. Returns false if the note was deleted meanwhile
    /// (so a late editor autosave cannot resurrect it) or if saving failed.
    @discardableResult
    public func update(_ note: Note) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return false }
        guard notes[index] != note else { return true }
        guard persist(note) else { return false }
        notes[index] = note
        sortNotes()
        return true
    }

    /// Changes a note's grid icon and colour. Appearance is not content, so the
    /// modification date (and therefore list order) is left unchanged.
    @discardableResult
    public func setAppearance(_ appearance: NoteAppearance, forNote noteID: UUID) -> Bool {
        guard var note = note(id: noteID) else { return false }
        guard note.appearance != appearance else { return true }
        note.appearance = appearance
        guard persist(note), let index = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        notes[index] = note
        return true
    }

    /// Deletes one note. Other notes and their files are not touched.
    @discardableResult
    public func delete(noteID: UUID) -> Bool {
        do {
            try store.delete(noteID: noteID)
        } catch {
            lastError = "The note could not be deleted: \(error.localizedDescription)"
            return false
        }
        notes.removeAll { $0.id == noteID }
        return true
    }

    // MARK: Add Entry

    /// Inserts `entry` into a note and saves it.
    ///
    /// Only the target note changes, and only if every check passes and the save
    /// succeeds. Cancelling in the UI simply never calls this.
    public func addEntry(
        _ entry: Entry,
        toNote noteID: UUID,
        at destination: EntryDestination,
        now: Date = Date()
    ) throws(LibraryError) -> InsertionReceipt {
        guard let note = note(id: noteID) else { throw .insertion(.noteNotFound) }
        let result: (note: Note, receipt: InsertionReceipt)
        do {
            result = try EntryInserter.inserting(entry, into: note, at: destination, now: now)
        } catch {
            throw .insertion(error)
        }
        try commit(result.note)
        return result.receipt
    }

    /// Reverts an Add Entry by removing exactly the blocks it created.
    public func undo(_ receipt: InsertionReceipt, now: Date = Date()) throws(LibraryError) {
        guard let note = note(id: receipt.noteID) else { throw .insertion(.noteNotFound) }
        let reverted: Note
        do {
            reverted = try EntryInserter.undoing(receipt, in: note, now: now)
        } catch {
            throw .insertion(error)
        }
        try commit(reverted)
    }

    // MARK: Private

    private func commit(_ note: Note) throws(LibraryError) {
        do {
            try store.save(note)
        } catch {
            throw .saveFailed(error.localizedDescription)
        }
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            sortNotes()
        }
    }

    private func persist(_ note: Note) -> Bool {
        do {
            try store.save(note)
            return true
        } catch {
            lastError = "\"\(note.displayTitle)\" could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func sortNotes() {
        notes.sort { $0.modifiedAt > $1.modifiedAt }
    }
}

public enum LibraryError: Error, Equatable, Sendable {
    case insertion(InsertionError)
    case saveFailed(String)

    public var message: String {
        switch self {
        case .insertion(let error): error.message
        case .saveFailed(let detail): "The note could not be saved, so nothing was changed. (\(detail))"
        }
    }
}
