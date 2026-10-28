import Foundation

/// Converts notes to and from GitHub Flavored Markdown with YAML front matter.
///
/// This is the only place that knows the Markdown format. See the table in `CLAUDE.md` for how each
/// Notes style is written. The rules for blank lines are:
/// - Blocks are separated by one blank line.
/// - Each empty paragraph adds one more blank line, so empty lines in a note survive a round trip.
/// - Consecutive list items and consecutive monostyled lines form one group with no blank lines inside.
enum MarkdownCodec {
    struct DecodedNote: Hashable, Sendable {
        /// `nil` if the file had no front matter.
        var fields: FrontMatter.Fields?
        var document: NoteDocument
    }

    // MARK: - Files

    static func encode(_ note: Note) -> String {
        FrontMatter.encode(note) + "\n" + encodeBody(note.document)
    }

    static func decode(_ text: String) -> DecodedNote {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let (fields, body) = FrontMatter.split(normalized)
        var bodyText = body
        if fields != nil, bodyText.first == "\n" {
            bodyText = bodyText.dropFirst()
        }
        return DecodedNote(fields: fields, document: decodeBody(String(bodyText)))
    }

    // MARK: - Encoding blocks

    static func encodeBody(_ document: NoteDocument) -> String {
        var lines: [String] = []
        var pendingEmptyParagraphs = 0
        var hasGroup = false
        let blocks = document.blocks
        var index = 0

        func beginGroup() {
            let blankLines = hasGroup ? pendingEmptyParagraphs + 1 : pendingEmptyParagraphs
            lines += Array(repeating: "", count: blankLines)
            pendingEmptyParagraphs = 0
            hasGroup = true
        }

        while index < blocks.count {
            switch blocks[index] {
            case .paragraph(.monostyled, _):
                var code: [String] = []
                while index < blocks.count, case .paragraph(.monostyled, let text) = blocks[index] {
                    code.append(text.plainText)
                    index += 1
                }
                beginGroup()
                let fence = codeFence(for: code)
                lines.append(fence)
                lines += code
                lines.append(fence)

            case .paragraph(let style, let text):
                index += 1
                if text.plainText.allSatisfy(\.isWhitespace) {
                    pendingEmptyParagraphs += 1
                    continue
                }
                beginGroup()
                lines.append(encodeParagraph(style, text))

            case .listItem:
                beginGroup()
                var counters: [Int] = []
                while index < blocks.count, case .listItem(let item) = blocks[index] {
                    lines.append(encodeListItem(item, counters: &counters))
                    index += 1
                }

            case .table(let table):
                index += 1
                beginGroup()
                lines += encodeTable(table)
            }
        }

        if hasGroup {
            lines += Array(repeating: "", count: pendingEmptyParagraphs)
        } else {
            lines = Array(repeating: "", count: max(pendingEmptyParagraphs - 1, 0))
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func encodeParagraph(_ style: ParagraphStyle, _ text: RichText) -> String {
        switch style {
        case .title: "# " + encodeHeadingText(text)
        case .heading: "## " + encodeHeadingText(text)
        case .subheading: "### " + encodeHeadingText(text)
        case .body, .monostyled: escapeBlockStart(encodeInline(text))
        }
    }

    private static func encodeHeadingText(_ text: RichText) -> String {
        var encoded = encodeInline(text)
        // A trailing "#" would be read as a closing heading sequence.
        if encoded.hasSuffix("#") {
            encoded.removeLast()
            encoded += "\\#"
        }
        return encoded
    }

    private static func encodeListItem(_ item: ListItem, counters: inout [Int]) -> String {
        if counters.count > item.level + 1 {
            counters.removeSubrange((item.level + 1)...)
        }
        while counters.count < item.level + 1 {
            counters.append(0)
        }

        let marker: String
        switch item.kind {
        case .bulleted:
            marker = "*"
            counters[item.level] = 0
        case .dashed:
            marker = "-"
            counters[item.level] = 0
        case .checklist:
            marker = item.isChecked ? "- [x]" : "- [ ]"
            counters[item.level] = 0
        case .numbered:
            counters[item.level] += 1
            marker = "\(counters[item.level])."
        }

        var content = escapeBlockStart(encodeInline(item.text))
        if item.kind != .checklist, content.hasPrefix("[") {
            content = "\\" + content
        }
        let indent = String(repeating: " ", count: item.level * 4)
        return content.isEmpty ? indent + marker : "\(indent)\(marker) \(content)"
    }

    private static func encodeTable(_ table: NoteTable) -> [String] {
        func row(_ cells: [RichText]) -> String {
            "| " + cells.map { encodeInline($0, inTable: true) }.joined(separator: " | ") + " |"
        }
        let separator = "|" + String(repeating: " --- |", count: table.columnCount)
        return [row(table.rows[0]), separator] + table.rows.dropFirst().map(row)
    }

    private static func codeFence(for lines: [String]) -> String {
        let longestBacktickRun = lines.map { line in
            line.prefix { $0 == " " }.count <= 3 ? line.drop { $0 == " " }.prefix { $0 == "`" }.count : 0
        }.max() ?? 0
        return String(repeating: "`", count: max(3, longestBacktickRun + 1))
    }

    /// Escapes the first character of a line if it would otherwise start a Markdown block
    /// (heading, quote, table, list).
    private static func escapeBlockStart(_ line: String) -> String {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        guard let first = rest.first else { return line }

        if "#>|-+".contains(first) {
            return indent + "\\" + rest
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let afterDigits = rest.dropFirst(digits.count)
            if let punctuation = afterDigits.first, punctuation == "." || punctuation == ")" {
                let afterPunctuation = afterDigits.dropFirst()
                if afterPunctuation.isEmpty || afterPunctuation.first?.isWhitespace == true {
                    return indent + digits + "\\" + afterDigits
                }
            }
        }
        return line
    }

    // MARK: - Encoding inline text

    static func encodeInline(_ text: RichText, inTable: Bool = false) -> String {
        var output = ""
        var active: InlineStyle = []
        for run in text.runs {
            output += markers(from: active, to: run.style)
            output += escapeText(run.text, inTable: inTable)
            active = run.style
        }
        output += markers(from: active, to: [])
        return output
    }

    private static func markers(from old: InlineStyle, to new: InlineStyle) -> String {
        let closing = old.subtracting(new)
        let opening = new.subtracting(old)
        var result = ""
        if closing.contains(.italic) { result += "*" }
        if closing.contains(.bold) { result += "**" }
        if closing.contains(.strikethrough) { result += "~~" }
        if closing.contains(.underline) { result += "</u>" }
        if opening.contains(.underline) { result += "<u>" }
        if opening.contains(.strikethrough) { result += "~~" }
        if opening.contains(.bold) { result += "**" }
        if opening.contains(.italic) { result += "*" }
        return result
    }

    private static func escapeText(_ text: String, inTable: Bool) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            switch character {
            case "\\", "*", "`", "~", "<":
                result += "\\" + String(character)
            case "_":
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let isIntraword = previous.map(isWordCharacter) == true && next.map(isWordCharacter) == true
                result += isIntraword ? "_" : "\\_"
            case "|" where inTable:
                result += "\\|"
            default:
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Decoding blocks

    static func decodeBody(_ text: String) -> NoteDocument {
        let lines: [Substring] = text.isEmpty
            ? []
            : text.dropLast(text.hasSuffix("\n") ? 1 : 0).split(separator: "\n", omittingEmptySubsequences: false)

        var blocks: [Block] = []
        var blankLines = 0
        var hasGroup = false
        var index = 0

        func beginGroup() {
            let emptyParagraphs = hasGroup ? max(blankLines - 1, 0) : blankLines
            blocks += Array(repeating: .emptyParagraph, count: emptyParagraphs)
            blankLines = 0
            hasGroup = true
        }

        while index < lines.count {
            let line = lines[index]
            if line.allSatisfy(\.isWhitespace) {
                blankLines += 1
                index += 1
                continue
            }
            beginGroup()

            if let fence = openingFence(line) {
                index += 1
                var code: [String] = []
                while index < lines.count, !isClosingFence(lines[index], matching: fence) {
                    code.append(String(lines[index]))
                    index += 1
                }
                index += 1 // Skip the closing fence.
                blocks += (code.isEmpty ? [""] : code).map { .paragraph(.monostyled, RichText(plain: $0)) }
            } else if let heading = parseHeading(line) {
                blocks.append(heading)
                index += 1
            } else if isTableStart(lines, at: index) {
                var rows = [splitTableRow(lines[index])]
                index += 2 // Skip the header and separator rows.
                while index < lines.count, lines[index].drop(while: \.isWhitespace).hasPrefix("|") {
                    rows.append(splitTableRow(lines[index]))
                    index += 1
                }
                blocks.append(.table(NoteTable(rows: rows.map { $0.map(decodeInline) })))
            } else if parseListLine(line) != nil {
                var items: [ParsedListLine] = []
                while index < lines.count, let item = parseListLine(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks += makeListItems(items)
            } else {
                blocks.append(.paragraph(.body, decodeInline(String(line))))
                index += 1
            }
        }

        if hasGroup {
            blocks += Array(repeating: .emptyParagraph, count: blankLines)
        } else {
            blocks = Array(repeating: .emptyParagraph, count: blankLines + 1)
        }
        return NoteDocument(blocks: blocks)
    }

    private static func openingFence(_ line: Substring) -> String? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }
        let rest = line.dropFirst(indent.count)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let fence = rest.prefix { $0 == character }
        guard fence.count >= 3 else { return nil }
        if character == "`", rest.dropFirst(fence.count).contains("`") { return nil }
        return String(fence)
    }

    private static func isClosingFence(_ line: Substring, matching fence: String) -> Bool {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3, let character = fence.first else { return false }
        let rest = line.dropFirst(indent.count)
        let run = rest.prefix { $0 == character }
        return run.count >= fence.count && rest.dropFirst(run.count).allSatisfy(\.isWhitespace)
    }

    private static func parseHeading(_ line: Substring) -> Block? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }
        let rest = line.dropFirst(indent.count)
        let hashes = rest.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        var content = rest.dropFirst(hashes.count)
        guard content.isEmpty || content.first == " " || content.first == "\t" else { return nil }

        content = content.drop { $0 == " " || $0 == "\t" }
        while content.last == " " || content.last == "\t" { content = content.dropLast() }
        // Remove an optional closing sequence of "#" characters.
        let closing = content.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let beforeClosing = content.dropLast(closing)
            if beforeClosing.isEmpty || beforeClosing.last == " " || beforeClosing.last == "\t" {
                content = beforeClosing
                while content.last == " " || content.last == "\t" { content = content.dropLast() }
            }
        }

