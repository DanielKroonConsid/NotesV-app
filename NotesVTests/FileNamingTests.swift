import Testing
@testable import NotesV

struct FileNamingTests {
    @Test(arguments: [
        ("Weekly sync", "Weekly sync"),
        ("  a/b:c?  ", "a b c"),
        ("...hidden", "hidden"),
        ("", "Untitled"),
        ("///", "Untitled"),
        ("Line\nbreak", "Line break"),
    ])
    func sanitizesNames(_ input: String, _ expected: String) {
        #expect(FileNaming.sanitizedName(input) == expected)
    }

    @Test func limitsLength() {
        #expect(FileNaming.sanitizedName(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func numbersDuplicates() {
        #expect(FileNaming.noteFileName(title: "Sync") == "Sync.md")
        #expect(FileNaming.noteFileName(title: "Sync", number: 2) == "Sync (2).md")
        #expect(FileNaming.baseName(ofNoteFileName: "Sync (2).md") == "Sync")
        #expect(FileNaming.baseName(ofNoteFileName: "Sync.md") == "Sync")
    }
}
