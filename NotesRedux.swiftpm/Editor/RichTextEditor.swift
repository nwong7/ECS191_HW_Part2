import SwiftUI
import UIKit
import NotesReduxCore

/// Bridge between SwiftUI controls (format bar, later the outline) and the
/// UIKit text view. Also publishes the caret's current formatting so toolbar
/// buttons can show their on/off state.
@MainActor
@Observable
final class RichTextController {
    private(set) var currentStyle: BlockStyle = .body
    private(set) var activeTraits: Set<Trait> = []
    private(set) var isEditing = false
    /// Heading id of the section at the top of the visible text (nil before the
    /// first heading). Drives the outline's highlight.
    private(set) var currentSectionID: UUID?

    @ObservationIgnored fileprivate weak var coordinator: RichTextEditor.Coordinator?

    func setStyle(_ style: BlockStyle) { coordinator?.applyStyle(style) }
    func toggle(_ trait: Trait) { coordinator?.toggle(trait) }
    func endEditing() { coordinator?.textView?.resignFirstResponder() }
    /// Scrolls to the given blocks and briefly highlights them.
    func reveal(blockIDs: [UUID]) { coordinator?.reveal(blockIDs: blockIDs) }
    /// Scrolls so the section's heading is at the top of the screen.
    func scrollTo(sectionID: UUID) { coordinator?.scrollTo(sectionID: sectionID) }

    /// Pastes the clipboard at the caret (replacing any selection).
    /// With formatting: keeps bold/italic/underline/strikethrough from the
    /// source. Without: plain text that takes on the surrounding formatting.
    func paste(keepFormatting: Bool) {
        guard let runs = ClipboardReader.read(keepFormatting: keepFormatting) else { return }
        let cleaned = PasteNormalizer.normalized(runs, keepFormatting: keepFormatting)
        coordinator?.paste(cleaned, applyTraits: keepFormatting)
    }

    fileprivate func publish(style: BlockStyle, traits: Set<Trait>) {
        if currentStyle != style { currentStyle = style }
        if activeTraits != traits { activeTraits = traits }
    }

    fileprivate func publish(isEditing: Bool) {
        if self.isEditing != isEditing { self.isEditing = isEditing }
    }

    fileprivate func publish(currentSectionID: UUID?) {
        if self.currentSectionID != currentSectionID { self.currentSectionID = currentSectionID }
    }
}

/// Rich-text editor for a note's blocks, backed by `UITextView`.
///
/// Why UITextView rather than SwiftUI `TextEditor`: we need per-paragraph custom
/// attributes (block ids), exact control over typing attributes, and later
/// scroll-to-range for section navigation.
///
/// Data flow: `blocks` in → text view. User edits → `BlockReconciler` →
/// `onChange(blocks)`. When `blocks` arrives equal to what the editor last
/// produced, nothing is reloaded, so typing never resets the caret. A different
/// `blocks` value (e.g. an Add Entry from elsewhere) reloads the text.
struct RichTextEditor: UIViewRepresentable {
    var blocks: [Block]
    var controller: RichTextController
    var onChange: ([Block]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        // Formatting goes through our own format bar so every change is captured
        // in the custom attributes. This also makes system paste plain-text.
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 32, right: 12)
        textView.accessibilityLabel = "Note text"

