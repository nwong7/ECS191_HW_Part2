import Foundation

/// A paragraph as read back from the rich-text editor.
///
/// The editor tags every character (including the paragraph's trailing newline)
/// with the id of the block it came from. After arbitrary edits, a paragraph may
/// carry zero ids (newly typed), one id (typical), or several (paragraphs merged
/// by deleting a line break). `idClaims` records how many characters carry each.
public struct EditorParagraph: Hashable, Sendable {
    public struct Claim: Hashable, Sendable {
        public var id: UUID
        public var characterCount: Int
        public init(id: UUID, characterCount: Int) {
            self.id = id
            self.characterCount = characterCount
        }
    }

    public var style: BlockStyle
    public var runs: [TextRun]
    public var idClaims: [Claim]

    public init(style: BlockStyle, runs: [TextRun], idClaims: [Claim]) {
        self.style = style
        self.runs = runs
        self.idClaims = idClaims
    }
}

/// Turns editor paragraphs back into `[Block]` while keeping block ids stable.
///
/// Stable ids are what make Add Entry reliable: a section is its heading's id, so
/// ordinary typing must not give a heading a new id. Rules:
/// 1. Each paragraph proposes the id covering most of its characters
///    (ties: the earliest claim). Only ids from `previous` are accepted, so ids
///    pasted in from elsewhere cannot leak into this note.
/// 2. If several paragraphs propose the same id (a paragraph was split, or text
///    was duplicated), one keeps it: the one whose style still matches the
///    original block, then the one with more text, then the earliest. That way
///    pressing Return at the *start* of a heading leaves the id on the heading
///    text rather than the new empty line.
/// 3. Every other paragraph gets a fresh id.
///
/// The editor must re-tag its text with the returned ids after each reconcile.
public enum BlockReconciler {
    public static func reconcile(_ paragraphs: [EditorParagraph], previous: [Block]) -> [Block] {
        let previousStyle = Dictionary(previous.map { ($0.id, $0.style) }, uniquingKeysWith: { a, _ in a })

        // Rule 1: primary candidate per paragraph.
        let candidates: [UUID?] = paragraphs.map { paragraph in
            var best: EditorParagraph.Claim?
            for claim in paragraph.idClaims where previousStyle[claim.id] != nil {
                if best == nil || claim.characterCount > best!.characterCount { best = claim }
            }
            return best?.id
        }

        // Rule 2: one winner per id.
        var winner: [UUID: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard let id = candidate else { continue }
            guard let current = winner[id] else { winner[id] = index; continue }
            if score(paragraphs[index], id: id, previousStyle) > score(paragraphs[current], id: id, previousStyle) {
                winner[id] = index
            }
        }

        // Rule 3: assemble, minting ids for non-winners.
        return paragraphs.enumerated().map { index, paragraph in
            let keep = candidates[index].flatMap { winner[$0] == index ? $0 : nil }
            return Block(id: keep ?? UUID(), style: paragraph.style, runs: paragraph.runs)
        }
    }

    /// Higher is better. Earlier paragraphs win ties because comparison is strict.
    private static func score(
        _ paragraph: EditorParagraph,
        id: UUID,
        _ previousStyle: [UUID: BlockStyle]
    ) -> (Int, Int) {
        (previousStyle[id] == paragraph.style ? 1 : 0, paragraph.runs.plainText.count)
    }
}
