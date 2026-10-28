import Foundation
import Testing
@testable import NotesV

struct MarkdownCodecTests {
    // MARK: Encoding

    @Test func encodesEveryParagraphStyle() {
        let document = NoteDocument(blocks: [
            .paragraph(.title, "Title"),
            .paragraph(.heading, "Heading"),
            .paragraph(.subheading, "Subheading"),
            .paragraph(.body, "Body"),
            .paragraph(.monostyled, "let x = 1"),
            .paragraph(.monostyled, "print(x)"),
        ])
        #expect(MarkdownCodec.encodeBody(document) == """
        # Title

        ## Heading

        ### Subheading

        Body

        ```
        let x = 1
        print(x)
        ```

        """)
    }

    @Test func encodesInlineStyles() {
        let text = RichText([
            TextRun("bold", style: .bold),
            TextRun(" "),
            TextRun("italic", style: .italic),
            TextRun(" "),
            TextRun("under", style: .underline),
            TextRun(" "),
            TextRun("strike", style: .strikethrough),
        ])
        #expect(MarkdownCodec.encodeInline(text) == "**bold** *italic* <u>under</u> ~~strike~~")
    }

    @Test func encodesLists() {
        let document = NoteDocument(blocks: [
            .listItem(ListItem(kind: .bulleted, text: "Bullet")),
            .listItem(ListItem(kind: .dashed, level: 1, text: "Dash")),
            .listItem(ListItem(kind: .numbered, text: "One")),
            .listItem(ListItem(kind: .numbered, text: "Two")),
            .listItem(ListItem(kind: .checklist, text: "Todo")),
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "Done")),
        ])
        #expect(MarkdownCodec.encodeBody(document) == """
        * Bullet
            - Dash
        1. One
        2. Two
        - [ ] Todo
        - [x] Done

        """)
    }

    @Test func encodesTables() {
        let table = NoteTable(rows: [["Name", "Role"], ["Ada", "Engineer | Lead"]])
        #expect(MarkdownCodec.encodeBody(NoteDocument(blocks: [.table(table)])) == """
        | Name | Role |
        | --- | --- |
        | Ada | Engineer \\| Lead |

        """)
    }

    @Test func emptyParagraphsAddBlankLines() {
        let document = NoteDocument(blocks: [
            .paragraph(.body, "A"),
            .emptyParagraph,
            .emptyParagraph,
            .paragraph(.body, "B"),
        ])
        #expect(MarkdownCodec.encodeBody(document) == "A\n\n\n\nB\n")
    }

    @Test func escapesTextThatLooksLikeMarkdown() {
        let document = NoteDocument(blocks: [.paragraph(.body, "# not a heading *or* emphasis")])
        #expect(MarkdownCodec.encodeBody(document) == "\\# not a heading \\*or\\* emphasis\n")
    }

    // MARK: Round trips

    static let roundTripDocuments: [NoteDocument] = [
        NoteDocument(),
        NoteDocument(blocks: [.emptyParagraph, .emptyParagraph]),
        NoteDocument(blocks: [.emptyParagraph, .paragraph(.title, "Late title"), .emptyParagraph]),
        NoteDocument(blocks: [
            .paragraph(.title, "Weekly sync"),
            .paragraph(.body, RichText([
                TextRun("Mixed "),
                TextRun("bold", style: .bold),
                TextRun("bolditalic", style: [.bold, .italic]),
                TextRun("italic", style: .italic),
                TextRun(" and "),
                TextRun("all", style: [.bold, .italic, .underline, .strikethrough]),
                TextRun(" "),
                TextRun("u s", style: [.underline, .strikethrough]),
            ])),
            .emptyParagraph,
            .paragraph(.heading, "Decisions #"),
            .listItem(ListItem(kind: .numbered, text: "First")),
            .listItem(ListItem(kind: .numbered, level: 1, text: "Nested")),
            .listItem(ListItem(kind: .bulleted, level: 3, text: "Deep")),
            .listItem(ListItem(kind: .numbered, text: "Second")),
            .listItem(ListItem(kind: .dashed, text: "[ ] not a checkbox")),
            .listItem(ListItem(kind: .checklist, text: "")),
            .listItem(ListItem(kind: .checklist, isChecked: true, text: RichText([TextRun("done", style: .bold)]))),
            .paragraph(.subheading, "Code"),
            .paragraph(.monostyled, "```swift"),
            .paragraph(.monostyled, ""),
            .paragraph(.monostyled, "  indented *raw*"),
            .table(NoteTable(rows: [["a", RichText([TextRun("b", style: .bold)])], ["c | d", ""]])),
            .emptyParagraph,
        ]),
    ]

    @Test(arguments: roundTripDocuments)
    func documentSurvivesRoundTrip(_ document: NoteDocument) {
        let markdown = MarkdownCodec.encodeBody(document)
        #expect(MarkdownCodec.decodeBody(markdown) == document, "Markdown:\n\(markdown)")
    }

    static let trickyLines = [
        "# hash", "## two", "- dash", "+ plus", "* star", "1. one", "12) twelve", "> quote", "| pipe",
        "snake_case_name", "_leading underscore", "trailing_", "a * b * c", "2 ** 3",
        "~tilde~", "~~double~~", "<u>tag</u>", "a < b > c", "back\\slash", "`code`", "[link](url)",
        "C#", "100%", "---", "***", "===", "\\", "#", "1.",
    ]

    @Test(arguments: trickyLines)
    func plainTextSurvivesRoundTrip(_ line: String) {
        for block in [Block.paragraph(.body, RichText(plain: line)), .paragraph(.title, RichText(plain: line)),
                      .listItem(ListItem(kind: .bulleted, text: RichText(plain: line))),
                      .table(NoteTable(rows: [[RichText(plain: line)]]))] {
            let document = NoteDocument(blocks: [block])
            let markdown = MarkdownCodec.encodeBody(document)
            #expect(MarkdownCodec.decodeBody(markdown) == document, "Markdown:\n\(markdown)")
        }
    }

    /// Leading whitespace is kept in body paragraphs only. Headings, list items and table cells trim it,
    /// like Markdown does.
    @Test func bodyParagraphKeepsLeadingWhitespace() {
        let document = NoteDocument(blocks: [.paragraph(.body, "    four spaces"), .paragraph(.body, "  - not a list")])
        #expect(MarkdownCodec.decodeBody(MarkdownCodec.encodeBody(document)) == document)
    }

    @Test func noteSurvivesRoundTripWithFrontMatter() {
        let note = Note(
            folderID: "Notes",
            created: Date(timeIntervalSince1970: 1_800_000_000),
            modified: Date(timeIntervalSince1970: 1_800_000_600),
            isPinned: true,
            meeting: MeetingReference(eventID: "AAMkAG\"x\"", subject: "Weekly: sync", start: Date(timeIntervalSince1970: 1_800_000_000)),
            document: NoteDocument(blocks: [.paragraph(.title, "Weekly sync"), .paragraph(.body, "Notes")])
        )
        let decoded = MarkdownCodec.decode(MarkdownCodec.encode(note))
        #expect(decoded.fields == FrontMatter.Fields(
            id: note.id, created: note.created, modified: note.modified, isPinned: true, meeting: note.meeting
        ))
        #expect(decoded.document == note.document)
    }

    @Test func writesFrontMatterInTheDocumentedFormat() {
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        let note = Note(
            id: id, folderID: "Notes",
            created: Date(timeIntervalSince1970: 1_792_486_800), modified: Date(timeIntervalSince1970: 1_792_489_500),
            document: NoteDocument(blocks: [.paragraph(.title, "Hello")])
        )
        #expect(MarkdownCodec.encode(note) == """
        ---
        id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
        created: 2026-10-20T09:00:00Z
        modified: 2026-10-20T09:45:00Z
        pinned: false
        ---

        # Hello

        """)
    }

    // MARK: Markdown from other editors

    @Test func readsFilesWithoutFrontMatter() {
        let decoded = MarkdownCodec.decode("# Hello\nWorld\n")
        #expect(decoded.fields == nil)
        #expect(decoded.document == NoteDocument(blocks: [.paragraph(.title, "Hello"), .paragraph(.body, "World")]))
    }

    @Test func readsCommonMarkdownVariants() {
        let markdown = """
        #### Small heading ##
        __bold__ and _italic_ and **unclosed

        - [X] Done
          - two-space nested
            - deeper
        * after

        ~~~
        tilde fence
        ~~~
        """
        let document = MarkdownCodec.decodeBody(markdown)
        #expect(document.blocks == [
            .paragraph(.subheading, "Small heading"),
            .paragraph(.body, RichText([
                TextRun("bold", style: .bold), TextRun(" and "), TextRun("italic", style: .italic), TextRun(" and **unclosed"),
            ])),
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "Done")),
            .listItem(ListItem(kind: .dashed, level: 1, text: "two-space nested")),
            .listItem(ListItem(kind: .dashed, level: 2, text: "deeper")),
            .listItem(ListItem(kind: .bulleted, text: "after")),
            .paragraph(.monostyled, "tilde fence"),
        ])
    }

    @Test func readsWindowsLineEndings() {
        let decoded = MarkdownCodec.decode("---\r\npinned: true\r\n---\r\n\r\nHi\r\n")
        #expect(decoded.fields?.isPinned == true)
        #expect(decoded.document == NoteDocument(blocks: [.paragraph(.body, "Hi")]))
    }
}
