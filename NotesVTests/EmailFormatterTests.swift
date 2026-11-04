import Foundation
import Testing
@testable import NotesV

struct EmailFormatterTests {
    private func body(of document: NoteDocument) -> String {
        EmailFormatter.html(for: document)
            .replacingOccurrences(of: #" style="[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^.*?<div>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</div></body></html>", with: "")
    }

    @Test func writesHeadingsAndInlineStyles() {
        let document = NoteDocument(blocks: [
            .paragraph(.title, "T"),
            .paragraph(.heading, "H"),
            .emptyParagraph,
            .paragraph(.body, RichText([TextRun("a", style: .bold), TextRun(" b<c & d>")])),
        ])
        #expect(body(of: document) == "<h1>T</h1><h2>H</h2><p><b>a</b> b&lt;c &amp; d&gt;</p>")
    }

    @Test func writesLists() {
        let document = NoteDocument(blocks: [
            .listItem(ListItem(kind: .bulleted, text: "A")),
            .listItem(ListItem(kind: .bulleted, text: "B")),
            .listItem(ListItem(kind: .numbered, level: 1, text: "C")),
            .listItem(ListItem(kind: .bulleted, text: "D")),
        ])
        #expect(body(of: document) == "<ul><li>A</li><li>B<ol><li>C</li></ol></li><li>D</li></ul>")
    }

    @Test func writesCheckboxesAndDashesAsText() {
        let document = NoteDocument(blocks: [
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "A")),
            .listItem(ListItem(kind: .checklist, text: "B")),
            .listItem(ListItem(kind: .dashed, text: "C")),
        ])
        #expect(body(of: document) == "<ul><li>☑ A</li><li>☐ B</li><li>– C</li></ul>")
    }

    @Test func switchesListTypeAtTheSameLevel() {
        let document = NoteDocument(blocks: [
            .listItem(ListItem(kind: .bulleted, text: "A")),
            .listItem(ListItem(kind: .numbered, text: "B")),
        ])
        #expect(body(of: document) == "<ul><li>A</li></ul><ol><li>B</li></ol>")
    }

    @Test func writesTables() {
        let document = NoteDocument(blocks: [.table(NoteTable(rows: [["a", "b"]]))])
        #expect(body(of: document) == "<table><tr><td>a</td><td>b</td></tr></table>")
    }

    @Test func writesPlainText() {
        let document = NoteDocument(blocks: [
            .paragraph(.title, "T"),
            .paragraph(.heading, "H"),
            .paragraph(.body, "Text"),
            .listItem(ListItem(kind: .bulleted, text: "A")),
            .listItem(ListItem(kind: .numbered, level: 1, text: "B")),
            .listItem(ListItem(kind: .numbered, level: 1, text: "C")),
            .listItem(ListItem(kind: .checklist, text: "D")),
            .table(NoteTable(rows: [["a", "b"]])),
        ])
        #expect(EmailFormatter.plainText(for: document) == """
        T

        H
        Text
        • A
            1. B
            2. C
        ☐ D
        a\tb
        """)
    }

    @Test @MainActor func clipboardContentsIncludeAllFormats() {
        let contents = EmailClipboard.contents(for: NoteDocument(blocks: [.paragraph(.title, "Protokoll")]))
        #expect(contents.html.contains("Protokoll"))
        #expect(contents.plainText == "Protokoll")
        #expect(contents.rtf != nil)
    }
}
