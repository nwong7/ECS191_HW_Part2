import Foundation
import Testing
@testable import NotesReduxCore

@Suite struct SectionIndexTests {
    @Test func birthdaysHasFourTopLevelSections() {
        let note = SampleNotes.birthdays()
        let sections = SectionIndex.sections(in: note)
        #expect(sections.map(\.title) == ["Family", "Friends", "School", "Work"])
        #expect(sections.allSatisfy { $0.level == 1 && $0.parentID == nil })
        // Friends: heading at 4, own content is Lucas, Emma, blank.
        #expect(sections[1].headingIndex == 4)
        #expect(sections[1].contentRange == 5..<8)
        // Last section runs to the end of the note.
        #expect(sections[3].contentRange == 12..<13)
    }

    @Test func subheadingsEndParentContentAndRecordParent() {
        let note = Note(blocks: [
            Block(text: "intro"),
            Block(style: .heading, text: "Family"),
            Block(text: "Dad"),
            Block(style: .subheading, text: "Cousins"),
            Block(text: "Ann"),
            Block(style: .heading, text: "Friends"),
        ])
        let sections = SectionIndex.sections(in: note)
        #expect(sections.count == 3)
        #expect(sections[0].contentRange == 2..<3)   // Family's own content stops at Cousins
        #expect(sections[1].parentID == sections[0].id)
        #expect(sections[1].contentRange == 4..<5)
        #expect(sections[2].contentRange.isEmpty)
        #expect(SectionIndex.path(for: sections[1], in: sections) == "Family › Cousins")
        // Content before the first heading belongs to no section.
        #expect(SectionIndex.section(containing: 0, in: sections) == nil)
        #expect(SectionIndex.section(containing: 4, in: sections)?.title == "Cousins")
    }

    @Test func duplicateHeadingTitlesAreDistinctSections() {
        let note = Note(blocks: [
            Block(style: .heading, text: "Notes"),
            Block(style: .heading, text: "Notes"),
        ])
        let sections = SectionIndex.sections(in: note)
        #expect(sections.count == 2)
        #expect(sections[0].id != sections[1].id)
    }

    @Test func textOffsetMapsToEnclosingSection() {
        let blocks = SampleNotes.birthdays().blocks
        let text = blocks.map(\.plainText).joined(separator: "\n")
        let paragraphs = ParagraphSplitter.paragraphs(in: text)
        let offsetOfLucas = (text as NSString).range(of: "Lucas").location
        let offsetOfWork = (text as NSString).range(of: "Work").location

        #expect(SectionIndex.section(atTextOffset: 0, paragraphs: paragraphs, blocks: blocks)?.title == "Family")
        #expect(SectionIndex.section(atTextOffset: offsetOfLucas, paragraphs: paragraphs, blocks: blocks)?.title == "Friends")
        #expect(SectionIndex.section(atTextOffset: offsetOfWork, paragraphs: paragraphs, blocks: blocks)?.title == "Work")
        #expect(SectionIndex.section(atTextOffset: text.utf16.count, paragraphs: paragraphs, blocks: blocks)?.title == "Work")
        // Out of step (e.g. mid-edit): no guess.
        #expect(SectionIndex.section(atTextOffset: 0, paragraphs: paragraphs, blocks: Array(blocks.dropLast())) == nil)
    }

    /// The outline is derived from blocks, so it follows edits made through the
    /// editor pipeline: renamed headings keep their id, new headings appear.
    @Test func outlineFollowsEditorEdits() {
        let before = SampleNotes.birthdays().blocks
        var paragraphs = before.map { block in
            EditorParagraph(style: block.style, runs: block.runs,
                            idClaims: [.init(id: block.id, characterCount: block.plainText.count + 1)])
        }
        paragraphs[4].runs = [TextRun("Close Friends")]                        // rename heading
        paragraphs.insert(EditorParagraph(style: .subheading, runs: [TextRun("College")], idClaims: []), at: 7)
        paragraphs[0].style = .body                                             // "Family" demoted

        let after = BlockReconciler.reconcile(paragraphs, previous: before)
        let sections = SectionIndex.sections(in: after)
        #expect(sections.map(\.title) == ["Close Friends", "College", "School", "Work"])
        #expect(sections[0].id == before[4].id)
        #expect(sections[1].parentID == before[4].id)
    }

    @Test func noHeadingsMeansNoSections() {
        #expect(SectionIndex.sections(in: SampleNotes.recipes()).isEmpty)
    }
}
