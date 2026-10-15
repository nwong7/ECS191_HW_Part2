import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct PasteNormalizerTests {
    @Test func withFormattingKeepsTraits() {
        let runs = [TextRun("Bold", traits: [.bold]), TextRun(" and "), TextRun("italic", traits: [.italic])]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: true) == runs)
    }

    @Test func withoutFormattingStripsTraitsAndMerges() {
        let runs = [TextRun("Bold", traits: [.bold, .underline]), TextRun(" plain")]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: false) == [TextRun("Bold plain")])
    }

    @Test func lineBreaksAreUnifiedAndTrailingOnesDropped() {
        let runs = [TextRun("a\r\nb\rc\u{2028}d\u{2029}e\n\n", traits: [.bold])]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: true) == [TextRun("a\nb\nc\nd\ne", traits: [.bold])])
    }

    @Test func trailingBreaksAcrossRunsAreDropped() {
        let runs = [TextRun("text", traits: [.italic]), TextRun("\n"), TextRun("\n", traits: [.bold])]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: true) == [TextRun("text", traits: [.italic])])
    }

    @Test func attachmentsAndInvisibleCharactersAreRemoved() {
        let runs = [TextRun("photo:\u{FFFC} zero\u{200B}width\u{00A0}space")]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: false) == [TextRun("photo: zerowidth space")])
    }

    @Test func innerBlankLinesAndIndentationArePreserved() {
        let runs = [TextRun("one\n\n  two")]
        #expect(PasteNormalizer.normalized(runs, keepFormatting: false) == runs)
    }

    @Test func emptyOrOnlyBreaksBecomesNothing() {
        #expect(PasteNormalizer.normalized([], keepFormatting: true).isEmpty)
        #expect(PasteNormalizer.normalized([TextRun("\n\r\n")], keepFormatting: true).isEmpty)
    }
}

@MainActor
@Suite struct AppearanceTests {
    @Test func setAppearancePersistsWithoutChangingOrderOrDate() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileNoteStore(directory: dir)
        let older = Note(title: "Older", createdAt: Date(timeIntervalSince1970: 100))
        let newer = Note(title: "Newer", createdAt: Date(timeIntervalSince1970: 200))
        try store.save(older)
        try store.save(newer)

        let library = NotesLibrary(store: store)
        library.load()
        let appearance = NoteAppearance(icon: "💡", color: .teal)
        #expect(library.setAppearance(appearance, forNote: older.id))
        #expect(library.notes.map(\.title) == ["Newer", "Older"])
        #expect(library.note(id: older.id)?.modifiedAt == older.modifiedAt)

        let reloaded = NotesLibrary(store: JSONFileNoteStore(directory: dir))
        reloaded.load()
        #expect(reloaded.note(id: older.id)?.appearance == appearance)
        #expect(reloaded.note(id: newer.id)?.appearance == NoteAppearance())
    }

    @Test func setAppearanceOnMissingNoteFails() {
        let library = NotesLibrary(store: InMemoryNoteStore())
        #expect(!library.setAppearance(NoteAppearance(), forNote: UUID()))
    }

    @Test func presetsAreUniqueAndColorsCovered() {
        #expect(Set(NoteAppearance.presetIcons).count == NoteAppearance.presetIcons.count)
        #expect(NoteColor.allCases.count >= 6)
    }
}