        context.coordinator.textView = textView
        context.coordinator.controller = controller
        controller.coordinator = context.coordinator
        context.coordinator.load(blocks)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        if blocks != context.coordinator.currentBlocks {
            context.coordinator.load(blocks)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        weak var textView: UITextView?
        weak var controller: RichTextController?
        var onChange: ([Block]) -> Void

        /// Blocks matching the text view's current contents.
        private(set) var currentBlocks: [Block] = []
        /// Paragraph ranges of the current text, one per block. Refreshed on
        /// every load and commit (attribute-only changes don't affect them).
        private var paragraphRanges: [ParagraphRange] = []
        /// After jumping to a section from the outline, keep it highlighted even
        /// if it can't scroll to the very top (end of note). Cleared when the
        /// user scrolls or moves the caret.
        private var pinnedSectionID: UUID?
        /// Identifies the active reveal highlight; nil when none is shown.
        private var highlightToken: UUID?
        /// True while we change the text storage ourselves; suppresses delegate work.
        private var isApplying = false
        /// Set when Return is pressed at the end of a heading: the new line
        /// starting at this location becomes body text.
        private var pendingBodyLocation: Int?
        /// Style/traits chosen in the format bar while the caret is on a line
        /// with no characters yet. Cleared when the caret moves.
        private var explicitTypingStyle: BlockStyle?
        private var explicitTypingTraits: Set<Trait>?

        init(onChange: @escaping ([Block]) -> Void) {
            self.onChange = onChange
        }

        // MARK: Loading

        func load(_ blocks: [Block]) {
            guard let textView else { return }
            isApplying = true
            let selection = textView.selectedRange
            textView.attributedText = RichTextCodec.attributedString(from: blocks)
            currentBlocks = blocks
            paragraphRanges = ParagraphSplitter.paragraphs(in: textView.textStorage.string)
            let length = textView.textStorage.length
            let location = min(selection.location, length)
            textView.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            isApplying = false
            // Publishing during a SwiftUI view update is not allowed; defer it.
            refreshTypingAttributes(publish: false)
            DispatchQueue.main.async { [weak self] in
                self?.publishState()
                self?.updateVisibleSection()
            }
        }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            pendingBodyLocation = nil
            if text == "\n", range.length == 0 {
                let storage = textView.textStorage
                let ranges = ParagraphSplitter.paragraphs(in: storage.string)
                let endsHeading = EditorRules.returnEndsHeading(at: range.location, paragraphs: ranges) {
                    RichTextCodec.style(of: ranges[$0], in: storage)
                }
                if endsHeading { pendingBodyLocation = range.location + 1 }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplying else { return }
            var forced: [Int] = []
            if let location = pendingBodyLocation {
                pendingBodyLocation = nil
                if let index = makeBodyParagraph(at: location) { forced.append(index) }
            }
            commitEdits(forceRestyle: forced)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplying else { return }
            explicitTypingStyle = nil
            explicitTypingTraits = nil
            pinnedSectionID = nil
            clearHighlight()
            refreshTypingAttributes(publish: true)
        }

        // UITextViewDelegate inherits UIScrollViewDelegate.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isApplying else { return }
            updateVisibleSection()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pinnedSectionID = nil
            clearHighlight()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            controller?.publish(isEditing: true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            controller?.publish(isEditing: false)
        }

        // MARK: Format bar actions

        func applyStyle(_ style: BlockStyle) {
            guard let textView else { return }
            let storage = textView.textStorage
            let ranges = ParagraphSplitter.paragraphs(in: storage.string)
            let indices = paragraphIndices(for: textView.selectedRange, in: ranges)

            isApplying = true
            storage.beginEditing()
            for i in indices where !ranges[i].enclosing.isEmpty {
                storage.addAttribute(.noteBlockStyle, value: style.rawValue, range: NSRange(ranges[i].enclosing))
            }
            storage.endEditing()
            isApplying = false

            if let last = indices.last, ranges[last].enclosing.isEmpty {
                explicitTypingStyle = style
            }
            commitEdits(forceRestyle: Array(indices))
        }

        func toggle(_ trait: Trait) {
            guard let textView else { return }
            let storage = textView.textStorage
            let selection = textView.selectedRange

            guard selection.length > 0 else {
                // No selection: affect what is typed next.
                var traits = RichTextCodec.decodeTraits(textView.typingAttributes[.noteTraits])
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                explicitTypingTraits = traits
                refreshTypingAttributes(publish: true)
                return
            }

            var everyCharacterHasTrait = true
            var spans: [(NSRange, Set<Trait>)] = []
            storage.enumerateAttribute(.noteTraits, in: selection, options: []) { value, span, _ in
                let traits = RichTextCodec.decodeTraits(value)
                if !traits.contains(trait) { everyCharacterHasTrait = false }
                spans.append((span, traits))
            }

            isApplying = true
            storage.beginEditing()
            for (span, traits) in spans {
                var updated = traits
                if everyCharacterHasTrait { updated.remove(trait) } else { updated.insert(trait) }
                storage.addAttribute(.noteTraits, value: RichTextCodec.encode(updated), range: span)
            }
            storage.endEditing()
            isApplying = false

            let ranges = ParagraphSplitter.paragraphs(in: storage.string)
            commitEdits(forceRestyle: Array(paragraphIndices(for: selection, in: ranges)))
        }

        // MARK: Paste

        /// Inserts `runs` at the selection. The text goes in through
        /// `insertText`, so typing undo covers it and it picks up the current
        /// paragraph's id and style. With `applyTraits`, each run's formatting
        /// is then applied exactly. Lines after the first that land in a
        /// heading become body text, so pasting a list under a heading doesn't
        /// turn every line into a heading.
        func paste(_ runs: [TextRun], applyTraits: Bool) {
            guard let textView else { return }
            let text = runs.plainText
            guard !text.isEmpty else { return }
            if !textView.isFirstResponder { textView.becomeFirstResponder() }

            let storage = textView.textStorage
            let start = textView.selectedRange.location
            let before = ParagraphSplitter.paragraphs(in: storage.string)
            let pastingIntoHeading = RichTextCodec.style(
                of: before[ParagraphSplitter.index(containing: start, in: before)], in: storage).isHeading

            textView.insertText(text)
            let length = (text as NSString).length
            guard start + length <= storage.length else { return }

            let after = ParagraphSplitter.paragraphs(in: storage.string)
            let first = ParagraphSplitter.index(containing: start, in: after)
            let last = ParagraphSplitter.index(containing: start + length, in: after)

            isApplying = true
            storage.beginEditing()
            if applyTraits {
                var offset = start
                for run in runs {
                    let runLength = (run.text as NSString).length
                    storage.addAttribute(.noteTraits, value: RichTextCodec.encode(run.traits),
                                         range: NSRange(location: offset, length: runLength))
                    offset += runLength
                }
            }
            if pastingIntoHeading && last > first {
                for i in (first + 1)...last where !after[i].enclosing.isEmpty {
                    storage.addAttribute(.noteBlockStyle, value: BlockStyle.body.rawValue,
                                         range: NSRange(after[i].enclosing))
                }
            }
            storage.endEditing()
            isApplying = false

            commitEdits(forceRestyle: Array(first...last))
        }

        // MARK: Navigation

        /// Scrolls so the given blocks are visible and flashes a highlight on
        /// them. Blocks are found by id, so this works however the note changed.
        func reveal(blockIDs: [UUID]) {
            guard let textView else { return }
            let indices = blockIDs.compactMap { id in currentBlocks.firstIndex { $0.id == id } }
            guard let first = indices.min(), let last = indices.max() else { return }
            let ranges = ParagraphSplitter.paragraphs(in: textView.textStorage.string)
            guard last < ranges.count else { return }

            let lower = ranges[first].content.lowerBound
            let upper = max(ranges[last].content.upperBound, lower)
            let range = NSRange(lower..<upper)
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(range)
            flashHighlight(range)
        }

        /// Scrolls so the heading of `sectionID` sits at the top of the visible
        /// area (or as close as the end of the note allows) and flashes it.
        func scrollTo(sectionID: UUID) {
            guard let textView,
                  let index = currentBlocks.firstIndex(where: { $0.id == sectionID }),
                  index < paragraphRanges.count,
                  let start = textView.position(from: textView.beginningOfDocument,
                                                offset: paragraphRanges[index].content.lowerBound)
            else { return }

            textView.layoutIfNeeded()
            let caret = textView.caretRect(for: start)
            let content = NSRange(paragraphRanges[index].content)
            if caret.isNull || caret.isInfinite {
                textView.scrollRangeToVisible(content)
            } else {
                let insets = textView.adjustedContentInset
                let minY = -insets.top
                let maxY = max(minY, textView.contentSize.height - textView.bounds.height + insets.bottom)
                let target = min(max(caret.minY - 8 - insets.top, minY), maxY)
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: target), animated: true)
            }
            pinnedSectionID = sectionID
            controller?.publish(currentSectionID: sectionID)
            flashHighlight(content)
        }

        /// Publishes the section whose content is at the top of the visible text.
        private func updateVisibleSection() {
            guard let textView else { return }
            if let pinnedSectionID {
                controller?.publish(currentSectionID: pinnedSectionID)
                return
            }
            let insets = textView.adjustedContentInset
            let point = CGPoint(
                x: textView.textContainerInset.left + 1,
                y: textView.contentOffset.y + insets.top + textView.textContainerInset.top + 1)
            guard let position = textView.closestPosition(to: point) else { return }
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            let section = SectionIndex.section(atTextOffset: offset, paragraphs: paragraphRanges, blocks: currentBlocks)
            controller?.publish(currentSectionID: section?.id)
        }

        /// Temporary background colour marking revealed text. It is not part of
        /// the note model: it is never read back, and any edit to the paragraph
        /// restyles it away. It stays until the user scrolls or taps (so there
        /// is time to see where an entry landed), or for at most 8 seconds.
        private func flashHighlight(_ range: NSRange) {
            guard let storage = textView?.textStorage, range.length > 0 else { return }
            clearHighlight()
            isApplying = true
            storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: range)
            isApplying = false
            let token = UUID()
            highlightToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.highlightToken == token else { return }
                self.clearHighlight()
            }
        }

        private func clearHighlight() {
            guard highlightToken != nil, let storage = textView?.textStorage else { return }
            highlightToken = nil
            isApplying = true
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
            isApplying = false
        }

        // MARK: Core edit pipeline

        /// Re-derives blocks from the text, keeps ids stable, normalizes
        /// attributes, and reports the new blocks.
        private func commitEdits(forceRestyle: [Int] = []) {
            guard let textView else { return }
            // Never touch attributes while the keyboard is composing (e.g. CJK
            // input); this runs again when composition finishes.
            guard textView.markedTextRange == nil else { return }

            let storage = textView.textStorage
            let (ranges, paragraphs) = RichTextCodec.editorParagraphs(
                from: storage, lastLineFallbackStyle: explicitTypingStyle ?? .body)
            let blocks = BlockReconciler.reconcile(paragraphs, previous: currentBlocks)
            restyle(storage, ranges: ranges, blocks: blocks, force: Set(forceRestyle))

            let changed = blocks != currentBlocks
            currentBlocks = blocks
            paragraphRanges = ranges
            refreshTypingAttributes(publish: true)
            updateVisibleSection()
            if changed { onChange(blocks) }
        }

        /// Makes every paragraph's attributes consistent with its block: one id,
        /// one style, and fonts derived from style + traits. Only paragraphs that
        /// are inconsistent (or forced) are rewritten, to keep typing fast.
        private func restyle(_ storage: NSTextStorage, ranges: [ParagraphRange], blocks: [Block], force: Set<Int>) {
            guard let textView else { return }
            let selection = textView.selectedRange
            isApplying = true
            storage.beginEditing()
            for (index, (range, block)) in zip(ranges, blocks).enumerated() {
                let full = NSRange(range.enclosing)
                guard full.length > 0 else { continue }
                guard force.contains(index) || !isUniform(storage, full, block) else { continue }

                var spans: [(NSRange, Set<Trait>)] = []
                storage.enumerateAttribute(.noteTraits, in: full, options: []) { value, span, _ in
                    spans.append((span, RichTextCodec.decodeTraits(value)))
                }
                for (span, traits) in spans {
                    storage.setAttributes(
                        RichTextCodec.attributes(style: block.style, traits: traits, blockID: block.id),
                        range: span)
                }
            }
            storage.endEditing()
            textView.selectedRange = selection
            isApplying = false
        }

        private func isUniform(_ storage: NSTextStorage, _ full: NSRange, _ block: Block) -> Bool {
            var effective = NSRange()
            let id = storage.attribute(.noteBlockID, at: full.location, longestEffectiveRange: &effective, in: full) as? String
            guard id == block.id.uuidString, effective == full else { return false }
            let style = storage.attribute(.noteBlockStyle, at: full.location, longestEffectiveRange: &effective, in: full) as? String
            return style == block.style.rawValue && effective == full
        }

        /// After Return at the end of a heading: turn the new line into body text
        /// and drop the heading's id from it, so it becomes a new block.
        private func makeBodyParagraph(at location: Int) -> Int? {
            guard let textView else { return nil }
            let storage = textView.textStorage
            let ranges = ParagraphSplitter.paragraphs(in: storage.string)
            let index = ParagraphSplitter.index(containing: location, in: ranges)
            let range = ranges[index]
            if range.enclosing.isEmpty {
                explicitTypingStyle = .body
                explicitTypingTraits = []
            } else {
                isApplying = true
                storage.setAttributes(
                    RichTextCodec.attributes(style: .body, traits: [], blockID: nil),
                    range: NSRange(range.enclosing))
                isApplying = false
            }
            return index
        }

        // MARK: Typing attributes

        /// Makes newly typed text belong to the caret's paragraph (its id and
        /// style) with the formatting of the neighbouring character. Without this,
        /// UIKit would copy attributes from the previous paragraph's line break.
        private func refreshTypingAttributes(publish: Bool) {
            guard let textView else { return }
            let storage = textView.textStorage
            let ranges = ParagraphSplitter.paragraphs(in: storage.string)
            let location = textView.selectedRange.location
            let range = ranges[ParagraphSplitter.index(containing: location, in: ranges)]

            let style: BlockStyle
            let blockID: UUID?
            if range.enclosing.isEmpty {
                style = explicitTypingStyle ?? .body
                blockID = nil
            } else {
                style = RichTextCodec.style(of: range, in: storage)
                blockID = RichTextCodec.blockID(at: range.enclosing.lowerBound, in: storage)
            }

            let traits: Set<Trait>
            if let explicit = explicitTypingTraits {
                traits = explicit
            } else if location > range.content.lowerBound {
                traits = RichTextCodec.traits(at: location - 1, in: storage)
            } else if !range.content.isEmpty {
                traits = RichTextCodec.traits(at: location, in: storage)
            } else {
                traits = []
            }

            textView.typingAttributes = RichTextCodec.attributes(style: style, traits: traits, blockID: blockID)
            if publish { publishState() }
        }

        private func publishState() {
            guard let textView else { return }
            let attrs = textView.typingAttributes
            let style = (attrs[.noteBlockStyle] as? String).flatMap(BlockStyle.init(rawValue:)) ?? .body
            let selection = textView.selectedRange
            let traits = selection.length > 0
                ? RichTextCodec.traits(at: selection.location, in: textView.textStorage)
                : RichTextCodec.decodeTraits(attrs[.noteTraits])
            controller?.publish(style: style, traits: traits)
        }

        /// Paragraphs touched by `selection`. A selection ending right after a
        /// line break does not include the following paragraph.
        private func paragraphIndices(for selection: NSRange, in ranges: [ParagraphRange]) -> ClosedRange<Int> {
            let first = ParagraphSplitter.index(containing: selection.location, in: ranges)
            let endLocation = selection.length > 0 ? selection.location + selection.length - 1 : selection.location
            let last = ParagraphSplitter.index(containing: endLocation, in: ranges)
            return first...max(first, last)
        }
    }
}
