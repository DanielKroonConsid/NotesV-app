import Testing
@testable import NotesV

struct RichTextTests {
    @Test func mergesAdjacentRunsWithTheSameStyle() {
        let text = RichText([TextRun("a", style: .bold), TextRun("b", style: .bold), TextRun("")])
        #expect(text.runs == [TextRun("ab", style: .bold)])
    }

    @Test func dropsEmphasisFromWhitespaceAtTheEdgeOfARegion() {
        let text = RichText([TextRun("bold ", style: .bold), TextRun("plain")])
        #expect(text.runs == [TextRun("bold", style: .bold), TextRun(" plain")])
    }

    @Test func keepsEmphasisOnWhitespaceInsideARegion() {
        let text = RichText([TextRun("a b", style: .bold)])
        #expect(text.runs == [TextRun("a b", style: .bold)])
    }

    @Test func keepsUnderlineOnWhitespace() {
        let text = RichText([TextRun("a"), TextRun(" ", style: .underline), TextRun("b")])
        #expect(text.runs.count == 3)
    }

    @Test func plainText() {
        let text = RichText([TextRun("Hello ", style: .italic), TextRun("world")])
        #expect(text.plainText == "Hello world")
    }
}
