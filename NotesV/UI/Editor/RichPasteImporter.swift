import AppKit

/// Turns rich text from the clipboard into a note, so that notes copied from Apple Notes keep their
/// structure. Other apps' text works the same way.
///
/// Foreign text has no paragraph styles of its own, only fonts and lists, so the styles are
/// worked out from those. Fonts and colors are then replaced by the app's own.
@MainActor
enum RichPasteImporter {
    /// Text at these sizes, relative to the body text, counts as a heading.
    /// Apple Notes copies titles at 20 points and body text at 13.
    private static let titleRatio: CGFloat = 1.45
    private static let headingRatio: CGFloat = 1.18
    private static let subheadingRatio: CGFloat = 1.05

    /// The marker of a text list, which rich text keeps between two tabs: `\t•\tItem`.
    private static let textListMarkerPattern = #"^\t[^\t]*\t"#

    /// A list marker or checkbox at the start of a line. Rich text keeps these as ordinary characters.
    private static let markerPattern = #"^[\t ]*(?:[•◦▪▫‣∙·*–—-]|\d{1,3}[.)]|[☐☑☒✓✔◻◼])[\t ]+"#

    /// The note on the clipboard, or `nil` if there is no rich text to read.
    static func document(from pasteboard: NSPasteboard) -> NoteDocument? {
        if let data = pasteboard.data(forType: .rtfd), let text = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return document(from: text)
        }
        if let data = pasteboard.data(forType: .rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil) {
            return document(from: text)
        }
        if let data = pasteboard.data(forType: .html), let text = attributedString(html: data) {
            return document(from: text)
        }
        return nil
    }

    static func attributedString(html data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
    }

    static func document(from source: NSAttributedString) -> NoteDocument {
        let text = NSMutableAttributedString(attributedString: source)
        removeAttachments(from: text)
        let bodySize = mostCommonFontSize(in: text)

        // Backwards, because removing a marker moves everything after it.
        for paragraph in AttributedStringConverter.paragraphs(in: text.string as NSString).reversed() where paragraph.full.length > 0 {
            let attributes = text.attributes(at: paragraph.full.location, effectiveRange: nil)
            if AttributedStringConverter.tableCell(in: attributes) != nil {
                markInlineStyles(in: paragraph.full, of: text, includingBold: true)
                continue
            }

            let line = (text.string as NSString).substring(with: paragraph.content)
            let isInTextList = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.isEmpty == false
            let marker = listMarker(in: line, isInTextList: isInTextList)
            let format = paragraphFormat(of: paragraph, in: text, marker: marker, bodySize: bodySize)

            markInlineStyles(in: paragraph.full, of: text, includingBold: format.kind == .style(.body) || format.kind.listKind != nil)
            text.addAttribute(.notesParagraphKind, value: format.kind.attributeValue, range: paragraph.full)
            text.addAttribute(.notesListLevel, value: format.level, range: paragraph.full)
            text.addAttribute(.notesChecked, value: format.isChecked, range: paragraph.full)

            if format.kind.listKind != nil, !marker.isEmpty {
                text.deleteCharacters(in: NSRange(location: paragraph.full.location, length: (marker as NSString).length))
            }
        }

        return NoteDocument(blocks: trimmingEmptyParagraphs(AttributedStringConverter.document(from: text).blocks))
    }

    // MARK: - Paragraphs

    /// The marker text a line starts with, or an empty string. A text list item can have a second
    /// marker after its own, like the checkboxes in a list without bullets.
    private static func listMarker(in line: String, isInTextList: Bool) -> String {
        var marker = ""
        var rest = line[...]
        for pattern in isInTextList ? [textListMarkerPattern, markerPattern] : [markerPattern] {
            if let range = rest.range(of: pattern, options: .regularExpression) {
                marker += rest[range]
                rest = rest[range.upperBound...]
            }
        }
        return marker
    }

    private static func paragraphFormat(
        of paragraph: AttributedStringConverter.Paragraph,
        in text: NSAttributedString,
        marker: String,
        bodySize: CGFloat
    ) -> ParagraphAttributes {
        let style = text.attribute(.paragraphStyle, at: paragraph.full.location, effectiveRange: nil) as? NSParagraphStyle
        let textList = style?.textLists.last

        if textList != nil || !marker.isEmpty {
            let level = max((style?.textLists.count ?? 1) - 1, 0)
            return listFormat(textList: textList, marker: marker, level: level)
        }

        var largestSize: CGFloat = 0
        var isMonospaced = paragraph.content.length > 0
        text.enumerateAttribute(.font, in: paragraph.content) { value, _, _ in
            guard let font = value as? NSFont else { return }
            largestSize = max(largestSize, font.pointSize)
            if !font.isFixedPitch { isMonospaced = false }
        }

        if isMonospaced { return ParagraphAttributes(kind: .style(.monostyled)) }
        let ratio = bodySize > 0 ? largestSize / bodySize : 1
        if ratio >= titleRatio { return ParagraphAttributes(kind: .style(.title)) }
        if ratio >= headingRatio { return ParagraphAttributes(kind: .style(.heading)) }
        if ratio >= subheadingRatio { return ParagraphAttributes(kind: .style(.subheading)) }
        return ParagraphAttributes(kind: .style(.body))
    }

    private static func listFormat(textList: NSTextList?, marker: String, level: Int) -> ParagraphAttributes {
        // The last marker decides, because it's the one written in the text.
        let symbol = marker.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let symbolCharacter = symbol.first

        if let symbolCharacter, "☑☒✓✔◼".contains(symbolCharacter) {
            return ParagraphAttributes(kind: .list(.checklist), level: level, isChecked: true)
        }
        if let symbolCharacter, "☐◻".contains(symbolCharacter) {
            return ParagraphAttributes(kind: .list(.checklist), level: level)
        }

        let format = textList?.markerFormat.rawValue ?? ""
        if format.contains("decimal") || symbolCharacter?.isNumber == true {
            return ParagraphAttributes(kind: .list(.numbered), level: level)
        }
        if format.contains("hyphen") || symbolCharacter.map("–—-".contains) == true {
            return ParagraphAttributes(kind: .list(.dashed), level: level)
        }
        return ParagraphAttributes(kind: .list(.bulleted), level: level)
    }

    /// Reads bold and italic from the fonts. Headings are bold by nature, so that isn't kept for them.
    private static func markInlineStyles(in range: NSRange, of text: NSMutableAttributedString, includingBold: Bool) {
        text.enumerateAttribute(.font, in: range) { value, runRange, _ in
            guard let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits else { return }
            text.addAttribute(.notesBold, value: includingBold && traits.contains(.bold), range: runRange)
            text.addAttribute(.notesItalic, value: traits.contains(.italic), range: runRange)
        }
    }

    // MARK: - Helpers

    /// The size most of the text has, which is taken to be the body text.
    private static func mostCommonFontSize(in text: NSAttributedString) -> CGFloat {
        var lengths: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont {
                lengths[font.pointSize, default: 0] += range.length
            }
        }
        return lengths.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? 0
    }

    /// Notes don't hold images or files, so their placeholder characters are removed.
    private static func removeAttachments(from text: NSMutableAttributedString) {
        let string = text.string as NSString
        var location = string.length - 1
        while location >= 0 {
            if string.character(at: location) == 0xFFFC {
                text.deleteCharacters(in: NSRange(location: location, length: 1))
            }
            location -= 1
        }
    }

    private static func trimmingEmptyParagraphs(_ blocks: [Block]) -> [Block] {
        var blocks = blocks[...]
        while blocks.first == .emptyParagraph { blocks = blocks.dropFirst() }
        while blocks.last == .emptyParagraph { blocks = blocks.dropLast() }
        return Array(blocks)
    }
}
