import Foundation

/// The paragraph styles from Apple Notes.
enum ParagraphStyle: String, CaseIterable, Hashable, Sendable {
    case title
    case heading
    case subheading
    case body
    case monostyled
}

/// The list types from Apple Notes.
enum ListKind: String, CaseIterable, Hashable, Sendable {
    case bulleted
    case dashed
    case numbered
    case checklist
}

struct ListItem: Hashable, Sendable {
    static let maximumLevel = 8

    var kind: ListKind
    var level: Int
    /// Only meaningful for checklists; always `false` for other list kinds.
    var isChecked: Bool
    var text: RichText

    init(kind: ListKind, level: Int = 0, isChecked: Bool = false, text: RichText) {
        self.kind = kind
        self.level = min(max(level, 0), Self.maximumLevel)
        self.isChecked = kind == .checklist && isChecked
        self.text = text
    }
}

/// A rectangular table. Every row has the same number of cells.
struct NoteTable: Hashable, Sendable {
    private(set) var rows: [[RichText]]

    init(rows: [[RichText]]) {
        let columnCount = max(rows.map(\.count).max() ?? 0, 1)
        let paddedRows = rows.map { $0 + Array(repeating: RichText(), count: columnCount - $0.count) }
        self.rows = paddedRows.isEmpty ? [[RichText()]] : paddedRows
    }

    init(rowCount: Int, columnCount: Int) {
        let row = Array(repeating: RichText(), count: max(columnCount, 1))
        self.init(rows: Array(repeating: row, count: max(rowCount, 1)))
    }

    var rowCount: Int { rows.count }
    var columnCount: Int { rows[0].count }

    subscript(row: Int, column: Int) -> RichText {
        get { rows[row][column] }
        set { rows[row][column] = newValue }
    }

    mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: RichText(), count: columnCount), at: index)
    }

    mutating func insertColumn(at index: Int) {
        for row in rows.indices {
            rows[row].insert(RichText(), at: index)
        }
    }

    mutating func removeRow(at index: Int) {
        guard rowCount > 1 else { return }
        rows.remove(at: index)
    }

    mutating func removeColumn(at index: Int) {
        guard columnCount > 1 else { return }
        for row in rows.indices {
            rows[row].remove(at: index)
        }
    }
}

enum Block: Hashable, Sendable {
    case paragraph(ParagraphStyle, RichText)
    case listItem(ListItem)
    case table(NoteTable)

    static let emptyParagraph = Block.paragraph(.body, RichText())

    var plainText: String {
        switch self {
        case .paragraph(_, let text):
            text.plainText
        case .listItem(let item):
            item.text.plainText
        case .table(let table):
            table.rows.flatMap { $0 }.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

/// The content of a note, independent of how it is shown or stored.
///
/// A document always has at least one block, just like a text view always has at least one paragraph.
struct NoteDocument: Hashable, Sendable {
    private(set) var blocks: [Block]

    init(blocks: [Block] = []) {
        self.blocks = blocks.isEmpty ? [.emptyParagraph] : blocks
    }

    /// A new, empty note that starts with the Title style, like in Notes.
    static let newNote = NoteDocument(blocks: [.paragraph(.title, RichText())])

    var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    /// The first non-empty line, or an empty string.
    var title: String {
        nonEmptyLines.first ?? ""
    }

    /// The first non-empty line after the title, or an empty string.
    var previewText: String {
        nonEmptyLines.dropFirst().first ?? ""
    }

    var hasContent: Bool {
        !nonEmptyLines.isEmpty
    }

    private var nonEmptyLines: [String] {
        blocks.lazy
            .map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { $0 }
    }
}
