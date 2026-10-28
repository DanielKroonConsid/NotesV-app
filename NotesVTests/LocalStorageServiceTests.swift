import Foundation
import Testing
@testable import NotesV

struct LocalStorageServiceTests {
    let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesVTests-\(UUID().uuidString)")

    private func makeNote(_ title: String, folder: String = "Notes") -> Note {
        Note(folderID: folder, document: NoteDocument(blocks: [.paragraph(.title, RichText(plain: title)), .paragraph(.body, "Body")]))
    }

    private func fileNames(in folder: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: rootURL.appending(path: folder).path(percentEncoded: false)).sorted()
    }

    @Test func savesAndLoadsNotes() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let note = makeNote("Weekly sync")
        try await storage.save(note)

        let library = try await LocalStorageService(rootURL: rootURL).loadLibrary()
        #expect(library.folders == [NoteFolder(name: "Notes")])
        #expect(library.notes == [note])
        #expect(try fileNames(in: "Notes") == ["Weekly sync.md"])
    }

    @Test func renamesTheFileWhenTheTitleChanges() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        var note = makeNote("Draft")
        try await storage.save(note)
        note.document = NoteDocument(blocks: [.paragraph(.title, "Final")])
        try await storage.save(note)

        #expect(try fileNames(in: "Notes") == ["Final.md"])
    }

    @Test func numbersNotesWithTheSameTitle() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let first = makeNote("Sync")
        let second = makeNote("Sync")
        try await storage.save(first)
        try await storage.save(second)
        // Saving again must not rename the file to a new number.
        try await storage.save(second)

        #expect(try fileNames(in: "Notes") == ["Sync (2).md", "Sync.md"])
    }

    @Test func movesTheFileWhenTheFolderChanges() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        var note = makeNote("Sync")
        try await storage.save(note)
        note.folderID = NoteFolder.recentlyDeletedName
        try await storage.save(note)

        #expect(try fileNames(in: "Notes").isEmpty)
        #expect(try fileNames(in: NoteFolder.recentlyDeletedName) == ["Sync.md"])
    }

    @Test func deletesNotes() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let note = makeNote("Sync")
        try await storage.save(note)
        try await storage.deletePermanently(note.id)

        #expect(try fileNames(in: "Notes").isEmpty)
    }

    @Test func managesFolders() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        _ = try await storage.createFolder(named: "Work")
        await #expect(throws: StorageError.self) {
            try await storage.createFolder(named: "Work")
        }

        var note = makeNote("Sync", folder: "Work")
        try await storage.save(note)
        let renamed = try await storage.renameFolder("Work", to: "Projects")
        #expect(renamed.name == "Projects")

        // The storage must still find the note after the rename.
        note.folderID = "Projects"
        note.document = NoteDocument(blocks: [.paragraph(.title, "Sync 2")])
        try await storage.save(note)
        #expect(try fileNames(in: "Projects") == ["Sync 2.md"])

        await #expect(throws: StorageError.self) {
            try await storage.deleteFolder("Projects")
        }
        try await storage.deletePermanently(note.id)
        try await storage.deleteFolder("Projects")
    }

    @Test func readsMarkdownWrittenByOtherApps() async throws {
        let folderURL = rootURL.appending(path: "Imported")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "# Hello\n\n- [ ] Task\n".write(to: folderURL.appending(path: "Hello.md"), atomically: true, encoding: .utf8)
        try "not a note".write(to: folderURL.appending(path: "notes.txt"), atomically: true, encoding: .utf8)

        let library = try await LocalStorageService(rootURL: rootURL).loadLibrary()
        #expect(library.notes.count == 1)
        #expect(library.notes.first?.document.title == "Hello")
        #expect(library.notes.first?.folderID == "Imported")
    }
}
