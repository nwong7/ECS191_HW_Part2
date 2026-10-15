import Foundation

/// Text captured by Add Entry, already split into lines.
///
/// Each line becomes one body block when inserted, which is how line breaks are
/// preserved. Inline formatting in `lines` is kept as-is.
public struct Entry: Hashable, Sendable {
    public private(set) var lines: [[TextRun]]

    /// Builds an entry from runs that may contain line breaks (`\n`, `\r\n`, etc.).
    ///
    /// Whitespace surrounding the *whole* entry is trimmed (leading/trailing blank
    /// lines, leading spaces of the first line, trailing spaces of the last line),
    /// matching what users expect from a text field. Everything in between,
    /// including blank lines and indentation, is preserved exactly.
    public init(runs: [TextRun]) {
        var lines: [[TextRun]] = [[]]
        for run in runs {
            let pieces = run.text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            for (i, piece) in pieces.enumerated() {
                if i > 0 { lines.append([]) }
                if !piece.isEmpty {
                    lines[lines.count - 1].append(TextRun(String(piece), traits: run.traits))
                }
            }
        }
        lines = lines.map { $0.normalized() }

        while let first = lines.first, first.plainText.allSatisfy(\.isWhitespace) { lines.removeFirst() }
        while let last = lines.last, last.plainText.allSatisfy(\.isWhitespace) { lines.removeLast() }
        if !lines.isEmpty {
            lines[0] = lines[0].trimmingLeadingWhitespace()
            lines[lines.count - 1] = lines[lines.count - 1].trimmingTrailingWhitespace()
        }
        self.lines = lines
    }

    public init(plainText: String) {
        self.init(runs: [TextRun(plainText)])
    }

    /// True when there is nothing but whitespace to insert.
    public var isEmpty: Bool { lines.isEmpty }
}

extension Array where Element == TextRun {
    func trimmingLeadingWhitespace() -> [TextRun] {
        var runs = self
        while let first = runs.first {
            let trimmed = String(first.text.drop(while: \.isWhitespace))
            if trimmed.isEmpty {
                runs.removeFirst()
            } else {
                runs[0].text = trimmed
                break
            }
        }
        return runs
    }

    func trimmingTrailingWhitespace() -> [TextRun] {
        var runs = self
        while let last = runs.last {
            var text = last.text
            while let c = text.last, c.isWhitespace { text.removeLast() }
            if text.isEmpty {
                runs.removeLast()
            } else {
                runs[runs.count - 1].text = text
                break
            }
        }
        return runs
    }
}
