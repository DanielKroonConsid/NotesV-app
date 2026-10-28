import AppKit
import Testing
@testable import NotesV

/// Drives the editor the way typing and menu commands do, and checks the resulting document.
@MainActor
struct NotesTextViewTests {
    private func makeTextView(_ document: NoteDocument) -> NotesTextView {
        let (_, textView) = NotesTextView.makeScrollableTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        textView.load(document)
        return textView
    }

    private func document(of textView: NotesTextView) -> NoteDocument {
        AttributedStringConverter.document(from: textView.textStorage!)
    }

    private func moveToEnd(_ textView: NotesTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    @Test func returnInAListContinuesTheList() {
        let textView = makeTextView(NoteDocument(blocks: [.listItem(ListItem(kind: .checklist, isChecked: true, text: "One"))]))
        moveToEnd(textView)
        textView.insertNewline(nil)
        textView.insertText("Two", replacementRange: textView.selectedRange())

        #expect(document(of: textView).blocks == [
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "One")),
            .listItem(ListItem(kind: .checklist, isChecked: false, text: "Two")),
        ])
    }

    @Test func returnOnAnEmptyListItemEndsTheList() {
        let textView = makeTextView(NoteDocument(blocks: [.listItem(ListItem(kind: .bulleted, text: "One"))]))
        moveToEnd(textView)
        textView.insertNewline(nil)
        textView.insertNewline(nil)
        textView.insertText("Body", replacementRange: textView.selectedRange())

        #expect(document(of: textView).blocks == [
            .listItem(ListItem(kind: .bulleted, text: "One")),
            .paragraph(.body, "Body"),
        ])
    }

    @Test func returnAfterATitleContinuesWithBody() {
        let textView = makeTextView(.newNote)
        textView.insertText("Weekly sync", replacementRange: textView.selectedRange())
        textView.insertNewline(nil)
        textView.insertText("Notes", replacementRange: textView.selectedRange())

        #expect(document(of: textView).blocks == [.paragraph(.title, "Weekly sync"), .paragraph(.body, "Notes")])
    }

    @Test func formatCommandsChangeTheParagraph() {
        let textView = makeTextView(NoteDocument(blocks: [.paragraph(.body, "Task"), .paragraph(.body, "Other")]))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.toggleChecklist(nil)
        textView.toggleChecked(nil)
        #expect(document(of: textView).blocks.first == .listItem(ListItem(kind: .checklist, isChecked: true, text: "Task")))

        textView.increaseListIndent(nil)
        #expect(document(of: textView).blocks.first == .listItem(ListItem(kind: .checklist, level: 1, isChecked: true, text: "Task")))

        textView.toggleChecklist(nil)
        #expect(document(of: textView).blocks.first == .paragraph(.body, "Task"))

        textView.formatHeading(nil)
        #expect(document(of: textView).blocks == [.paragraph(.heading, "Task"), .paragraph(.body, "Other")])
    }

    @Test func boldTogglesOnTheSelection() {
        let textView = makeTextView(NoteDocument(blocks: [.paragraph(.body, "Hello world")]))
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.toggleNotesBold(nil)
        #expect(document(of: textView).blocks == [
            .paragraph(.body, RichText([TextRun("Hello", style: .bold), TextRun(" world")])),
        ])

        textView.toggleNotesBold(nil)
        #expect(document(of: textView).blocks == [.paragraph(.body, "Hello world")])
    }

    @Test func backspaceAtTheStartOfAListItemRemovesTheList() {
        let textView = makeTextView(NoteDocument(blocks: [.listItem(ListItem(kind: .numbered, text: "One"))]))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.deleteBackward(nil)

        #expect(document(of: textView).blocks == [.paragraph(.body, "One")])
    }

    @Test func tablesCanBeInsertedAndEdited() {
        let textView = makeTextView(NoteDocument(blocks: [.paragraph(.body, "Before")]))
        moveToEnd(textView)
        textView.insertNotesTable(nil)
        textView.insertText("A", replacementRange: textView.selectedRange())
        textView.insertTab(nil)
        textView.insertText("B", replacementRange: textView.selectedRange())
        textView.addTableRow(nil)

        guard case .table(let table) = document(of: textView).blocks[1] else {
            Issue.record("Expected a table after the first paragraph")
            return
        }
        #expect(table.rowCount == 3)
        #expect(table.rows[0] == ["A", "B"])
    }
}
