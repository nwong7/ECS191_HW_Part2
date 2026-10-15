import Foundation

/// Cleans clipboard text before it is pasted into a note.
///
/// The platform layer converts the clipboard (RTF, HTML or plain text) into
/// `TextRun`s, keeping only the traits Notes Redux supports. This step then
/// makes the text safe for the block model:
/// - every kind of line break (`\r\n`, `\r`, U+2028, U+2029) becomes `\n`, so
///   the editor splits it into paragraphs consistently;
/// - object-replacement characters (U+FFFC, left behind by images and other
///   attachments) and zero-width spaces are removed;
/// - non-breaking spaces become ordinary spaces;
/// - trailing line breaks are dropped (HTML and RTF copies usually end with
///   one, which would otherwise add a stray empty line).
///
/// "Without formatting" additionally removes every trait, so the text takes on
/// the formatting of where it is pasted.
public enum PasteNormalizer {
    public static func normalized(_ runs: [TextRun], keepFormatting: Bool) -> [TextRun] {
        var cleaned = runs.map { run in
            TextRun(clean(run.text), traits: keepFormatting ? run.traits : [])
        }
        .normalized()

        // Drop trailing line breaks across run boundaries.
        while let last = cleaned.last {
            var text = last.text
            while text.last == "\n" { text.removeLast() }
            if text.isEmpty {
                cleaned.removeLast()
            } else {
                cleaned[cleaned.count - 1].text = text
                break
            }
        }
        return cleaned
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
