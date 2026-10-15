import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct BlockReconcilerTests {
    /// Paragraph fully tagged with a single block id, as the editor would report it.
    func para(_ text: String, _ style: BlockStyle = .body, id: UUID?) -> EditorParagraph {
        EditorParagraph(
            style: style,
            runs: [TextRun(text)],
            idClaims: id.map { [.init(id: $0, characterCount: text.count + 1)] } ?? [])
    }

    @Test func unchangedParagraphsKeepTheirIds() {
        let previous = SampleNotes.birthdays().blocks
        let paragraphs = previous.map { para($0.plainText, $0.style, id: $0.id) }
        #expect(BlockReconciler.reconcile(paragraphs, previous: previous) == previous)
    }

    @Test func typingInsideAParagraphKeepsItsId() {
        let block = Block(style: .heading, text: "Friends")
        let result = BlockReconciler.reconcile([para("Close Friends", .heading, id: block.id)], previous: [block])
        #expect(result == [Block(id: block.id, style: .heading, text: "Close Friends")])
    }

    @Test func splittingAParagraphGivesExactlyOneHalfTheOldId() {
        let block = Block(text: "Hello World")
        let result = BlockReconciler.reconcile(
            [para("Hello ", id: block.id), para("World", id: block.id)], previous: [block])
        #expect(result.count == 2)
        #expect(result.filter { $0.id == block.id }.count == 1)
        #expect(Set(result.map(\.id)).count == 2)
    }

    @Test func returnAtStartOfHeadingKeepsIdOnHeadingText() {
        let block = Block(style: .heading, text: "Friends")
        // The new empty line inherits heading style and the id from typing attributes.
        let result = BlockReconciler.reconcile(
            [para("", .heading, id: block.id), para("Friends", .heading, id: block.id)], previous: [block])
        #expect(result[1].id == block.id)
        #expect(result[0].id != block.id)
    }

    @Test func styleMatchBeatsLength() {
        let block = Block(style: .heading, text: "Hi")
        // Split where the longer half became body text: the half still a heading keeps the id.
        let result = BlockReconciler.reconcile(
            [para("Hi", .heading, id: block.id), para("a much longer body line", .body, id: block.id)],
            previous: [block])
        #expect(result[0].id == block.id)
    }

    @Test func mergedParagraphKeepsTheMajorityId() {
        let a = Block(style: .heading, text: "Friends")
        let b = Block(text: "Lu")
        let merged = EditorParagraph(
            style: .heading,
            runs: [TextRun("FriendsLu")],
            idClaims: [.init(id: a.id, characterCount: 7), .init(id: b.id, characterCount: 3)])
        let result = BlockReconciler.reconcile([merged], previous: [a, b])
        #expect(result == [Block(id: a.id, style: .heading, text: "FriendsLu")])
    }

    @Test func newAndForeignParagraphsGetFreshIds() {
        let block = Block(text: "a")
        let foreign = UUID()
        let result = BlockReconciler.reconcile(
            [para("a", id: block.id), para("typed", id: nil), para("pasted", id: foreign)], previous: [block])
        #expect(result[0].id == block.id)
        #expect(result[1].id != block.id)
        #expect(result[2].id != foreign)
        #expect(Set(result.map(\.id)).count == 3)
    }

    @Test func formattingRunsAreNormalized() {
        let block = Block(text: "x")
        let p = EditorParagraph(
            style: .body,
            runs: [TextRun("a", traits: [.bold]), TextRun(""), TextRun("b", traits: [.bold])],
            idClaims: [.init(id: block.id, characterCount: 3)])
        #expect(BlockReconciler.reconcile([p], previous: [block])[0].runs == [TextRun("ab", traits: [.bold])])
    }
}
