import Foundation

/// Location of one paragraph inside editor text, in UTF-16 offsets (the unit
/// used by `NSString`, `NSRange` and `UITextView`).
public struct ParagraphRange: Hashable, Sendable {
    /// The paragraph's text, without its line terminator.
    public let content: Range<Int>
    /// `content` plus the terminator (if any).
    public let enclosing: Range<Int>

    public init(content: Range<Int>, enclosing: Range<Int>) {
        self.content = content
        self.enclosing = enclosing
    }
}

/// Splits editor text into paragraphs exactly the way `RichTextCodec` joins
/// blocks: one paragraph per block, separated by a single line terminator.
///
/// Unlike `NSString.enumerateSubstrings(.byParagraphs)`, this *always* reports
/// the final paragraph, even when it is empty. Without that, a note ending in a
/// blank line would lose that block on every round trip through the editor.
public enum ParagraphSplitter {
    private static let lineFeed: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D
    private static let lineSeparator: UInt16 = 0x2028
    private static let paragraphSeparator: UInt16 = 0x2029

    public static func paragraphs(in text: String) -> [ParagraphRange] {
        paragraphs(utf16: Array(text.utf16))
    }

    public static func paragraphs(utf16 units: [UInt16]) -> [ParagraphRange] {
        var result: [ParagraphRange] = []
        var start = 0
        var i = 0
        while i < units.count {
            let unit = units[i]
            guard unit == lineFeed || unit == carriageReturn || unit == lineSeparator || unit == paragraphSeparator
            else { i += 1; continue }
            // Treat CRLF (e.g. from pasted Windows text) as one terminator.
            let length = (unit == carriageReturn && i + 1 < units.count && units[i + 1] == lineFeed) ? 2 : 1
            result.append(ParagraphRange(content: start..<i, enclosing: start..<(i + length)))
            i += length
            start = i
        }
        result.append(ParagraphRange(content: start..<units.count, enclosing: start..<units.count))
        return result
    }

    /// Index of the paragraph containing a caret at `location`.
    /// A caret just after a terminator belongs to the next paragraph.
    public static func index(containing location: Int, in paragraphs: [ParagraphRange]) -> Int {
        paragraphs.firstIndex { location < $0.enclosing.upperBound } ?? max(paragraphs.count - 1, 0)
    }
}

/// Small editing policies shared by the editor, kept here so they are tested.
public enum EditorRules {
    /// Whether pressing Return at `location` should make the new line body text:
    /// only when the caret is at the end of a heading or subheading, as in most
    /// editors. Elsewhere the new line keeps the current paragraph's style.
    public static func returnEndsHeading(
        at location: Int,
        paragraphs: [ParagraphRange],
        styleOfParagraph: (Int) -> BlockStyle
    ) -> Bool {
        guard !paragraphs.isEmpty else { return false }
        let index = ParagraphSplitter.index(containing: location, in: paragraphs)
        return styleOfParagraph(index).isHeading && location == paragraphs[index].content.upperBound
    }
}
