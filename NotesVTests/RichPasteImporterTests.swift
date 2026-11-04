import AppKit
import Testing
@testable import NotesV

@MainActor
struct RichPasteImporterTests {
    private func line(_ text: String, size: CGFloat = 12, bold: Bool = false, lists: [NSTextList] = []) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.textLists = lists
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return NSAttributedString(string: text + "\n", attributes: [.font: font, .paragraphStyle: style])
    }

    private func joined(_ lines: NSAttributedString...) -> NSAttributedString {
        let result = NSMutableAttributedString()
        lines.forEach(result.append)
        return result
    }

    private func viaRTF(_ text: NSAttributedString) throws -> NSAttributedString {
        let data = try #require(text.rtf(from: NSRange(location: 0, length: text.length)))
        return try #require(NSAttributedString(rtf: data, documentAttributes: nil))
    }

    @Test func worksOutHeadingsFromFontSizes() {
        let document = RichPasteImporter.document(from: joined(
            line("Title", size: 20, bold: true),
            line("Heading", size: 16, bold: true),
            line("Subheading", size: 14, bold: true),
            line("Body one", size: 13),
            line("Body two", size: 13),
            line("Body three", size: 13)
        ))
        #expect(document.blocks == [
            .paragraph(.title, "Title"),
            .paragraph(.heading, "Heading"),
            .paragraph(.subheading, "Subheading"),
            .paragraph(.body, "Body one"),
            .paragraph(.body, "Body two"),
            .paragraph(.body, "Body three"),
        ])
    }

    @Test func keepsInlineStylesThroughRTF() throws {
        let text = NSMutableAttributedString(string: "Bold ", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        text.append(NSAttributedString(string: "plain ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        text.append(NSAttributedString(string: "under", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]))
        let document = RichPasteImporter.document(from: try viaRTF(text))
        #expect(document.blocks == [.paragraph(.body, RichText([
            TextRun("Bold", style: .bold), TextRun(" plain "), TextRun("under", style: .underline),
        ]))])
    }

    @Test func readsTextListsThroughRTF() throws {
        let bullets = NSTextList(markerFormat: .disc, options: 0)
        let numbers = NSTextList(markerFormat: .decimal, options: 0)
        let document = RichPasteImporter.document(from: try viaRTF(joined(
            line("\t•\tBullet", lists: [bullets]),
            line("\t1.\tNumber", lists: [numbers])
        )))
        #expect(document.blocks == [
            .listItem(ListItem(kind: .bulleted, text: "Bullet")),
            .listItem(ListItem(kind: .numbered, text: "Number")),
        ])
    }

    @Test func readsMarkersAndCheckboxesInPlainLines() {
        let document = RichPasteImporter.document(from: joined(
            line("• Bullet"), line("- Dash"), line("2. Number"), line("☐ Todo"), line("☑ Done"), line("Not - a list")
        ))
        #expect(document.blocks == [
            .listItem(ListItem(kind: .bulleted, text: "Bullet")),
            .listItem(ListItem(kind: .dashed, text: "Dash")),
            .listItem(ListItem(kind: .numbered, text: "Number")),
            .listItem(ListItem(kind: .checklist, text: "Todo")),
            .listItem(ListItem(kind: .checklist, isChecked: true, text: "Done")),
            .paragraph(.body, "Not - a list"),
        ])
    }

    @Test func readsHTML() throws {
        let html = """
        <html><body style="font-size:12px"><h1 style="font-size:24px">Title</h1><p>Some <b>bold</b> body text that is the longest part of this note.</p>
        <ul><li>One</li><li>Two</li></ul><ol><li>First</li></ol>
        <table><tr><td>a</td><td>b</td></tr></table></body></html>
        """
        let text = try #require(RichPasteImporter.attributedString(html: Data(html.utf8)))
        let blocks = RichPasteImporter.document(from: text).blocks

        #expect(blocks.first == .paragraph(.title, "Title"))
        #expect(blocks.contains(.listItem(ListItem(kind: .bulleted, text: "One"))))
        #expect(blocks.contains(.listItem(ListItem(kind: .numbered, text: "First"))))
        #expect(blocks.contains(.table(NoteTable(rows: [["a", "b"]]))))
    }

    @Test func removesAttachmentsAndEmptyEdges() {
        let text = NSMutableAttributedString(string: "\n\nText\u{FFFC}\n\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        #expect(RichPasteImporter.document(from: text).blocks == [.paragraph(.body, "Text")])
    }

    @Test func survivesCopyFromNotesV() throws {
        let original = NoteDocument(blocks: [
            .paragraph(.title, "Protokoll"),
            .paragraph(.heading, "Beslut"),
            .paragraph(.body, "Vi gick igenom releasen och budgeten på mötet."),
            .listItem(ListItem(kind: .bulleted, text: "Punkt")),
            .listItem(ListItem(kind: .checklist, text: "Uppgift")),
        ])
        let text = try #require(RichPasteImporter.attributedString(html: Data(EmailFormatter.html(for: original).utf8)))
        #expect(RichPasteImporter.document(from: text) == original)
    }

    @Test func insertsAPastedNoteIntoTheEditor() {
        let (_, textView) = NotesTextView.makeScrollableTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        textView.load(.newNote)

        let pasted = NoteDocument(blocks: [.paragraph(.title, "Title"), .listItem(ListItem(kind: .checklist, text: "Todo"))])
        textView.insert(pasted)

        #expect(AttributedStringConverter.document(from: textView.textStorage!) == pasted)
    }

    /// A new note types in the Title style, which must not rub off on what is pasted.
    @Test func pastedTextKeepsItsOwnFontInANewNote() throws {
        let (_, textView) = NotesTextView.makeScrollableTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        textView.load(.newNote)

        textView.insert(NoteDocument(blocks: [.paragraph(.title, "Title"), .paragraph(.body, "Body")]))

        let storage = try #require(textView.textStorage)
        func fontSize(at location: Int) -> CGFloat? {
            (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize
        }
        #expect(fontSize(at: 0) == 24)
        #expect(fontSize(at: storage.length - 1) == 13)
        #expect(textView.selectedRange().location == storage.length)
    }

    @Test func pastingCanBeUndone() {
        let (_, textView) = NotesTextView.makeScrollableTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        let window = NSWindow(contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = textView
        textView.load(NoteDocument(blocks: [.paragraph(.body, "Before")]))

        textView.setSelectedRange(NSRange(location: 6, length: 0))
        textView.insert(NoteDocument(blocks: [.paragraph(.body, " after")]))
        #expect(textView.string == "Before after")

        textView.undoManager?.undo()
        #expect(textView.string == "Before")
    }
}
