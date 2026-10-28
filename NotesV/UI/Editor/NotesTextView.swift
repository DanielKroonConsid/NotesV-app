import AppKit

/// The note editor: an `NSTextView` that behaves like the editor in Apple Notes.
///
/// It uses TextKit 1, because `NSTextTable` needs it. List markers, checkboxes and the monostyled
/// background are drawn by the view; they are not part of the text.
final class NotesTextView: NSTextView {
    /// The date shown centered above the note, like in Notes.
    var headerText = "" {
        didSet { if headerText != oldValue { needsDisplay = true } }
    }

    private static let headerHeight: CGFloat = 36

    static func makeScrollableTextView() -> (NSScrollView, NotesTextView) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NotesTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: headerHeight)

        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.typingAttributes = NotesTextStyle.attributes(paragraph: ParagraphAttributes(), inline: [])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    // MARK: - Loading

    func load(_ document: NoteDocument) {
        textStorage?.setAttributedString(AttributedStringConverter.attributedString(from: document))
        setSelectedRange(NSRange(location: 0, length: 0))
        undoManager?.removeAllActions()

        // An empty note has no characters to take the paragraph style from.
        if let first = document.blocks.first, first.plainText.isEmpty, document.blocks.count == 1,
           case .paragraph(let style, _) = first {
            typingAttributes = NotesTextStyle.attributes(paragraph: ParagraphAttributes(kind: .style(style)), inline: [])
        }
        needsDisplay = true
    }

    // MARK: - Paste

    /// Only plain text is pasted, so it takes on the style where it is inserted, like in Notes.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    // MARK: - Paragraph helpers

    private var paragraphs: [AttributedStringConverter.Paragraph] {
        let all = AttributedStringConverter.paragraphs(in: string as NSString)
        return all.isEmpty ? [.init(content: NSRange(), full: NSRange())] : all
    }

    /// The paragraphs that touch `range`. A caret touches the paragraph it is in.
    private func paragraphs(intersecting range: NSRange) -> [AttributedStringConverter.Paragraph] {
        paragraphs.filter { paragraph in
            if range.length == 0 || paragraph.full.length == 0 {
                let end = max(range.location, NSMaxRange(range))
                return paragraph.full.location <= end && range.location <= NSMaxRange(paragraph.content)
            }
            return NSIntersectionRange(paragraph.full, range).length > 0
        }
    }

    private func attributes(of paragraph: AttributedStringConverter.Paragraph) -> [NSAttributedString.Key: Any] {
        guard let textStorage, paragraph.full.length > 0 else { return typingAttributes }
        return textStorage.attributes(at: paragraph.full.location, effectiveRange: nil)
    }

    private func paragraphAttributes(of paragraph: AttributedStringConverter.Paragraph) -> ParagraphAttributes {
        ParagraphAttributes(attributes(of: paragraph))
    }

    private func textBlocks(in attributes: [NSAttributedString.Key: Any]) -> [NSTextBlock] {
        (attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks ?? []
    }

    private var caretParagraph: AttributedStringConverter.Paragraph? {
        paragraphs(intersecting: NSRange(location: selectedRange().location, length: 0)).first
    }

    /// Applies `transform` to every selected paragraph outside tables, as one undoable change.
    private func updateParagraphs(
        in range: NSRange,
        _ transform: (ParagraphAttributes) -> ParagraphAttributes
    ) {
        guard let textStorage else { return }
        let selected = paragraphs(intersecting: range).filter { textBlocks(in: attributes(of: $0)).isEmpty }
        let changed = selected.filter { $0.full.length > 0 }
        if let first = changed.first, let last = changed.last {
            let union = NSUnionRange(first.full, last.full)
            guard shouldChangeText(in: union, replacementString: nil) else { return }
            textStorage.beginEditing()
            for paragraph in changed {
                let newAttributes = transform(paragraphAttributes(of: paragraph))
                restyle(paragraph.full, with: newAttributes)
            }
            textStorage.endEditing()
            didChangeText()
        }

        // Keep typing in the new style, also in an empty last paragraph.
        if let caret = caretParagraph, textBlocks(in: attributes(of: caret)).isEmpty {
            let inline = NotesTextStyle.inlineStyle(from: typingAttributes)
            let paragraph = caret.full.length > 0
                ? paragraphAttributes(of: caret)
                : transform(ParagraphAttributes(typingAttributes))
            typingAttributes = NotesTextStyle.attributes(paragraph: paragraph, inline: inline)
        }
        needsDisplay = true
    }

    /// Re-applies all attributes in `range` for a new paragraph style, keeping inline styles.
    private func restyle(_ range: NSRange, with paragraph: ParagraphAttributes) {
        guard let textStorage else { return }
        textStorage.enumerateAttributes(in: range) { attributes, runRange, _ in
            let inline = paragraph.kind == .style(.monostyled) ? [] : NotesTextStyle.inlineStyle(from: attributes)
            let newAttributes = NotesTextStyle.attributes(paragraph: paragraph, inline: inline, textBlocks: textBlocks(in: attributes))
            textStorage.setAttributes(newAttributes, range: runRange)
        }
    }

    private func setParagraphKind(_ kind: ParagraphKind) {
        updateParagraphs(in: selectedRange()) { current in
            ParagraphAttributes(kind: kind, level: current.level, isChecked: current.isChecked)
        }
    }

    private func toggleList(_ kind: ListKind) {
        let selected = paragraphs(intersecting: selectedRange())
        let allInList = selected.allSatisfy { paragraphAttributes(of: $0).kind == .list(kind) }
        setParagraphKind(allInList ? .style(.body) : .list(kind))
    }

    private func changeIndent(by delta: Int) {
        updateParagraphs(in: selectedRange()) { current in
            guard current.kind.listKind != nil else { return current }
            return ParagraphAttributes(kind: current.kind, level: current.level + delta, isChecked: current.isChecked)
        }
    }

    // MARK: - Format actions

    @objc func formatTitle(_ sender: Any?) { setParagraphKind(.style(.title)) }
    @objc func formatHeading(_ sender: Any?) { setParagraphKind(.style(.heading)) }
    @objc func formatSubheading(_ sender: Any?) { setParagraphKind(.style(.subheading)) }
    @objc func formatBody(_ sender: Any?) { setParagraphKind(.style(.body)) }
    @objc func formatMonostyled(_ sender: Any?) { setParagraphKind(.style(.monostyled)) }
    @objc func toggleBulletedList(_ sender: Any?) { toggleList(.bulleted) }
    @objc func toggleDashedList(_ sender: Any?) { toggleList(.dashed) }
    @objc func toggleNumberedList(_ sender: Any?) { toggleList(.numbered) }
    @objc func toggleChecklist(_ sender: Any?) { toggleList(.checklist) }
    @objc func increaseListIndent(_ sender: Any?) { changeIndent(by: 1) }
    @objc func decreaseListIndent(_ sender: Any?) { changeIndent(by: -1) }

    @objc func toggleChecked(_ sender: Any?) {
        let checklistItems = paragraphs(intersecting: selectedRange())
            .map(paragraphAttributes(of:))
            .filter { $0.kind == .list(.checklist) }
        let allChecked = !checklistItems.isEmpty && checklistItems.allSatisfy(\.isChecked)
        updateParagraphs(in: selectedRange()) { current in
            ParagraphAttributes(kind: current.kind, level: current.level, isChecked: !allChecked)
        }
    }

    @objc func toggleNotesBold(_ sender: Any?) { toggleInline(.bold) }
    @objc func toggleNotesItalic(_ sender: Any?) { toggleInline(.italic) }
    @objc func toggleNotesUnderline(_ sender: Any?) { toggleInline(.underline) }
    @objc func toggleNotesStrikethrough(_ sender: Any?) { toggleInline(.strikethrough) }

    override func underline(_ sender: Any?) { toggleInline(.underline) }

    private func toggleInline(_ style: InlineStyle) {
        guard let textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else {
            var inline = NotesTextStyle.inlineStyle(from: typingAttributes)
            inline.formSymmetricDifference(style)
            typingAttributes = NotesTextStyle.attributes(
                paragraph: ParagraphAttributes(typingAttributes), inline: inline, textBlocks: textBlocks(in: typingAttributes)
            )
            return
        }

        let string = self.string as NSString
        var allHaveStyle = true
        textStorage.enumerateAttributes(in: range) { attributes, runRange, stop in
            let hasText = !string.substring(with: runRange).allSatisfy(\.isNewline)
            if hasText, !NotesTextStyle.inlineStyle(from: attributes).contains(style) {
                allHaveStyle = false
                stop.pointee = true
            }
        }

        guard shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: range) { attributes, runRange, _ in
            var inline = NotesTextStyle.inlineStyle(from: attributes)
            if allHaveStyle { inline.remove(style) } else { inline.insert(style) }
            let newAttributes = NotesTextStyle.attributes(
                paragraph: ParagraphAttributes(attributes), inline: inline, textBlocks: textBlocks(in: attributes)
            )
            textStorage.setAttributes(newAttributes, range: runRange)
        }
        textStorage.endEditing()
        didChangeText()
    }

    // MARK: - Typing behavior

    override func insertNewline(_ sender: Any?) {
        if let cell = tableCell(at: selectedRange().location) {
            moveFromCell(cell, to: .below)
            return
        }
        guard let paragraph = caretParagraph else {
            super.insertNewline(sender)
            return
        }
        let current = paragraphAttributes(of: paragraph)

        // Return on an empty list item ends the list, or moves a nested item out one level.
        if current.kind.listKind != nil, selectedRange().length == 0, paragraph.content.length == 0 {
            updateParagraphs(in: selectedRange()) { current in
                current.level > 0
                    ? ParagraphAttributes(kind: current.kind, level: current.level - 1)
                    : ParagraphAttributes(kind: .style(.body))
            }
            return
        }

        super.insertNewline(sender)

        let newRange = NSRange(location: selectedRange().location, length: 0)
        switch current.kind {
        case .style(.title), .style(.heading), .style(.subheading):
            // After a heading, Notes continues with body text.
            if caretParagraph?.content.length == 0 {
                updateParagraphs(in: newRange) { _ in ParagraphAttributes(kind: .style(.body)) }
            }
        case .list(.checklist):
            updateParagraphs(in: newRange) { current in
                ParagraphAttributes(kind: current.kind, level: current.level, isChecked: false)
            }
        default:
            break
        }
    }

    override func insertTab(_ sender: Any?) {
        if let cell = tableCell(at: selectedRange().location) {
            moveFromCell(cell, to: .next)
        } else if paragraphs(intersecting: selectedRange()).contains(where: { paragraphAttributes(of: $0).kind.listKind != nil }) {
            changeIndent(by: 1)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let cell = tableCell(at: selectedRange().location) {
            moveFromCell(cell, to: .previous)
        } else if paragraphs(intersecting: selectedRange()).contains(where: { paragraphAttributes(of: $0).kind.listKind != nil }) {
            changeIndent(by: -1)
        } else {
            super.insertBacktab(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, let paragraph = caretParagraph, paragraph.full.location == selection.location {
            if tableCell(at: selection.location) != nil {
                // Deleting at the start of a cell would merge two cells.
                return
            }
            let current = paragraphAttributes(of: paragraph)
            if current.kind.listKind != nil {
                // Backspace at the start of a list item removes the list formatting first.
                updateParagraphs(in: selection) { current in
                    current.level > 0
                        ? ParagraphAttributes(kind: current.kind, level: current.level - 1, isChecked: current.isChecked)
                        : ParagraphAttributes(kind: .style(.body))
                }
                return
            }
        }
        super.deleteBackward(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        // List numbers further down may have changed.
        needsDisplay = true
    }

    // MARK: - Checklist clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let paragraph = checklistParagraph(at: point) {
            updateParagraphs(in: NSRange(location: paragraph.full.location, length: 0)) { current in
                ParagraphAttributes(kind: current.kind, level: current.level, isChecked: !current.isChecked)
            }
            return
        }
        super.mouseDown(with: event)
    }

    private func checklistParagraph(at point: NSPoint) -> AttributedStringConverter.Paragraph? {
        guard let layoutManager, let textContainer, !string.isEmpty else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard let paragraph = paragraphs(intersecting: NSRange(location: characterIndex, length: 0)).first,
              paragraph.full.length > 0 else { return nil }
        let attributes = paragraphAttributes(of: paragraph)
        guard attributes.kind == .list(.checklist),
              let rect = markerRect(for: paragraph, attributes: attributes) else { return nil }
        return rect.insetBy(dx: -2, dy: -2).contains(point) ? paragraph : nil
    }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawHeader()
        let all = paragraphs
        drawMonostyledBackgrounds(paragraphs: all, in: rect)
        drawListMarkers(paragraphs: all, in: rect)
    }

    private func drawHeader() {
        guard !headerText.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = NSAttributedString(string: headerText, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 12))
    }

    /// The rectangle left of a list item's text where its marker is drawn, in view coordinates.
    private func markerRect(for paragraph: AttributedStringConverter.Paragraph, attributes: ParagraphAttributes) -> NSRect? {
        guard let layoutManager, let textContainer, let kind = attributes.kind.listKind else { return nil }
        let font = NotesTextStyle.baseFont(for: attributes.kind)
        let origin = textContainerOrigin
        let baseline: CGFloat

        if paragraph.full.length > 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: paragraph.full.location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            baseline = origin.y + fragment.minY + layoutManager.location(forGlyphAt: glyphIndex).y
        } else {
            let fragment = layoutManager.extraLineFragmentRect
            guard fragment.height > 0 else { return nil }
            baseline = origin.y + fragment.minY + font.ascender
        }

        let markerWidth = kind == .checklist ? NotesTextStyle.checklistMarkerWidth : NotesTextStyle.listMarkerWidth
        let x = origin.x + textContainer.lineFragmentPadding + CGFloat(attributes.level) * NotesTextStyle.listIndentPerLevel
        return NSRect(x: x, y: baseline - font.ascender, width: markerWidth, height: font.ascender - font.descender)
    }

    private func drawListMarkers(paragraphs: [AttributedStringConverter.Paragraph], in dirtyRect: NSRect) {
        for (index, paragraph) in paragraphs.enumerated() {
            let attributes = paragraphAttributes(of: paragraph)
            guard let kind = attributes.kind.listKind,
                  let rect = markerRect(for: paragraph, attributes: attributes),
                  rect.intersects(dirtyRect) else { continue }

            switch kind {
            case .bulleted:
                drawMarkerText("•", in: rect)
            case .dashed:
                drawMarkerText("–", in: rect)
            case .numbered:
                drawMarkerText("\(listNumber(at: index, in: paragraphs)).", in: rect)
            case .checklist:
                drawCheckbox(isChecked: attributes.isChecked, in: rect)
            }
        }
    }

    private func drawMarkerText(_ marker: String, in rect: NSRect) {
        let text = NSAttributedString(string: marker, attributes: [
            .font: NotesTextStyle.baseFont(for: .list(.bulleted)),
            .foregroundColor: NSColor.textColor,
        ])
        let width = text.size().width
        text.draw(at: NSPoint(x: rect.maxX - 6 - width, y: rect.minY))
    }

    private func drawCheckbox(isChecked: Bool, in rect: NSRect) {
        let diameter: CGFloat = 16
        let circle = NSRect(x: rect.minX, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        if isChecked {
            NotesTextStyle.accentColor.setFill()
            NSBezierPath(ovalIn: circle).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: circle.minX + diameter * 0.28, y: circle.minY + diameter * 0.52))
            check.line(to: NSPoint(x: circle.minX + diameter * 0.44, y: circle.minY + diameter * 0.68))
            check.line(to: NSPoint(x: circle.minX + diameter * 0.73, y: circle.minY + diameter * 0.34))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            let path = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// The number of a numbered list item: its position among the preceding numbered items at the
    /// same level, skipping deeper levels.
    private func listNumber(at index: Int, in paragraphs: [AttributedStringConverter.Paragraph]) -> Int {
        let level = paragraphAttributes(of: paragraphs[index]).level
        var number = 1
        var previous = index - 1
        while previous >= 0 {
            let attributes = paragraphAttributes(of: paragraphs[previous])
            guard attributes.kind.listKind != nil else { break }
            if attributes.level > level {
                previous -= 1
                continue
            }
            guard attributes.level == level, attributes.kind == .list(.numbered) else { break }
            number += 1
            previous -= 1
        }
        return number
    }

    private func drawMonostyledBackgrounds(paragraphs: [AttributedStringConverter.Paragraph], in dirtyRect: NSRect) {
        guard let layoutManager, let textContainer else { return }
        var groups: [[AttributedStringConverter.Paragraph]] = []
        var current: [AttributedStringConverter.Paragraph] = []
        for paragraph in paragraphs {
            if paragraph.full.length > 0, paragraphAttributes(of: paragraph).kind == .style(.monostyled) {
                current.append(paragraph)
            } else if !current.isEmpty {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }

        let origin = textContainerOrigin
        let padding = textContainer.lineFragmentPadding
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let firstGlyph = layoutManager.glyphIndexForCharacter(at: first.full.location)
            let lastGlyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(last.full) - 1)
            let top = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil).minY
            let bottom = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil).maxY
            let rect = NSRect(
                x: origin.x + padding,
                y: origin.y + top,
                width: textContainer.size.width - 2 * padding,
                height: bottom - top
            )
            guard rect.intersects(dirtyRect) else { continue }
            NSColor.quaternaryLabelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }

    // MARK: - Tables

    private struct CellLocation {
        var table: NSTextTable
        var row: Int
        var column: Int
    }

    private enum CellDirection {
        case next, previous, below
    }

    private func tableCell(at location: Int) -> CellLocation? {
        guard let textStorage else { return nil }
        let attributes = location < textStorage.length
            ? textStorage.attributes(at: location, effectiveRange: nil)
            : typingAttributes
        guard let cell = AttributedStringConverter.tableCell(in: attributes) else { return nil }
        return CellLocation(table: cell.table, row: cell.startingRow, column: cell.startingColumn)
    }

    /// The text range of a cell, found by scanning the paragraphs.
    private func contentRange(of table: NSTextTable, row: Int, column: Int) -> NSRange? {
        guard let textStorage else { return nil }
        for paragraph in paragraphs where paragraph.full.length > 0 {
            let attributes = textStorage.attributes(at: paragraph.full.location, effectiveRange: nil)
            if let cell = AttributedStringConverter.tableCell(in: attributes), cell.table === table,
               cell.startingRow == row, cell.startingColumn == column {
                return paragraph.content
            }
        }
        return nil
    }

    private func moveFromCell(_ cell: CellLocation, to direction: CellDirection) {
        let columns = cell.table.numberOfColumns
        var target: (row: Int, column: Int)
        switch direction {
        case .next: target = cell.column + 1 < columns ? (cell.row, cell.column + 1) : (cell.row + 1, 0)
        case .previous: target = cell.column > 0 ? (cell.row, cell.column - 1) : (cell.row - 1, columns - 1)
        case .below: target = (cell.row + 1, cell.column)
        }
        guard target.row >= 0 else { return }

        if let range = contentRange(of: cell.table, row: target.row, column: target.column) {
            setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        } else if direction == .next {
            // Tab in the last cell adds a row, like in Notes.
            addTableRow(nil)
            moveToCell(row: cell.row + 1, column: 0)
        } else if direction == .below {
            // Return in the last row moves to the text after the table.
            let analysis = AttributedStringConverter.analyze(textStorage ?? NSAttributedString())
            if let tableRange = analysis.blockRanges.first(where: { NSLocationInRange(selectedRange().location, $0) }) {
                setSelectedRange(NSRange(location: NSMaxRange(tableRange), length: 0))
            }
        }
        scrollRangeToVisible(selectedRange())
    }

    private func moveToCell(row: Int, column: Int) {
        guard let cell = tableCell(at: selectedRange().location),
              let range = contentRange(of: cell.table, row: row, column: column) else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    /// Edits the document as a whole, then puts the caret in the given block and cell.
    /// `edit` gets the blocks, the index of the block with the caret, and the caret's cell.
    private func editDocument(
        _ edit: (inout [Block], Int, (row: Int, column: Int)?) -> (block: Int, cell: (row: Int, column: Int)?)?
    ) {
        guard let textStorage else { return }
        let analysis = AttributedStringConverter.analyze(textStorage)
        let caret = selectedRange().location
        let blockIndex = analysis.blockRanges.firstIndex { NSLocationInRange(caret, $0) }
            ?? analysis.blockRanges.count - 1
        let cell = tableCell(at: caret).map { (row: $0.row, column: $0.column) }

        var blocks = analysis.document.blocks
        guard let target = edit(&blocks, blockIndex, cell) else { return }

        let newText = AttributedStringConverter.attributedString(from: NoteDocument(blocks: blocks))
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard shouldChangeText(in: fullRange, replacementString: newText.string) else { return }
        textStorage.replaceCharacters(in: fullRange, with: newText)
        didChangeText()

        let newRanges = AttributedStringConverter.analyze(textStorage).blockRanges
        let blockRange = newRanges[min(target.block, newRanges.count - 1)]
        var location = blockRange.location
        if let cell = target.cell, let newCell = tableCell(at: blockRange.location),
           let range = contentRange(of: newCell.table, row: cell.row, column: cell.column) {
            location = range.location
        }
        setSelectedRange(NSRange(location: location, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    @objc func insertNotesTable(_ sender: Any?) {
        editDocument { blocks, index, _ in
            let table = Block.table(NoteTable(rowCount: 2, columnCount: 2))
            let tableIndex: Int
            if case .paragraph(_, let text) = blocks[index], text.isEmpty {
                blocks[index] = table
                tableIndex = index
            } else {
                tableIndex = index + 1
                blocks.insert(table, at: tableIndex)
            }
            // Keep a paragraph after the table so the user can keep writing.
            if tableIndex + 1 >= blocks.count || { if case .table = blocks[tableIndex + 1] { true } else { false } }() {
                blocks.insert(.emptyParagraph, at: tableIndex + 1)
            }
            return (tableIndex, (0, 0))
        }
    }

    private func editTable(_ edit: (inout NoteTable, Int, Int) -> (row: Int, column: Int)?) {
        editDocument { blocks, index, cell in
            guard let cell, case .table(var table) = blocks[index] else { return nil }
            guard let target = edit(&table, cell.row, cell.column) else {
                blocks.remove(at: index)
                return (index, nil)
            }
            blocks[index] = .table(table)
            return (index, target)
        }
    }

    @objc func addTableRow(_ sender: Any?) {
        editTable { table, row, column in
            table.insertRow(at: row + 1)
            return (row + 1, column)
        }
    }

    @objc func addTableColumn(_ sender: Any?) {
        editTable { table, row, column in
            table.insertColumn(at: column + 1)
            return (row, column + 1)
        }
    }

    @objc func deleteTableRow(_ sender: Any?) {
        editTable { table, row, column in
            guard table.rowCount > 1 else { return nil }
            table.removeRow(at: row)
            return (min(row, table.rowCount - 1), column)
        }
    }

    @objc func deleteTableColumn(_ sender: Any?) {
        editTable { table, row, column in
            guard table.columnCount > 1 else { return nil }
            table.removeColumn(at: column)
            return (row, min(column, table.columnCount - 1))
        }
    }
}
