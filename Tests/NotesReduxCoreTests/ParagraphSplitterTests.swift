import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct ParagraphSplitterTests {
    func contents(_ text: String) -> [String] {
        let units = Array(text.utf16)
        return ParagraphSplitter.paragraphs(in: text).map {
            String(decoding: units[$0.content], as: UTF16.self)
        }
    }

    @Test func emptyTextIsOneEmptyParagraph() {
        #expect(ParagraphSplitter.paragraphs(in: "") == [ParagraphRange(content: 0..<0, enclosing: 0..<0)])
    }

    @Test func trailingNewlineYieldsTrailingEmptyParagraph() {
        #expect(contents("a\n") == ["a", ""])
        #expect(contents("a\n\n") == ["a", "", ""])
        #expect(contents("\n") == ["", ""])
    }

    @Test func allTerminatorKindsSplitAndCRLFIsOne() {
        #expect(contents("a\r\nb\rc\u{2028}d\u{2029}e") == ["a", "b", "c", "d", "e"])
        let p = ParagraphSplitter.paragraphs(in: "a\r\nb")
        #expect(p[0].enclosing == 0..<3)
        #expect(p[1].content == 3..<4)
    }

    @Test func offsetsAreUTF16() {
        // "🎂" is 2 UTF-16 code units; NSRange-based editors rely on this.
        let p = ParagraphSplitter.paragraphs(in: "🎂\nx")
        #expect(p[0].content == 0..<2)
        #expect(p[1].content == 3..<4)
    }

    @Test func roundTripsWithBlocksJoinedByNewline() {
        let note = SampleNotes.birthdays()
        let text = note.blocks.map(\.plainText).joined(separator: "\n")
        #expect(contents(text) == note.blocks.map(\.plainText))
    }

    @Test func caretLocationMapsToParagraph() {
        let p = ParagraphSplitter.paragraphs(in: "ab\ncd\n")
        #expect(ParagraphSplitter.index(containing: 0, in: p) == 0)
        #expect(ParagraphSplitter.index(containing: 2, in: p) == 0)   // before "\n"
        #expect(ParagraphSplitter.index(containing: 3, in: p) == 1)   // after "\n"
        #expect(ParagraphSplitter.index(containing: 6, in: p) == 2)   // end of text
    }

    @Test func returnEndsHeadingOnlyAtEndOfHeading() {
        let p = ParagraphSplitter.paragraphs(in: "Friends\nLucas")
        let styles: [BlockStyle] = [.heading, .body]
        #expect(EditorRules.returnEndsHeading(at: 7, paragraphs: p, styleOfParagraph: { styles[$0] }))
        #expect(!EditorRules.returnEndsHeading(at: 3, paragraphs: p, styleOfParagraph: { styles[$0] }))
        #expect(!EditorRules.returnEndsHeading(at: 13, paragraphs: p, styleOfParagraph: { styles[$0] }))
    }
}

@MainActor
@Suite struct NotesLibraryAddTests {
    @Test func addKeepsAppearanceAndRefusesDuplicates() {
        let library = NotesLibrary(store: InMemoryNoteStore())
        let sample = SampleNotes.birthdays()
        #expect(library.add(sample))
        #expect(library.note(id: sample.id)?.appearance.icon == "🎂")
        var changed = sample
        changed.title = "Overwrite?"
        #expect(!library.add(changed))
        #expect(library.note(id: sample.id)?.title == "Birthdays")
    }
}
