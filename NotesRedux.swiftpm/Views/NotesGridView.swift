import SwiftUI
import NotesReduxCore

/// How the home screen shows notes. Stored with @AppStorage("notesLayout").
enum NotesLayout: String {
    case list
    case grid
}

/// App-style grid of notes: icon on its colour with the title underneath,
/// as in the App Library reference from the project notes.
struct NotesGridView: View {
    let notes: [Note]
    let footer: String
    let onCustomize: (Note) -> Void
    let onDelete: (Note) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(notes) { note in
                    NavigationLink(value: NoteRoute(noteID: note.id)) {
                        VStack(spacing: 6) {
                            NoteIconView(note: note, size: 64)
                            Text(note.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onCustomize(note)
                        } label: {
                            Label("Change Icon…", systemImage: "paintpalette")
                        }
                        Button(role: .destructive) {
                            onDelete(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityLabel(note.displayTitle)
                    .accessibilityHint("Opens the note")
                }
            }
            .padding()

            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        NotesGridView(notes: SampleNotes.all(), footer: "3 Notes", onCustomize: { _ in }, onDelete: { _ in })
    }
}
