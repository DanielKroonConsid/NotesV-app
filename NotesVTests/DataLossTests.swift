import AppKit
import CryptoKit
import Foundation
import Testing
@testable import NotesV

/// Checks that nothing the user wrote is lost when files, folders or settings don't look as expected.
struct FrontMatterPreservationTests {
    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    @Test func keysFromOtherAppsSurviveASave() {
        let text = """
        ---
        id: \(id.uuidString)
        tags:
          - work
          - sync
        aliases: [Veckomöte]
        pinned: false
        ---
        Body

        """
        let decoded = MarkdownCodec.decode(text)
        #expect(decoded.fields?.extraEntries.map(\.key) == ["tags", "aliases"])

        let note = Note(id: id, folderID: "Notes", extraFrontMatter: decoded.fields?.extraEntries ?? [], document: decoded.document)
        let saved = MarkdownCodec.encode(note)
        #expect(saved.contains("tags:\n  - work\n  - sync\naliases: [Veckomöte]\n---"))
        #expect(MarkdownCodec.decode(saved).fields?.extraEntries == decoded.fields?.extraEntries)
    }

    @Test func readsBlockListsBlockTextAndDatesWithoutAZone() throws {
        let text = """
        ---
        meeting:
          subject: Sync
          start: 2026-10-20 09:00
          end: 2026-10-20T10:00
          attendees:
          - Ada Ek
          - "Bo Berg"
          agenda: |
            Release
            Budget
        ---

        """
        let meeting = try #require(MarkdownCodec.decode(text).fields?.meeting)
        let calendar = Calendar.current
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: meeting.start)
            == DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 0))
        #expect(meeting.end.map { calendar.component(.hour, from: $0) } == 10)
        #expect(meeting.attendees == ["Ada Ek", "Bo Berg"])
        #expect(meeting.agenda == "Release\nBudget")
    }

    @Test func aMeetingThatCantBeReadIsKeptAsWritten() throws {
        let text = "---\nmeeting:\n  subject: Sync\n  start: next week\n---\nBody\n"
        let fields = try #require(MarkdownCodec.decode(text).fields)
        #expect(fields.meeting == nil)

        let note = Note(folderID: "Notes", extraFrontMatter: fields.extraEntries, document: NoteDocument(blocks: [.paragraph(.body, "Body")]))
        #expect(MarkdownCodec.encode(note).contains("meeting:\n  subject: Sync\n  start: next week\n---"))

        // A meeting the user adds later replaces the old one instead of being written twice.
        var withMeeting = note
        withMeeting.meeting = MeetingDetails(title: "New", start: .now)
        let saved = MarkdownCodec.encode(withMeeting)
        #expect(saved.components(separatedBy: "meeting:").count == 2)
        #expect(!saved.contains("next week"))
    }

    @Test(arguments: [
        "\u{FEFF}---\nid: ID\n---\nBody\n",
        "---\r\nid: ID\r\n---\r\nBody\r\n",
        "---\rid: ID\r---\rBody\r",
        "---  \nid: ID\n--- \nBody\n",
        "---\nid: ID\n...\nBody\n",
    ])
    func findsFrontMatterWrittenByOtherEditors(text: String) {
        let decoded = MarkdownCodec.decode(text.replacingOccurrences(of: "ID", with: id.uuidString))
        #expect(decoded.fields?.id == id)
        #expect(decoded.document.plainText == "Body")
    }
}

struct StorageDataLossTests {
    let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesVTests-\(UUID().uuidString)")

    private func notesFile(_ name: String) -> URL {
        rootURL.appending(path: "Notes/\(name)")
    }

