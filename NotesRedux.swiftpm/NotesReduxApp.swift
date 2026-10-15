import SwiftUI
import NotesReduxCore

@main
struct NotesReduxApp: App {
    @State private var library = AppEnvironment.makeLibrary()

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environment(library)
        }
    }
}

@MainActor
enum AppEnvironment {
    static let didSeedKey = "didSeedSampleNotes"

    /// Opens the on-device note store and loads every note.
    static func makeLibrary() -> NotesLibrary {
        let directory = (try? JSONFileNoteStore.defaultDirectory())
            ?? URL.documentsDirectory.appending(path: "Notes", directoryHint: .isDirectory)
        let library = NotesLibrary(store: JSONFileNoteStore(directory: directory))
        library.load()
        seedSampleNotesOnFirstLaunch(into: library)
        return library
    }

    /// Adds the example notes from the project brief once, on a fresh install,
    /// so Add Entry can be tried immediately. Never runs again, even if the user
    /// deletes every note.
    private static func seedSampleNotesOnFirstLaunch(into library: NotesLibrary) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }
        if library.notes.isEmpty {
            for note in SampleNotes.all() { library.add(note) }
        }
        defaults.set(true, forKey: didSeedKey)
    }
}

/// In-memory library for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static func library() -> NotesLibrary {
        let library = NotesLibrary(store: InMemoryNoteStore(notes: SampleNotes.all()))
        library.load()
        return library
    }
}
