import AppKit

/// Converts between a `NoteDocument` and the attributed string shown in the editor.
///
/// Each paragraph, list item and table cell becomes one paragraph of text. The paragraph's kind,
/// list level and checked state are stored as custom attributes (see `NSAttributedString.Key`).
/// Tables use `NSTextTable`.
@MainActor
enum AttributedStringConverter {
    struct Paragraph {
        /// The paragraph text without the trailing newline.
        var content: NSRange
        /// The paragraph text including the trailing newline, if any.
        var full: NSRange
    }

    struct Analysis {
        var document: NoteDocument
        /// The character range of each block in `document.blocks`.
        var blockRanges: [NSRange]
    }

    // MARK: - Document to text

    static func attributedString(from document: NoteDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in document.blocks.enumerated() {
            let isLast = index == document.blocks.count - 1
            switch block {
            case .paragraph(let style, let text):
                append(text, paragraph: ParagraphAttributes(kind: .style(style)), terminated: !isLast, to: result)
            case .listItem(let item):
                let paragraph = ParagraphAttributes(kind: .list(item.kind), level: item.level, isChecked: item.isChecked)
                append(item.text, paragraph: paragraph, terminated: !isLast, to: result)
            case .table(let table):
                let textTable = makeTextTable(columnCount: table.columnCount)
                for row in 0..<table.rowCount {
                    for column in 0..<table.columnCount {
                        let cell = makeCell(in: textTable, row: row, column: column)
                        // Cells are always terminated: an empty last cell needs a character to hold
                        // its table attributes. `analyze` drops the empty paragraph this leaves at the end.
                        append(table[row, column], paragraph: ParagraphAttributes(), textBlocks: [cell],
                               terminated: true, to: result)
                    }
                }
            }
        }
        return result
    }

    private static func append(
        _ text: RichText,
        paragraph: ParagraphAttributes,
        textBlocks: [NSTextBlock] = [],
        terminated: Bool,
        to result: NSMutableAttributedString
    ) {
        for run in text.runs {
            let attributes = NotesTextStyle.attributes(paragraph: paragraph, inline: run.style, textBlocks: textBlocks)
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        if terminated {
            let attributes = NotesTextStyle.attributes(paragraph: paragraph, inline: [], textBlocks: textBlocks)
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }
    }

    static func makeTextTable(columnCount: Int) -> NSTextTable {
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        return table
    }

    static func makeCell(in table: NSTextTable, row: Int, column: Int) -> NSTextTableBlock {
        let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        cell.setWidth(1, type: .absoluteValueType, for: .border)
        cell.setBorderColor(.separatorColor)
        cell.setWidth(6, type: .absoluteValueType, for: .padding)
        return cell
    }

    // MARK: - Text to document

    static func document(from text: NSAttributedString) -> NoteDocument {
        analyze(text).document
    }

    static func analyze(_ text: NSAttributedString) -> Analysis {
        let paragraphs = paragraphs(in: text.string as NSString)
        guard !paragraphs.isEmpty else {
            return Analysis(document: NoteDocument(), blockRanges: [NSRange(location: 0, length: 0)])
        }

        var blocks: [Block] = []
        var ranges: [NSRange] = []
        var index = 0
        while index < paragraphs.count {
            let paragraph = paragraphs[index]
            let attributes = startAttributes(of: paragraph, in: text)

            if let cell = tableCell(in: attributes) {
                let table = cell.table
                var cells: [Int: [Int: RichText]] = [:]
                var range = paragraph.full
                while index < paragraphs.count,
                      let cell = tableCell(in: startAttributes(of: paragraphs[index], in: text)),
                      cell.table === table {
                    let content = richText(in: paragraphs[index].content, of: text)
                    let existing = cells[cell.startingRow]?[cell.startingColumn]
                    // A cell can hold several paragraphs; a note table cell holds one line.
                    let joined = existing.map { $0.isEmpty || content.isEmpty ? $0 + content : $0 + " " + content } ?? content
                    cells[cell.startingRow, default: [:]][cell.startingColumn] = joined
                    range = NSUnionRange(range, paragraphs[index].full)
                    index += 1
                }
                let rowCount = (cells.keys.max() ?? 0) + 1
                let rows = (0..<rowCount).map { row in
                    (0..<table.numberOfColumns).map { column in cells[row]?[column] ?? RichText() }
                }
                blocks.append(.table(NoteTable(rows: rows)))
                ranges.append(range)
                continue
            }

            let isTrailingEmptyParagraph = paragraph.full.length == 0 && index == paragraphs.count - 1
            if isTrailingEmptyParagraph, case .table = blocks.last {
                break
            }

            let paragraphAttributes = ParagraphAttributes(attributes)
            switch paragraphAttributes.kind {
            case .style(.monostyled):
                let plain = (text.string as NSString).substring(with: paragraph.content)
                blocks.append(.paragraph(.monostyled, RichText(plain: plain)))
            case .style(let style):
                blocks.append(.paragraph(style, richText(in: paragraph.content, of: text)))
            case .list(let kind):
                blocks.append(.listItem(ListItem(
                    kind: kind,
                    level: paragraphAttributes.level,
                    isChecked: paragraphAttributes.isChecked,
                    text: richText(in: paragraph.content, of: text)
                )))
            }
            ranges.append(paragraph.full)
            index += 1
        }
        return Analysis(document: NoteDocument(blocks: blocks), blockRanges: ranges)
    }

    /// Splits text into paragraphs. Text that ends with a newline has an empty last paragraph.
    static func paragraphs(in string: NSString) -> [Paragraph] {
        guard string.length > 0 else { return [] }
        var result: [Paragraph] = []
        var start = 0
        while true {
            let newline = string.range(of: "\n", range: NSRange(location: start, length: string.length - start))
            if newline.location == NSNotFound {
                let range = NSRange(location: start, length: string.length - start)
                result.append(Paragraph(content: range, full: range))
                break
            }
            result.append(Paragraph(
                content: NSRange(location: start, length: newline.location - start),
                full: NSRange(location: start, length: newline.location - start + 1)
            ))
            start = newline.location + 1
            if start == string.length {
                let empty = NSRange(location: start, length: 0)
                result.append(Paragraph(content: empty, full: empty))
                break
            }
        }
        return result
    }

    static func tableCell(in attributes: [NSAttributedString.Key: Any]) -> NSTextTableBlock? {
        (attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock
    }

    private static func startAttributes(of paragraph: Paragraph, in text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        paragraph.full.length > 0 ? text.attributes(at: paragraph.full.location, effectiveRange: nil) : [:]
    }

    private static func richText(in range: NSRange, of text: NSAttributedString) -> RichText {
        var runs: [TextRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            runs.append(TextRun(string.substring(with: runRange), style: NotesTextStyle.inlineStyle(from: attributes)))
        }
        return RichText(runs)
    }
}
