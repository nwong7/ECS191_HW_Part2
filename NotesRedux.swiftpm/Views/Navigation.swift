import SwiftUI

/// Navigation destination for a note, optionally asking the editor to scroll to
/// and highlight some blocks (used by Add Entry's "View in Note").
struct NoteRoute: Hashable {
    let noteID: UUID
    var revealBlockIDs: [UUID] = []
}

extension EnvironmentValues {
    /// Opens a note on the main navigation stack. Lets views deeper in the stack
    /// (e.g. the editor's Add Entry sheet) navigate to a different note.
    @Entry var openNote: (NoteRoute) -> Void = { _ in }
}
