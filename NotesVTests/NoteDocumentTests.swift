import Foundation
import Testing
@testable import NotesV

struct NoteDocumentTests {
    @Test func titleAndPreviewSkipEmptyLines() {
        let document = NoteDocument(blocks: [
            .emptyParagraph, .paragraph(.title, " Weekly sync "), .emptyParagraph, .paragraph(.body, "First point"),
        ])
        #expect(document.title == "Weekly sync")
        #expect(document.previewText == "First point")
        #expect(document.hasContent)
    }

    @Test func newNoteHasNoContent() {
        #expect(!NoteDocument.newNote.hasContent)
        #expect(NoteDocument(blocks: []).blocks == [.emptyParagraph])
    }

    @Test func tableIsAlwaysRectangular() {
        let table = NoteTable(rows: [["a"], ["b", "c"]])
        #expect(table.columnCount == 2)
        #expect(table[0, 1] == RichText())
    }

    @Test func dateGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_497_600) // 2026-10-20 12:00 UTC
        func group(daysAgo: Double) -> NoteDateGroup {
            NoteDateGroup(date: now.addingTimeInterval(-daysAgo * 86_400), now: now, calendar: calendar)
        }
        #expect(group(daysAgo: 0) == .today)
        #expect(group(daysAgo: 1) == .yesterday)
        #expect(group(daysAgo: 5) == .previous7Days)
        #expect(group(daysAgo: 20) == .previous30Days)
        #expect(group(daysAgo: 60) == .month(year: 2026, month: 8))
    }
}
