import SwiftUI
import NotesReduxCore

/// Optional starting values for the Add Entry sheet.
struct AddEntryPrefill: Equatable {
    var noteID: UUID?
    var text = ""
    var destination: EntryDestination?
}

/// Add Entry: type text, choose a note and a section, insert.
///
/// All checks and the insertion itself happen in `NotesLibrary.addEntry`
/// (tested in NotesReduxCore). This view only collects input and reports the
/// outcome. Cancelling never calls the library, so it cannot change any note.
struct AddEntrySheet: View {
    /// Called with the receipt when the user taps "View in Note".
    var onViewInNote: (InsertionReceipt) -> Void

    @Environment(NotesLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var noteID: UUID?
    @State private var destination: EntryDestination = .endOfNote
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?
    @State private var isConfirmingDiscard = false
    @FocusState private var isTextFocused: Bool

    private enum Phase: Equatable {
        case editing
        case added(InsertionReceipt, summary: String)
        case undone(summary: String)
    }

    init(
        initialNoteID: UUID? = nil,
        prefill: AddEntryPrefill? = nil,
        onViewInNote: @escaping (InsertionReceipt) -> Void
    ) {
        self.onViewInNote = onViewInNote
        _noteID = State(initialValue: prefill?.noteID ?? initialNoteID)
        _text = State(initialValue: prefill?.text ?? "")
        _destination = State(initialValue: prefill?.destination ?? .endOfNote)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .editing:
                    form
                case .added(let receipt, let summary):
                    addedView(receipt: receipt, summary: summary)
                case .undone(let summary):
                    undoneView(summary: summary)
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Swipe-to-dismiss would silently discard typed text.
        .interactiveDismissDisabled(phase == .editing && hasText)
    }

    // MARK: Editing

    private var form: some View {
        Form {
            Section {
                TextField("What do you want to note down?", text: $text, axis: .vertical)
                    .lineLimit(3...10)
                    .focused($isTextFocused)
            } header: {
                Text("Entry")
            } footer: {
                Text("Each line of the entry becomes its own line in the note.")
            }

            Section {
                Picker("Note", selection: $noteID) {
                    Text("Choose a Note").tag(UUID?.none)
                    ForEach(library.notes) { note in
                        Text(note.displayTitle).tag(UUID?.some(note.id))
                    }
                }
                .pickerStyle(.navigationLink)

                if let note = selectedNote {
                    Picker("Section", selection: $destination) {
                        ForEach(AddEntryDestinations.options(for: note)) { option in
                            Text(option.title)
                                .padding(.leading, CGFloat(max(option.level - 1, 0)) * 16)
                                .tag(option.destination)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: {
                Text("Add To")
            } footer: {
                destinationFooter
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: submit)
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
            }
        }
        .onChange(of: noteID) { _, _ in
            destination = selectedNote.map(AddEntryDestinations.defaultDestination(for:)) ?? .endOfNote
        }
        .onAppear { isTextFocused = true }
        .alert("Couldn't Add Entry", isPresented: hasError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Discard this entry?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard Entry", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var destinationFooter: some View {
        if noteID != nil && selectedNote == nil {
            Text("That note no longer exists. Choose another note.")
                .foregroundStyle(.red)
        } else if let note = selectedNote, !AddEntryDestinations.isValid(destination, in: note) {
            Text("That section no longer exists. Choose another section.")
                .foregroundStyle(.red)
        } else if let note = selectedNote, let summary = AddEntryDestinations.describe(destination, in: note) {
            Text("Will be added at the end of \(summary).")
        }
    }

    // MARK: Result

    private func addedView(receipt: InsertionReceipt, summary: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Entry Added")
                    .font(.title2.bold())
                Text("Added to \(summary)")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    onViewInNote(receipt)
                } label: {
                    Label("View in Note", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    undo(receipt, summary: summary)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Couldn't Undo", isPresented: hasError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func undoneView(summary: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Entry Removed")
                .font(.title2.bold())
            Text("\(summary) is back to how it was.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                phase = .editing
            } label: {
                Label("Edit Entry Again", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Actions

    private var selectedNote: Note? {
        noteID.flatMap(library.note(id:))
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmit: Bool {
        guard let note = selectedNote else { return false }
        return !Entry(plainText: text).isEmpty && AddEntryDestinations.isValid(destination, in: note)
    }

    private var hasError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func cancel() {
        if hasText {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func submit() {
        guard let noteID else { return }
        do {
            let receipt = try library.addEntry(Entry(plainText: text), toNote: noteID, at: destination)
            let summary = library.note(id: noteID)
                .flatMap { AddEntryDestinations.describe(destination, in: $0) } ?? "the note"
            phase = .added(receipt, summary: summary)
        } catch let error as LibraryError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ receipt: InsertionReceipt, summary: String) {
        do {
            try library.undo(receipt)
            phase = .undone(summary: library.note(id: receipt.noteID)?.displayTitle ?? summary)
        } catch let error as LibraryError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddEntrySheet { _ in }
        .environment(PreviewSupport.library())
}
