import SwiftUI
import NotesReduxCore

/// "Change Icon": pick a preset icon (or the title's first letter) and a preset
/// colour. Changes are previewed live and saved only when Done is tapped.
struct NoteAppearanceSheet: View {
    let note: Note

    @Environment(NotesLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var appearance: NoteAppearance

    /// nil means "first letter of the title".
    private let iconOptions: [String?] = [nil] + NoteAppearance.presetIcons
    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    init(note: Note) {
        self.note = note
        _appearance = State(initialValue: note.appearance)
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    VStack(spacing: 8) {
                        NoteIconView(note: previewNote, size: 96)
                        Text(note.displayTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preview")
                }

                SwiftUI.Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(iconOptions.enumerated()), id: \.offset) { _, icon in
                            iconButton(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }

                SwiftUI.Section("Color") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(NoteColor.allCases, id: \.self) { color in
                            colorButton(color)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Change Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        library.setAppearance(appearance, forNote: note.id)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var previewNote: Note {
        var copy = note
        copy.appearance = appearance
        return copy
    }

    private func iconButton(_ icon: String?) -> some View {
        let isSelected = appearance.icon == icon
        return Button {
            appearance.icon = icon
        } label: {
            Group {
                if let icon {
                    Text(icon).font(.title2)
                } else {
                    Text("Aa").font(.headline)
                }
            }
            .frame(width: 48, height: 48)
            .background(
                isSelected ? Color.accentColor.opacity(0.3) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.map { "Icon \($0)" } ?? "First letter of title")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ color: NoteColor) -> some View {
        let isSelected = appearance.color == color
        return Button {
            appearance.color = color
        } label: {
            Circle()
                .fill(color.color.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 3)
                            .padding(-5)
                    }
                }
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.rawValue.capitalized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NoteAppearanceSheet(note: SampleNotes.birthdays())
        .environment(PreviewSupport.library())
}
