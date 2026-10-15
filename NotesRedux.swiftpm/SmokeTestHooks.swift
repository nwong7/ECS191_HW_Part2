#if DEBUG
import Foundation
import NotesReduxCore

/// DEBUG-only launch arguments used by the CI simulator smoke test
/// (`.github/scripts/smoke-test.sh`). They let the script put the app into a
/// few known states without UI automation, then take screenshots.
///
/// Launch arguments of the form `-Key value` land in UserDefaults' argument
/// domain, which is how they are read here. Matching notes and sections by
/// title is acceptable in this test hook only; the app itself always uses ids.
/// None of this code exists in Release builds.
///
/// - `-SmokeTestOpenNote <title>`: open that note on launch.
/// - `-SmokeTestShowOutline YES`: start note editors with the outline visible.
/// - `-SmokeTestAddEntry <text> -SmokeTestNote <title> -SmokeTestSection <heading>`:
///   run Add Entry through `NotesLibrary` on launch, then open the note with
///   the new lines revealed.
/// - `-SmokeTestShowAddEntrySheet <text> -SmokeTestNote <title> -SmokeTestSection <heading>`:
///   open the Add Entry sheet pre-filled, without submitting it.
/// - `-SmokeTestChangeIcon <title>`: open the Change Icon sheet for that note.
/// - `-notesLayout grid` (not a hook): the app's own stored layout setting.
@MainActor
enum SmokeTestHooks {
    enum LaunchAction {
        case open(NoteRoute)
        case showAddEntry(AddEntryPrefill)
        case changeIcon(UUID)
    }

    private static var didApply = false
    private static var defaults: UserDefaults { .standard }

    static var showOutline: Bool {
        defaults.bool(forKey: "SmokeTestShowOutline")
    }

    /// What to do on first appearance of the notes list, if anything. Runs once
    /// per launch so returning to the list doesn't repeat it.
    static func launchAction(library: NotesLibrary) -> LaunchAction? {
        guard !didApply else { return nil }
        didApply = true

        if let text = defaults.string(forKey: "SmokeTestAddEntry"), let note = targetNote(in: library) {
            let destination = targetDestination(in: note)
            if let receipt = try? library.addEntry(Entry(plainText: text), toNote: note.id, at: destination) {
                return .open(NoteRoute(noteID: note.id, revealBlockIDs: receipt.insertedBlockIDs))
            }
        }

        if let text = defaults.string(forKey: "SmokeTestShowAddEntrySheet"), let note = targetNote(in: library) {
            return .showAddEntry(AddEntryPrefill(noteID: note.id, text: text, destination: targetDestination(in: note)))
        }

        if let title = defaults.string(forKey: "SmokeTestChangeIcon"),
           let note = library.notes.first(where: { $0.title == title }) {
            return .changeIcon(note.id)
        }

        if let title = defaults.string(forKey: "SmokeTestOpenNote"),
           let note = library.notes.first(where: { $0.title == title }) {
            return .open(NoteRoute(noteID: note.id))
        }
        return nil
    }

    private static func targetNote(in library: NotesLibrary) -> Note? {
        guard let title = defaults.string(forKey: "SmokeTestNote") else { return nil }
        return library.notes.first { $0.title == title }
    }

    private static func targetDestination(in note: Note) -> EntryDestination {
        let sectionTitle = defaults.string(forKey: "SmokeTestSection")
        return AddEntryDestinations.options(for: note)
            .first { $0.title == sectionTitle }?.destination ?? .endOfNote
    }
}
#endif
