import Foundation

/// Inline formatting supported by Notes Redux.
///
/// The set is intentionally small. Pasted rich text is reduced to these traits;
/// fonts, colors and sizes from other apps are dropped rather than half-kept.
public enum Trait: String, Codable, CaseIterable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
}

/// A span of text that shares one set of traits.
///
/// Invariant: `text` never contains line breaks. Line structure is expressed by
/// separate `Block`s, so a run always belongs to exactly one paragraph.
public struct TextRun: Codable, Hashable, Sendable {
    public var text: String
    public var traits: Set<Trait>

    public init(_ text: String, traits: Set<Trait> = []) {
        self.text = text
        self.traits = traits
    }
}

extension Array where Element == TextRun {
    /// Concatenated text of all runs, without formatting.
    public var plainText: String { map(\.text).joined() }

    /// Removes empty runs and merges neighbours that share the same traits.
    /// Keeps stored JSON compact and makes equality checks meaningful.
    public func normalized() -> [TextRun] {
        var result: [TextRun] = []
        for run in self where !run.text.isEmpty {
            if let last = result.last, last.traits == run.traits {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}
