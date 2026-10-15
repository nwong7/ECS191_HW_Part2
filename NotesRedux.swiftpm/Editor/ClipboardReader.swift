import UIKit
import UniformTypeIdentifiers
import NotesReduxCore

/// Reads the system clipboard for the Paste menu.
///
/// "With formatting" prefers rich data (RTF, HTML, RTFD) and keeps only the
/// traits Notes Redux supports: bold, italic, underline and strikethrough.
/// Fonts, sizes, colours and images are dropped by design. "Without
/// formatting" uses the plain-text representation.
///
/// Note: iOS asks the user for permission ("Allow Paste") when an app reads
/// another app's clipboard from its own button. The system Edit-menu Paste
/// doesn't ask, but always pastes plain text in this editor.
enum ClipboardReader {
    static func read(keepFormatting: Bool) -> [TextRun]? {
        let pasteboard = UIPasteboard.general
        if keepFormatting, let attributed = attributedString(from: pasteboard) {
            return runs(from: attributed)
        }
        if let string = pasteboard.string {
            return [TextRun(string)]
        }
        // Rich-only clipboard (rare): fall back to its plain text.
        if let attributed = attributedString(from: pasteboard) {
            return [TextRun(attributed.string)]
        }
        return nil
    }

    private static func attributedString(from pasteboard: UIPasteboard) -> NSAttributedString? {
        let candidates: [(UTType, NSAttributedString.DocumentType)] = [
            (.rtf, .rtf),
            (.html, .html),
            (.flatRTFD, .rtfd),
        ]
        for (type, documentType) in candidates {
            guard let data = pasteboard.data(forPasteboardType: type.identifier) else { continue }
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil) {
                return attributed
            }
        }
        return nil
    }

    /// Maps attributes to supported traits, one run per attribute span.
    static func runs(from attributed: NSAttributedString) -> [TextRun] {
        let string = attributed.string as NSString
        var runs: [TextRun] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            var traits: Set<Trait> = []
            if let font = attrs[.font] as? UIFont {
                let symbolic = font.fontDescriptor.symbolicTraits
                if symbolic.contains(.traitBold) { traits.insert(.bold) }
                if symbolic.contains(.traitItalic) { traits.insert(.italic) }
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 { traits.insert(.underline) }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 { traits.insert(.strikethrough) }
            runs.append(TextRun(string.substring(with: range), traits: traits))
        }
        return runs
    }
}
