import Foundation

/// Stores each note as `<uuid>.json` in one directory.
///
/// - Writes are atomic (temp file + rename), so a crash mid-save leaves the
///   previous version intact rather than a truncated file.
/// - Files that fail to decode are moved to a `Unreadable` subfolder instead of
///   being deleted or overwritten, so data is never silently destroyed.
/// - Each file is wrapped with a schema version to allow future migrations.
public final class JSONFileNoteStore: NoteStore, Sendable {
    public static let schemaVersion = 1

    public let directory: URL
    private var unreadableDirectory: URL { directory.appendingPathComponent("Unreadable", isDirectory: true) }

    private struct FileEnvelope: Codable {
        var schemaVersion: Int
        var note: Note
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Default location: Application Support/Notes.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Notes", isDirectory: true)
    }

    public func loadAll() throws -> NoteLoadResult {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var result = NoteLoadResult(notes: [])
        let decoder = JSONDecoder()
        for file in files {
            do {
                let envelope = try decoder.decode(FileEnvelope.self, from: Data(contentsOf: file))
                result.notes.append(envelope.note)
            } catch {
                result.unreadableFiles.append(file.lastPathComponent)
                quarantine(file)
            }
        }
        return result
    }

    public func save(_ note: Note) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(FileEnvelope(schemaVersion: Self.schemaVersion, note: note))
        try data.write(to: fileURL(for: note.id), options: .atomic)
    }

    public func delete(noteID: UUID) throws {
        let url = fileURL(for: noteID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func quarantine(_ file: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: unreadableDirectory, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let target = unreadableDirectory.appendingPathComponent("\(stamp)-\(file.lastPathComponent)")
            try fm.moveItem(at: file, to: target)
        } catch {
            // Leaving the file in place is safe: it is skipped again next launch and
            // never overwritten, because its note was not loaded and so never saved.
        }
    }
}
