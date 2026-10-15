import SwiftUI
import NotesReduxCore

/// Edits one note. Every change is saved immediately through `NotesLibrary`
/// (one small atomic file write), so there is no unsaved state to lose when the
/// app is closed or killed.
struct NoteEditorView: View {
    let noteID: UUID

    @Environment(NotesLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openNote) private var openNote
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var controller = RichTextController()
    @State private var isConfirmingDelete = false
    @State private var isAddingEntry = false
    @State private var customizingNote: Note?
    @State private var revealRequest: RevealRequest?
    @State private var isOutlineVisible: Bool

    /// A request to scroll to and highlight blocks. The token makes repeated
    /// requests for the same blocks distinct, so each one triggers.
    private struct RevealRequest: Hashable {
        let blockIDs: [UUID]
        let token = UUID()
    }

    init(noteID: UUID, revealBlockIDs: [UUID] = []) {
        self.noteID = noteID
        _revealRequest = State(initialValue: revealBlockIDs.isEmpty ? nil : RevealRequest(blockIDs: revealBlockIDs))
        var showOutline = false
        #if DEBUG
        showOutline = SmokeTestHooks.showOutline
        #endif
        _isOutlineVisible = State(initialValue: showOutline)
    }

    var body: some View {
        Group {
            if let note = library.note(id: noteID) {
                editor(for: note)
            } else {
                ContentUnavailableView(
                    "Note Not Found",
                    systemImage: "note.text",
                    description: Text("This note may have been deleted."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if controller.isEditing {
                    Button("Done") { controller.endEditing() }
                        .fontWeight(.semibold)
                }
                Button {
                    setOutlineVisible(!isOutlineVisible)
                } label: {
                    Label(isOutlineVisible ? "Hide Outline" : "Show Outline", systemImage: "list.bullet.indent")
                }
                .disabled(library.note(id: noteID) == nil)
                // On iPhone the outline covers the note, so hide note actions
                // while it is open to avoid acting on a note you can't see.
                if !(isOutlineVisible && horizontalSizeClass == .compact) {
                    Button {
                        controller.endEditing()
                        isAddingEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "text.badge.plus")
                    }
                    .disabled(library.note(id: noteID) == nil)
                    Menu {
                        Button {
                            controller.endEditing()
                            customizingNote = library.note(id: noteID)
                        } label: {
                            Label("Change Icon…", systemImage: "paintpalette")
                        }
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            AddEntrySheet(initialNoteID: noteID) { receipt in
                isAddingEntry = false
                if receipt.noteID == noteID {
                    revealRequest = RevealRequest(blockIDs: receipt.insertedBlockIDs)
                } else {
                    openNote(NoteRoute(noteID: receipt.noteID, revealBlockIDs: receipt.insertedBlockIDs))
                }
            }
            .environment(library)
        }
        .sheet(item: $customizingNote) { note in
            NoteAppearanceSheet(note: note)
                .environment(library)
        }
        .task(id: revealRequest) {
            guard let request = revealRequest else { return }
            // Let navigation/sheet animations and text layout finish first.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            controller.reveal(blockIDs: request.blockIDs)
        }
        .confirmationDialog("Delete this note?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                library.delete(noteID: noteID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func editor(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: titleBinding)
                .font(.title.bold())
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Text(note.modifiedAt, format: .dateTime.month(.wide).day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 2)
            RichTextEditor(blocks: note.blocks, controller: controller) { blocks in
                save(blocks: blocks)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FormatBar(controller: controller)
        }
        .overlay(alignment: .trailing) {
            outline(for: note)
        }
    }

    // MARK: Outline

    @ViewBuilder
    private func outline(for note: Note) -> some View {
        if isOutlineVisible {
            ZStack(alignment: .trailing) {
                // Dimmed backdrop on narrow screens; tap it to close.
                if horizontalSizeClass == .compact {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture { setOutlineVisible(false) }
                        .accessibilityHidden(true)
                }
                OutlinePanel(
                    sections: SectionIndex.sections(in: note),
                    currentSectionID: controller.currentSectionID,
                    onSelect: { sectionID in
                        controller.scrollTo(sectionID: sectionID)
                        if horizontalSizeClass == .compact { setOutlineVisible(false) }
                    },
                    onClose: { setOutlineVisible(false) })
                .frame(width: 300)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .shadow(color: .black.opacity(0.15), radius: 8, x: -2)
                // Swipe the panel toward the edge to hide it.
                .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.width > 60 { setOutlineVisible(false) }
                })
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            OutlineHandle { setOutlineVisible(true) }
                .transition(.opacity)
        }
    }

    private func setOutlineVisible(_ visible: Bool) {
        if visible { controller.endEditing() }
        withAnimation(.snappy) { isOutlineVisible = visible }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { library.note(id: noteID)?.title ?? "" },
            set: { newTitle in
                guard var note = library.note(id: noteID), note.title != newTitle else { return }
                note.title = newTitle
                note.modifiedAt = Date()
                library.update(note)
            })
    }

    private func save(blocks: [Block]) {
        // Read the latest note from the library rather than a captured copy, so
        // a title edit or Add Entry in between is never overwritten.
        guard var note = library.note(id: noteID), note.blocks != blocks else { return }
        note.blocks = blocks
        note.modifiedAt = Date()
        library.update(note)
    }
}

/// Paragraph style menu, bold/italic/underline/strikethrough toggles and the
/// paste menu. Sits above the keyboard via `safeAreaInset`.
struct FormatBar: View {
    let controller: RichTextController

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Picker("Paragraph Style", selection: styleBinding) {
                    ForEach(BlockStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(controller.currentStyle.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .padding(.horizontal, 6)
            }
            .accessibilityLabel("Paragraph style, \(controller.currentStyle.displayName)")

            Spacer(minLength: 8)

            ForEach(Trait.allCases, id: \.self) { trait in
                let isOn = controller.activeTraits.contains(trait)
                Button {
                    controller.toggle(trait)
                } label: {
                    Image(systemName: trait.symbolName)
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(
                            isOn ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .accessibilityLabel(trait.displayName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }

            // Tapping outside the menu closes it without pasting.
            Menu {
                Button {
                    controller.paste(keepFormatting: true)
                } label: {
                    Label("Paste with Formatting", systemImage: "doc.richtext")
                }
                Button {
                    controller.paste(keepFormatting: false)
                } label: {
                    Label("Paste without Formatting", systemImage: "doc.plaintext")
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Paste")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.bar)
    }

    private var styleBinding: Binding<BlockStyle> {
        Binding(get: { controller.currentStyle }, set: { controller.setStyle($0) })
    }
}

#Preview {
    let library = PreviewSupport.library()
    return NavigationStack {
        NoteEditorView(noteID: library.notes.first { $0.title == "Birthdays" }!.id)
    }
    .environment(library)
}
