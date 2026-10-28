import AppKit
import Testing
@testable import NotesV

@MainActor
struct AttributedStringConverterTests {
    nonisolated static let documents: [NoteDocument] = [
        NoteDocument(),
        NoteDocument(blocks: [.emptyParagraph, .emptyParagraph]),
        NoteDocument(blocks: [
            .paragraph(.title, "Weekly sync"),
            .paragraph(.heading, "Agenda"),
            .paragraph(.subheading, "Item"),
            .paragraph(.body, RichText([
                TextRun("b", style: .bold), TextRun("i", style: .italic), TextRun(" "),
                TextRun("u", style: .underline), TextRun("s", style: .strikethrough),
            ])),
            .emptyParagraph,
            .paragraph(.monostyled, "code *raw*"),
            .listItem(ListItem(kind: .bulleted, text: "Bullet")),
            .listItem(ListItem(kind: .dashed, level: 2, text: "Dash")),
            .listItem(ListItem(kind: .numbered, level: 1, text: "Number")),
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "Done")),
            .listItem(ListItem(kind: .checklist, text: "")),
            .table(NoteTable(rows: [["a", RichText([TextRun("b", style: .bold)])], ["", "d"]])),
            .paragraph(.body, "After"),
        ]),
        NoteDocument(blocks: [.paragraph(.body, "Before"), .table(NoteTable(rowCount: 2, columnCount: 3))]),
    ]

    @Test(arguments: documents)
    func documentSurvivesRoundTrip(_ document: NoteDocument) {
        let text = AttributedStringConverter.attributedString(from: document)
        #expect(AttributedStringConverter.document(from: text) == document)
    }

    /// An empty text has no characters to carry a paragraph style, so an empty title becomes body text.
    /// The editor sets the typing attributes for this case instead.
    @Test func emptyNoteHasNoStyle() {
        let text = AttributedStringConverter.attributedString(from: .newNote)
        #expect(text.length == 0)
    }

    @Test func reportsBlockRanges() {
        let document = NoteDocument(blocks: [
            .paragraph(.title, "Hi"),
            .table(NoteTable(rows: [["a", "b"]])),
            .paragraph(.body, "End"),
        ])
        let analysis = AttributedStringConverter.analyze(AttributedStringConverter.attributedString(from: document))
        #expect(analysis.blockRanges == [NSRange(location: 0, length: 3), NSRange(location: 3, length: 4), NSRange(location: 7, length: 3)])
    }

    @Test func usesNotesFonts() {
        let text = AttributedStringConverter.attributedString(from: NoteDocument(blocks: [
            .paragraph(.title, "T"), .paragraph(.body, RichText([TextRun("B", style: .bold)])),
        ]))
        let titleFont = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let boldFont = text.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(titleFont?.pointSize == 24)
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}
