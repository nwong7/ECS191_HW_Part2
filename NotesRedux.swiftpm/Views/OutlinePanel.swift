import SwiftUI
import NotesReduxCore

/// Side panel listing a note's headings and subheadings, in the style of the
/// Google Docs outline from the project notes: headings next to a vertical
/// line, subheadings indented, the section currently on screen highlighted.
///
/// `sections` is derived from the note on every render, so the panel stays in
/// sync with edits automatically.
struct OutlinePanel: View {
    let sections: [NotesReduxCore.Section]
    let currentSectionID: UUID?
    let onSelect: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hide Outline")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)

            Divider()

            if sections.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Use the style menu to make a line a Heading or Subheading."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                row(for: section)
                                    .id(section.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: currentSectionID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func row(for section: NotesReduxCore.Section) -> some View {
        let isCurrent = section.id == currentSectionID
        return Button {
            onSelect(section.id)
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isCurrent ? Color.accentColor : Color(.separator))
                    .frame(width: isCurrent ? 4 : 1)
                Text(section.displayTitle)
                    .font(section.level == 1 ? .body : .subheadline)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    // Primary text even when current: yellow-on-pale-yellow is
                    // hard to read. The accent marks the line and background.
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, section.level == 1 ? 12 : 28)
                    .padding(.trailing, 12)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .accessibilityLabel(section.level == 1 ? "Heading, \(section.displayTitle)" : "Subheading, \(section.displayTitle)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Vertical bar on the screen edge that opens the outline by tap or by
/// dragging it toward the middle of the screen, as described in the project
/// notes. Tinted with the app's accent colour so it reads as part of the app,
/// not as a system picture-in-picture grabber.
struct OutlineHandle: View {
    let onOpen: () -> Void

    var body: some View {
        Capsule()
            .fill(Color.accentColor.opacity(0.75))
            .frame(width: 6, height: 180)
            .padding(.trailing, 3)
            // Much larger invisible hit area than the visible bar, for an easy grab.
            .frame(width: 44, height: 240, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                if value.translation.width < -30 { onOpen() }
            })
            .accessibilityElement()
            .accessibilityLabel("Show Outline")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
    }
}
