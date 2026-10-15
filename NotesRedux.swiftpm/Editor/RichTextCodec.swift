import UIKit
import NotesReduxCore

/// Custom attributes that carry the note model inside the editor's text.
///
/// Fonts are *derived* from these and never read back: the style and traits
/// attributes are the source of truth, so headings (which render bold) are not
/// mistaken for bold body text.
extension NSAttributedString.Key {
    /// UUID string of the block this character belongs to.
    static let noteBlockID = NSAttributedString.Key("NotesRedux.blockID")
    /// `BlockStyle.rawValue` of the paragraph.
    static let noteBlockStyle = NSAttributedString.Key("NotesRedux.blockStyle")
    /// Comma-separated `Trait.rawValue`s, e.g. "bold,italic".
    static let noteTraits = NSAttributedString.Key("NotesRedux.traits")
}

/// Converts between `[Block]` and the editor's attributed text.
///
/// Layout: each block's runs, then a single "\n" terminator (except after the
/// last block). Every character, terminators included, is tagged with the
/// block's id and style. `ParagraphSplitter` (tested in NotesReduxCore) is the
/// exact inverse of this join.
enum RichTextCodec {

    // MARK: Encoding

    static func attributedString(from blocks: [Block]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            for run in block.runs {
                result.append(NSAttributedString(
                    string: run.text,
                    attributes: attributes(style: block.style, traits: run.traits, blockID: block.id)))
            }
            if index < blocks.count - 1 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: attributes(style: block.style, traits: [], blockID: block.id)))
            }
        }
        return result
    }

    static func attributes(style: BlockStyle, traits: Set<Trait>, blockID: UUID?) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: style, traits: traits),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle(for: style),
            .noteBlockStyle: style.rawValue,
            .noteTraits: encode(traits),
        ]
        if let blockID { attrs[.noteBlockID] = blockID.uuidString }
        if traits.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if traits.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    static func font(for style: BlockStyle, traits: Set<Trait>) -> UIFont {
        let base: UIFont
        var symbolic: UIFontDescriptor.SymbolicTraits = []
        switch style {
        case .body:
            base = .preferredFont(forTextStyle: .body)
        case .heading:
            base = .preferredFont(forTextStyle: .title2)
            symbolic.insert(.traitBold)
        case .subheading:
            base = .preferredFont(forTextStyle: .title3)
            symbolic.insert(.traitBold)
        }
        if traits.contains(.bold) { symbolic.insert(.traitBold) }
        if traits.contains(.italic) { symbolic.insert(.traitItalic) }
        guard !symbolic.isEmpty,
              let descriptor = base.fontDescriptor.withSymbolicTraits(symbolic)
        else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    static func paragraphStyle(for style: BlockStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        switch style {
        case .body: paragraph.paragraphSpacingBefore = 0
        case .heading: paragraph.paragraphSpacingBefore = 12
        case .subheading: paragraph.paragraphSpacingBefore = 8
        }
        paragraph.paragraphSpacing = 2
        return paragraph
    }

    static func encode(_ traits: Set<Trait>) -> String {
        traits.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func decodeTraits(_ value: Any?) -> Set<Trait> {
        guard let string = value as? String, !string.isEmpty else { return [] }
        return Set(string.split(separator: ",").compactMap { Trait(rawValue: String($0)) })
    }

    // MARK: Decoding

    static func style(at location: Int, in text: NSAttributedString) -> BlockStyle? {
        guard location >= 0, location < text.length else { return nil }
        return (text.attribute(.noteBlockStyle, at: location, effectiveRange: nil) as? String)
            .flatMap(BlockStyle.init(rawValue:))
    }

    static func traits(at location: Int, in text: NSAttributedString) -> Set<Trait> {
        guard location >= 0, location < text.length else { return [] }
        return decodeTraits(text.attribute(.noteTraits, at: location, effectiveRange: nil))
    }

    static func blockID(at location: Int, in text: NSAttributedString) -> UUID? {
        guard location >= 0, location < text.length else { return nil }
        return (text.attribute(.noteBlockID, at: location, effectiveRange: nil) as? String)
            .flatMap(UUID.init(uuidString:))
    }

    /// A paragraph's style is the style of its first character (content or, for
    /// an empty line, its terminator). Paragraphs with no characters at all (an
    /// empty last line) have no stored style; the caller supplies `fallback`.
    static func style(of paragraph: ParagraphRange, in text: NSAttributedString, fallback: BlockStyle = .body) -> BlockStyle {
        style(at: paragraph.enclosing.lowerBound, in: text) ?? fallback
    }

    /// Reads every paragraph back for `BlockReconciler`.
    static func editorParagraphs(
        from text: NSAttributedString,
        lastLineFallbackStyle: BlockStyle = .body
    ) -> (ranges: [ParagraphRange], paragraphs: [EditorParagraph]) {
        let string = text.string as NSString
        let ranges = ParagraphSplitter.paragraphs(in: text.string)
        let paragraphs = ranges.map { range -> EditorParagraph in
            var runs: [TextRun] = []
            text.enumerateAttribute(.noteTraits, in: NSRange(range.content), options: []) { value, span, _ in
                runs.append(TextRun(string.substring(with: span), traits: decodeTraits(value)))
            }

            var claims: [EditorParagraph.Claim] = []
            text.enumerateAttribute(.noteBlockID, in: NSRange(range.enclosing), options: []) { value, span, _ in
                guard let id = (value as? String).flatMap(UUID.init(uuidString:)) else { return }
                if let i = claims.firstIndex(where: { $0.id == id }) {
                    claims[i].characterCount += span.length
                } else {
                    claims.append(.init(id: id, characterCount: span.length))
                }
            }

            return EditorParagraph(
                style: style(of: range, in: text, fallback: lastLineFallbackStyle),
                runs: runs,
                idClaims: claims)
        }
        return (ranges, paragraphs)
    }
}
