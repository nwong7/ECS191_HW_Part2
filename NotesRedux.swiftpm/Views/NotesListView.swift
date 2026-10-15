import SwiftUI
import NotesReduxCore

/// A request to show the Add Entry sheet. Presented with `.sheet(item:)` so the
/// prefill travels with the request; `.sheet(isPresented:)` could build the
/// sheet from stale state and lose the prefill.
struct AddEntryRequest: Identifiable {
    let id = UUID()
    var prefill: AddEntryPrefill?
}

/// Home screen: searchable notes, newest first, as a list or an icon grid.
struct NotesListView: View {
    @Environment(NotesLibrary.self) private var library
    @AppStorage("notesLayout") private var layout: NotesLayout = .list
    @State private var path: [NoteRoute] = []
    @State private var query = ""
    @State private var pendingDeletion: Note?
    @State private var addEntryRequest: AddEntryRequest?
    @State private var customizingNote: Note?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Notes")
                .searchable(text: $query, prompt: "Search")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { layout = layout == .list ? .grid : .list }
                        } label: {
                            Label(layout == .list ? "Show as Grid" : "Show as List",
                                  systemImage: layout == .list ? "square.grid.2x2" : "list.bullet")
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            addEntryRequest = AddEntryRequest()
                        } label: {
                            Label("Add Entry", systemImage: "text.badge.plus")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(library.notes.isEmpty)
                        Spacer()
                        Button(action: createNote) {
                            Label("New Note", systemImage: "square.and.pencil")
                        }
                    }
                }
                .task {
                    #if DEBUG
                    switch SmokeTestHooks.launchAction(library: library) {
                    case .open(let route)?:
                        path = [route]
                    case .showAddEntry(let prefill)?:
                        addEntryRequest = AddEntryRequest(prefill: prefill)
                    case .changeIcon(let noteID)?:
                        customizingNote = library.note(id: noteID)
                    case nil:
                        break
                    }
                    #endif
                }
                .navigationDestination(for: NoteRoute.self) { route in
                    NoteEditorView(noteID: route.noteID, revealBlockIDs: route.revealBlockIDs)
                }
                .confirmationDialog(
                    "Delete this note?",
                    isPresented: isConfirmingDeletion,
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { note in
                    Button("Delete \u{201C}\(note.displayTitle)\u{201D}", role: .destructive) {
                        delete(note)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("This can't be undone.")
                }
        }
        .environment(\.openNote, { route in path.append(route) })
        .sheet(item: $addEntryRequest) { request in
            AddEntrySheet(prefill: request.prefill) { receipt in
                addEntryRequest = nil
                path = [NoteRoute(noteID: receipt.noteID, revealBlockIDs: receipt.insertedBlockIDs)]
            }
            .environment(library)
        }
        .sheet(item: $customizingNote) { note in
            NoteAppearanceSheet(note: note)
                .environment(library)
        }
        .alert("Something Went Wrong", isPresented: hasError) {
            Button("OK") {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        let notes = library.notes(matching: query)
        if library.notes.isEmpty {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Create a note to get started.")
            } actions: {
                Button("New Note", action: createNote)
                    .buttonStyle(.borderedProminent)
            }
        } else if notes.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if layout == .grid {
            NotesGridView(
                notes: notes,
                footer: footerText(matching: notes.count),
                onCustomize: { customizingNote = $0 },
                onDelete: { pendingDeletion = $0 })
        } else {
            List {
                // Qualified because NotesReduxCore also defines `Section`.
                SwiftUI.Section {
                    ForEach(notes) { note in
                        NavigationLink(value: NoteRoute(noteID: note.id)) {
                            NoteRow(note: note)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = note
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                customizingNote = note
                            } label: {
                                Label("Change Icon…", systemImage: "paintpalette")
                            }
                            Button(role: .destructive) {
                                pendingDeletion = note
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    // Plain caption rather than a bottom-bar item, which iOS
                    // renders as a button-like glass capsule.
                    Text(footerText(matching: notes.count))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func footerText(matching shown: Int) -> String {
        let total = library.notes.count
        let noun = total == 1 ? "Note" : "Notes"
        return query.trimmingCharacters(in: .whitespaces).isEmpty ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }

    private func createNote() {
        guard let note = library.createNote() else { return }
        query = ""
        path.append(NoteRoute(noteID: note.id))
    }

    private func delete(_ note: Note) {
        path.removeAll { $0.noteID == note.id }
        library.delete(noteID: note.id)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            NoteIconView(note: note)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(note.modifiedAt, format: .dateTime.month(.abbreviated).day().year())
                    Text(note.preview.isEmpty ? "No additional text" : note.preview)
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NotesListView()
        .environment(PreviewSupport.library())
}