        let style: ParagraphStyle = switch hashes.count {
        case 1: .title
        case 2: .heading
        default: .subheading
        }
        return .paragraph(style, decodeInline(String(content)))
    }

    private struct ParsedListLine {
        var indent: Int
        var kind: ListKind
        var isChecked: Bool
        var content: Substring
    }

    private static func parseListLine(_ line: Substring) -> ParsedListLine? {
        var indent = 0
        var rest = line[...]
        while let first = rest.first, first == " " || first == "\t" {
            indent += first == "\t" ? 4 : 1
            rest = rest.dropFirst()
        }
        guard let first = rest.first else { return nil }

        var kind: ListKind
        var markerLength: Int
        if first == "*" || first == "+" || first == "-" {
            kind = first == "-" ? .dashed : .bulleted
            markerLength = 1
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count) else { return nil }
            let punctuation = rest.dropFirst(digits.count).first
            guard punctuation == "." || punctuation == ")" else { return nil }
            kind = .numbered
            markerLength = digits.count + 1
        }

        var content = rest.dropFirst(markerLength)
        guard content.isEmpty || content.first == " " || content.first == "\t" else { return nil }
        content = content.drop { $0 == " " || $0 == "\t" }

        var isChecked = false
        if let box = checkbox(at: content) {
            kind = .checklist
            isChecked = box
            content = content.dropFirst(3).drop { $0 == " " || $0 == "\t" }
        }
        return ParsedListLine(indent: indent, kind: kind, isChecked: isChecked, content: content)
    }

    /// Whether the text starts with a task-list checkbox, and if it is checked.
    private static func checkbox(at content: Substring) -> Bool? {
        let box = content.prefix(3)
        guard box.count == 3, box.first == "[", box.last == "]" else { return nil }
        let after = content.dropFirst(3).first
        guard after == nil || after == " " || after == "\t" else { return nil }
        switch box.dropFirst().first {
        case " ": return false
        case "x", "X": return true
        default: return nil
        }
    }

    private static func makeListItems(_ lines: [ParsedListLine]) -> [Block] {
        let levels: [Int]
        if lines.allSatisfy({ $0.indent % 4 == 0 }) {
            levels = lines.map { $0.indent / 4 }
        } else {
            // Other editors often indent nested lists by 2 or 3 spaces.
            var stack: [Int] = []
            levels = lines.map { line in
                while let last = stack.last, last > line.indent { stack.removeLast() }
                if stack.last != line.indent { stack.append(line.indent) }
                return stack.count - 1
            }
        }
        return zip(lines, levels).map { line, level in
            .listItem(ListItem(kind: line.kind, level: level, isChecked: line.isChecked, text: decodeInline(String(line.content))))
        }
    }

    private static func isTableStart(_ lines: [Substring], at index: Int) -> Bool {
        guard lines[index].drop(while: \.isWhitespace).hasPrefix("|"), index + 1 < lines.count else { return false }
        let separator = splitTableRow(lines[index + 1])
        return !separator.isEmpty && separator.allSatisfy { cell in
            cell.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
        }
    }

    /// Splits a table row into raw cell strings. Escaped pipes (`\|`) stay escaped so that inline
    /// decoding turns them back into `|`.
    private static func splitTableRow(_ line: Substring) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = []
        var current = ""
        var endedWithPipe = false
        var iterator = trimmed.makeIterator()
        while let character = iterator.next() {
            endedWithPipe = false
            if character == "\\", let next = iterator.next() {
                current += "\\" + String(next)
            } else if character == "|" {
                cells.append(current)
                current = ""
                endedWithPipe = true
            } else {
                current.append(character)
            }
        }
        if !endedWithPipe {
            cells.append(current)
        }
        if trimmed.hasPrefix("|"), !cells.isEmpty {
            cells.removeFirst()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Decoding inline text

    private enum DelimiterKind: Equatable {
        case bold, italic, strikethrough, underlineOpen, underlineClose
    }

    private struct Token {
        var kind: DelimiterKind?
        var text: String
        var canOpen = true
        var canClose = true
    }

    static func decodeInline(_ source: String) -> RichText {
        let characters = Array(source)
        var tokens: [Token] = []

        func appendText(_ text: String) {
            if let last = tokens.last, last.kind == nil {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(Token(kind: nil, text: text))
            }
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                if index + 1 < characters.count, isASCIIPunctuation(characters[index + 1]) {
                    appendText(String(characters[index + 1]))
                    index += 2
                } else {
                    appendText("\\")
                    index += 1
                }

            case "*", "_":
                let count = characters[index...].prefix { $0 == character }.count
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + count < characters.count ? characters[index + count] : nil
                if character == "_", previous.map(isWordCharacter) == true, next.map(isWordCharacter) == true {
                    appendText(String(repeating: character, count: count))
                } else {
                    let canOpen = next.map { !$0.isWhitespace } ?? false
                    let canClose = previous.map { !$0.isWhitespace } ?? false
                    for _ in 0..<(count / 2) {
                        tokens.append(Token(kind: .bold, text: String([character, character]), canOpen: canOpen, canClose: canClose))
                    }
                    if count % 2 == 1 {
                        tokens.append(Token(kind: .italic, text: String(character), canOpen: canOpen, canClose: canClose))
                    }
                }
                index += count

            case "~":
                let count = characters[index...].prefix { $0 == "~" }.count
                for _ in 0..<(count / 2) {
                    tokens.append(Token(kind: .strikethrough, text: "~~"))
                }
                if count % 2 == 1 {
                    appendText("~")
                }
                index += count

            case "<":
                let ahead = String(characters[index..<min(index + 4, characters.count)]).lowercased()
                if ahead.hasPrefix("<u>") {
                    tokens.append(Token(kind: .underlineOpen, text: String(characters[index..<index + 3])))
                    index += 3
                } else if ahead == "</u>" {
                    tokens.append(Token(kind: .underlineClose, text: String(characters[index..<index + 4])))
                    index += 4
                } else {
                    appendText("<")
                    index += 1
                }

            default:
                appendText(String(character))
                index += 1
            }
        }

        // Pair openers with closers. Delimiters without a partner are kept as literal text.
        var isPaired = Array(repeating: false, count: tokens.count)
        for kind in [DelimiterKind.bold, .italic, .strikethrough] {
            var opener: Int?
            for (tokenIndex, token) in tokens.enumerated() where token.kind == kind {
                if let openerIndex = opener, token.canClose {
                    isPaired[openerIndex] = true
                    isPaired[tokenIndex] = true
                    opener = nil
                } else if token.canOpen {
                    opener = tokenIndex
                }
            }
        }
        var underlineOpener: Int?
        for (tokenIndex, token) in tokens.enumerated() {
            if token.kind == .underlineOpen, underlineOpener == nil {
                underlineOpener = tokenIndex
            } else if token.kind == .underlineClose, let openerIndex = underlineOpener {
                isPaired[openerIndex] = true
                isPaired[tokenIndex] = true
                underlineOpener = nil
            }
        }

        var style: InlineStyle = []
        var runs: [TextRun] = []
        for (tokenIndex, token) in tokens.enumerated() {
            guard let kind = token.kind, isPaired[tokenIndex] else {
                runs.append(TextRun(token.text, style: style))
                continue
            }
            switch kind {
            case .bold: style.formSymmetricDifference(.bold)
            case .italic: style.formSymmetricDifference(.italic)
            case .strikethrough: style.formSymmetricDifference(.strikethrough)
            case .underlineOpen: style.insert(.underline)
            case .underlineClose: style.remove(.underline)
            }
        }
        return RichText(runs)
    }

    // MARK: - Character classes

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func isASCIIPunctuation(_ character: Character) -> Bool {
        character.isASCII && (character.isPunctuation || character.isSymbol)
    }
}
