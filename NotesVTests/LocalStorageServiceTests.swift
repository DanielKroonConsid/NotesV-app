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
        #expect(try fileNames(in: "Notes/Projects") == ["Sync 2.md"])

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

struct ExternalChangeTests {
    let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesVTests-\(UUID().uuidString)")

    private func makeNote(_ title: String) -> Note {
        Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.title, RichText(plain: title)), .paragraph(.body, "Body")]))
    }

    private func fileURL(of title: String) -> URL {
        rootURL.appending(path: "Notes/\(title).md")
    }

    /// Replaces the note's body in its file, like another Markdown editor would.
    private func editFile(of title: String, body: String) throws {
        let text = try String(contentsOf: fileURL(of: title), encoding: .utf8)
        try text.replacingOccurrences(of: "Body", with: body).write(to: fileURL(of: title), atomically: true, encoding: .utf8)
    }

    @Test func refusesToOverwriteAChangedFile() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        var note = makeNote("Sync")
        try await storage.save(note)
        try editFile(of: "Sync", body: "Changed elsewhere")

        note.isPinned = true
        await #expect(throws: StorageError.self) { try await storage.save(note) }
        #expect(try String(contentsOf: fileURL(of: "Sync"), encoding: .utf8).contains("Changed elsewhere"))
    }

    @Test func keepsSavingWhenTheFileIsUnchanged() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        var note = makeNote("Sync")
        try await storage.save(note)
        note.isPinned = true
        try await storage.save(note)
        _ = try await storage.loadLibrary()
        note.isPinned = false
        try await storage.save(note)
    }

    @Test func aCopiedFileKeepsItsIDBetweenLoads() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        try await storage.save(makeNote("Sync"))
        try FileManager.default.copyItem(at: fileURL(of: "Sync"), to: fileURL(of: "Sync copy"))

        let first = try await storage.loadLibrary()
        let second = try await storage.loadLibrary()
        #expect(first.notes.count == 2)
        #expect(Set(first.notes.map(\.id)) == Set(second.notes.map(\.id)))
    }

    @MainActor
    @Test func refreshPicksUpChangesMadeOutsideTheApp() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let note = makeNote("Sync")
        let removed = makeNote("Old")
        try await storage.save(note)
        try await storage.save(removed)
        let store = NoteStore(storage: storage)
        await store.load()

        try editFile(of: "Sync", body: "Changed elsewhere")
        try FileManager.default.removeItem(at: fileURL(of: "Old"))
        await store.refresh()

        #expect(store.notes[note.id]?.document.plainText.contains("Changed elsewhere") == true)
        #expect(store.notes[removed.id] == nil)
    }

    @MainActor
    @Test func keepsBothVersionsWhenTheFileChangedDuringAnEdit() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let note = makeNote("Sync")
        try await storage.save(note)
        let store = NoteStore(storage: storage)
        await store.load()

        try editFile(of: "Sync", body: "Changed elsewhere")
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, RichText(plain: "Sync")), .paragraph(.body, "Changed here")]), of: note.id)
        await store.refresh()

        let texts = store.notes.values.map(\.document.plainText)
        #expect(texts.count == 2)
        #expect(texts.contains { $0.contains("Changed elsewhere") })
        #expect(texts.contains { $0.contains("Changed here") })
        #expect(store.errorMessage != nil)
    }
}

@MainActor
struct StorageFolderTests {
    let baseURL = FileManager.default.temporaryDirectory.appending(path: "NotesVTests-\(UUID().uuidString)")
    let suiteName = "NotesVTests-\(UUID().uuidString)"

    @Test func notesGoInAFolderOfTheirOwn() {
        let picked = URL(filePath: "/Users/a/OneDrive", directoryHint: .isDirectory)
        #expect(StorageFolderBookmark.notesRoot(in: picked).lastPathComponent == "NotesV")
        let named = URL(filePath: "/Users/a/OneDrive/NotesV", directoryHint: .isDirectory)
        #expect(StorageFolderBookmark.notesRoot(in: named) == named)
    }