    @Test func aCopyGetsANewIDThatIsWrittenToItsFile() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let original = Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.title, "Sync")]))
        try await storage.save(original)
        try FileManager.default.copyItem(at: notesFile("Sync.md"), to: notesFile("Sync copy.md"))
        // The copy is newer, so the original keeps its id whichever file is listed first.
        try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: notesFile("Sync copy.md").path(percentEncoded: false))

        let first = try await LocalStorageService(rootURL: rootURL).loadLibrary()
        let copyID = try #require(first.notes.first { $0.id != original.id }?.id)
        #expect(first.notes.contains { $0.id == original.id })

        let copyText = try String(contentsOf: notesFile("Sync copy.md"), encoding: .utf8)
        #expect(copyText.contains("id: \(copyID.uuidString)"))

        let second = try await LocalStorageService(rootURL: rootURL).loadLibrary()
        #expect(Set(second.notes.map(\.id)) == [original.id, copyID])
    }

    @Test func aFolderThatCantBeListedIsNotDeleted() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        _ = try await storage.createFolder(named: "Locked")
        let folderURL = rootURL.appending(path: "Notes/Locked")
        try Data("x".utf8).write(to: folderURL.appending(path: "Kept.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folderURL.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderURL.path(percentEncoded: false)) }

        await #expect(throws: (any Error).self) { try await storage.deleteFolder("Locked") }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderURL.path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: folderURL.appending(path: "Kept.md").path(percentEncoded: false)))
    }

    @Test func aFileChangedOutsideTheAppIsNotDeletedPermanently() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        let note = Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.title, "Sync")]))
        try await storage.save(note)
        try (try String(contentsOf: notesFile("Sync.md"), encoding: .utf8) + "Added elsewhere\n")
            .write(to: notesFile("Sync.md"), atomically: true, encoding: .utf8)

        await #expect(throws: StorageError.self) { try await storage.deletePermanently(note.id) }
        #expect(FileManager.default.fileExists(atPath: notesFile("Sync.md").path(percentEncoded: false)))
    }

    @Test func aFailedLoadKeepsWhatTheServiceKnowsAboutEachFile() async throws {
        let storage = LocalStorageService(rootURL: rootURL)
        var note = Note(folderID: "Notes", document: NoteDocument(blocks: [.paragraph(.title, "Sync")]))
        try await storage.save(note)
        _ = try await storage.loadLibrary()

        let lockedURL = rootURL.appending(path: "Notes/Locked")
        try FileManager.default.createDirectory(at: lockedURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedURL.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedURL.path(percentEncoded: false)) }
        await #expect(throws: (any Error).self) { try await storage.loadLibrary() }

        // The note is still saved to its own file, not to a new "Sync (2).md".
        note.document = NoteDocument(blocks: [.paragraph(.title, "Sync"), .paragraph(.body, "More")])
        try await storage.save(note)
        let names = try FileManager.default.contentsOfDirectory(atPath: rootURL.appending(path: "Notes").path(percentEncoded: false))
        #expect(names.filter { $0.hasSuffix(".md") } == ["Sync.md"])
    }
}

@MainActor
struct NoteStoreDataLossTests {
    private func makeStore() async -> (NoteStore, InMemoryStorageService, UUID) {
        let storage = InMemoryStorageService()
        let store = NoteStore(storage: storage)
        await store.load()
        store.createNote()
        let noteID = store.selectedNoteID!
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Viktigt")]), of: noteID)
        return (store, storage, noteID)
    }

    @Test func quittingReportsNotesThatCouldNotBeSaved() async {
        let (store, storage, noteID) = await makeStore()
        await storage.setFailsToSave(true)
        #expect(await store.prepareForTermination() == 1)

        // A note that failed before is tried again, not forgotten.
        await storage.setFailsToSave(false)
        #expect(await store.prepareForTermination() == 0)
        #expect(await storage.savedNotes[noteID]?.title == "Viktigt")
    }

    @Test func theFolderIsNotChangedWhileNotesAreUnsaved() async {
        let (store, storage, _) = await makeStore()
        await storage.setFailsToSave(true)

        await #expect(throws: StorageError.self) { try await store.moveLibrary(to: InMemoryStorageService()) }
        #expect(store.notes.values.contains { $0.title == "Viktigt" })
    }
}

@MainActor
struct SettingsDataLossTests {
    @Test func aSettingsFileFromANewerVersionIsNotReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NotesV-Tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let newer = #"{"version": 99, "myNames": "Ada", "ai": {"preset": "openAI", "baseURL": "https://api.openai.com/v1", "authStyle": "bearer", "modelChoice": {"latest": {}}}}"#
        try newer.write(to: SettingsFile.url(in: root), atomically: true, encoding: .utf8)

        let suite = "NotesV-Tests-\(UUID().uuidString)"
        let ai = AISettings(keychain: KeychainService(service: "se.consid.NotesV.tests-\(UUID().uuidString)"), defaultsSuiteName: suite)
        let profile = ProfileSettings(defaultsSuiteName: suite)
        let storage = StorageSettings(defaultRootURL: root, defaultsSuiteName: suite)
        let backup = SettingsBackup(aiSettings: ai, profile: profile, storage: storage)
        backup.folderDidChange()
        backup.writeNow()

        #expect(try String(contentsOf: SettingsFile.url(in: root), encoding: .utf8) == newer)
        #expect(backup.errorMessage != nil)
    }

    @Test func clearingTheKeyFieldDoesNotDeleteTheKey() throws {
        let keychain = KeychainService(service: "se.consid.NotesV.tests-\(UUID().uuidString)")
        let account = AIEndpointPreset.openAI.rawValue
        defer { try? keychain.setPassword(nil, for: account) }
        let settings = AISettings(keychain: keychain, defaultsSuiteName: "NotesV-Tests-\(UUID().uuidString)")

        settings.apiKey = "sk-test"
        settings.apiKey = ""
        #expect(try keychain.password(for: account) == "sk-test")
        #expect(settings.hasStoredKey)

        settings.removeAPIKey()
        #expect(try keychain.password(for: account) == nil)
        #expect(!settings.hasStoredKey)
    }
}

@MainActor
struct PasteDataLossTests {
    @Test func richTextWithoutTextIsNotPastedAsANote() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotesV-Tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let blank = NSAttributedString(string: " \n ")
        let rtf = try #require(blank.rtf(from: NSRange(location: 0, length: blank.length)))
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)

        #expect(RichPasteImporter.document(from: pasteboard) == nil)
    }
}
