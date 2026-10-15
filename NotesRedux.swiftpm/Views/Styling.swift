import SwiftUI
import NotesReduxCore

extension NoteColor {
    var color: Color {
        switch self {
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .gray: .gray
        }
    }
}

extension BlockStyle {
    var displayName: String {
        switch self {
        case .body: "Body"
        case .heading: "Heading"
        case .subheading: "Subheading"
        }
    }
}

extension Trait {
    var symbolName: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }

    var displayName: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        }
    }
}

/// Square icon for a note: its preset emoji, or its first letter, on its color.
struct NoteIconView: View {
    let note: Note
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(note.appearance.color.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                if let icon = note.appearance.icon {
                    Text(icon).font(.system(size: size * 0.5))
                } else {
                    Text(String(note.displayTitle.prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}