    @Test func movingCopiesNotesAndFoldersAndKeepsTheOriginals() async throws {
        let source = InMemoryStorageService()
        let note = Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.body, "Hello")]))
        try await source.save(note)
        _ = try await source.createFolder(named: "Projekt")
        let store = NoteStore(storage: source)
        await store.load()

        let destination = InMemoryStorageService()
        try await store.moveLibrary(to: destination)

        #expect(await destination.savedNotes[note.id] == note)
        #expect(await source.savedNotes[note.id] == note)
        #expect(store.folders.contains { $0.name == "Projekt" })
        #expect(store.notes[note.id] == note)
    }

    @Test func movingKeepsNotesAlreadyInTheDestination() async throws {
        let id = UUID()
        let source = InMemoryStorageService()
        try await source.save(Note(id: id, folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.body, "Here")])))
        let destination = InMemoryStorageService()
        let existing = Note(id: id, folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.body, "There")]))
        try await destination.save(existing)
        let store = NoteStore(storage: source)
        await store.load()

        try await store.moveLibrary(to: destination)
        #expect(store.notes[id] == existing)
    }

    @Test func remembersThePickedFolder() async throws {
        let defaultRoot = baseURL.appending(path: "Default")
        let picked = baseURL.appending(path: "Picked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let settings = StorageSettings(defaultRootURL: defaultRoot, defaultsSuiteName: suiteName)
        let store = NoteStore(storage: InMemoryStorageService())
        await store.load()

        await settings.useFolder(picked, store: store)
        #expect(settings.errorMessage == nil)

        let restored = StorageSettings(defaultRootURL: defaultRoot, defaultsSuiteName: suiteName)
        #expect(!restored.isFolderMissing)
        #expect(restored.rootURL.standardizedFileURL.path().hasSuffix("/Picked/NotesV/"))
    }

    @Test func reportsAFolderThatIsGone() async throws {
        let defaultRoot = baseURL.appending(path: "Default")
        let picked = baseURL.appending(path: "Picked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let settings = StorageSettings(defaultRootURL: defaultRoot, defaultsSuiteName: suiteName)
        let store = NoteStore(storage: InMemoryStorageService())
        await store.load()
        await settings.useFolder(picked, store: store)
        try FileManager.default.removeItem(at: picked)

        let restored = StorageSettings(defaultRootURL: defaultRoot, defaultsSuiteName: suiteName)
        #expect(restored.isFolderMissing)
        #expect(restored.rootURL == defaultRoot)
    }
}

struct SubfolderStorageTests {
    let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesVTests-\(UUID().uuidString)")

    private func write(_ text: String, to path: String) throws {
        let url = rootURL.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A note file as NotesV writes it.
    private func note(_ body: String) -> String {
        "---\nid: \(UUID().uuidString)\n---\n\(body)"
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appending(path: path).path(percentEncoded: false))
    }

    @Test func userFoldersAreStoredInsideNotes() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        _ = try await storage.createFolder(named: "Smekab")
        try await storage.save(Note(folderID: "Smekab", document: NoteDocument(blocks: [.paragraph(.title, "Sync")])))
        try await storage.save(Note(folderID: NoteFolder.meetingProtocolsName, document: NoteDocument(blocks: [.paragraph(.title, "Minutes")])))

        #expect(exists("Notes/Smekab/Sync.md"))
        #expect(exists("Meeting Protocols/Minutes.md"))
        #expect(!exists("Smekab"))

        let library = try await storage.loadLibrary()
        #expect(Set(library.folders.map(\.name)) == ["Notes", "Smekab", "Meeting Protocols"])
        #expect(library.notes.first { $0.title == "Sync" }?.folderID == "Smekab")
    }

    @Test func existingFoldersMoveIntoNotes() async throws {
        try write(note("# Sync\n"), to: "Smekab/Sync.md")
        try write(note("# VAS\n"), to: "VAS/VAS.md")
        try write(note("# Plain\n"), to: "Notes/Plain.md")
        try write(note("# Minutes\n"), to: "Meeting Protocols/Minutes.md")
        try write(note("# Old\n"), to: "Recently Deleted/Old.md")

        let library = try await LocalStorageService(rootURL: rootURL).loadLibrary()

        #expect(exists("Notes/Smekab/Sync.md"))
        #expect(exists("Notes/VAS/VAS.md"))
        #expect(exists("Meeting Protocols/Minutes.md"))
        #expect(exists("Recently Deleted/Old.md"))
        #expect(!exists("Smekab"))
        #expect(!exists("VAS"))
        #expect(library.notes.count == 5)
        #expect(library.notes.first { $0.title == "Sync" }?.folderID == "Smekab")
    }

    @Test func aFolderInBothPlacesIsMergedWithoutLosingNotes() async throws {
        try write(note("# Sync\n\nFrom the old place\n"), to: "Smekab/Sync.md")
        let same = note("# Same\n")
        try write(same, to: "Smekab/Same.md")
        try write(note("# New\n"), to: "Smekab/New.md")
        try write(note("# Sync\n\nFrom the new place\n"), to: "Notes/Smekab/Sync.md")
        try write(same, to: "Notes/Smekab/Same.md")

        let library = try await LocalStorageService(rootURL: rootURL).loadLibrary()

        #expect(!exists("Smekab"))
        #expect(library.notes.count == 4)
        let texts = library.notes.map(\.document.plainText)
        #expect(texts.contains { $0.contains("From the old place") })
        #expect(texts.contains { $0.contains("From the new place") })
    }

    @Test func aFolderThatCantBeEmptiedKeepsItsOtherFiles() async throws {
        try write(note("# Sync\n"), to: "Smekab/Sync.md")
        try write("one", to: "Smekab/data.txt")
        try write(note("# Other\n"), to: "Notes/Smekab/Other.md")
        try write("two", to: "Notes/Smekab/data.txt")

        let library = try await LocalStorageService(rootURL: rootURL).loadLibrary()

        #expect(exists("Smekab/data.txt"))
        #expect(library.notes.count == 2)
        #expect(library.folders.filter { $0.name == "Smekab" }.count == 1)
    }

    @Test func foldersThatArentNoteFoldersStayWhereTheyAre() async throws {
        try write("# Read me\n", to: "Source/README.md")
        try write("let a = 1", to: "Source/main.swift")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "Empty"), withIntermediateDirectories: true)

        _ = try await LocalStorageService(rootURL: rootURL).loadLibrary()

        #expect(exists("Source/README.md"))
        #expect(exists("Source/main.swift"))
        #expect(!exists("Notes/Source"))
        #expect(exists("Notes/Empty"))
    }

    @Test func movingToAnEmptyFolderKeepsSubfolders() async throws {
        let source = LocalStorageService(rootURL: rootURL.appending(path: "source"))
        _ = try await source.createFolder(named: "Smekab")
        let note = Note(folderID: "Smekab", document: NoteDocument(blocks: [.paragraph(.title, "Sync")]))
        try await source.save(note)
        try await source.save(Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.title, "Plain")])))
        let store = await NoteStore(storage: source)
        await store.load()

        try await store.moveLibrary(to: LocalStorageService(rootURL: rootURL.appending(path: "target")))

        #expect(exists("target/Notes/Smekab/Sync.md"))
        #expect(exists("target/Notes/Plain.md"))
        #expect(exists("source/Notes/Smekab/Sync.md"))
        #expect(await store.errorMessage == nil)
    }
}
