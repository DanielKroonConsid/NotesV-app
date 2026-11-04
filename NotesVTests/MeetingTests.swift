import Foundation
import Testing
@testable import NotesV

@MainActor
struct MeetingTests {
    private let meeting = MeetingDetails(title: "Sync", start: Date(timeIntervalSince1970: 1_792_486_800))

    private func makeStore() async -> (NoteStore, InMemoryStorageService) {
        let storage = InMemoryStorageService()
        let store = NoteStore(storage: storage)
        await store.load()
        return (store, storage)
    }

    private func waitForSave(of noteID: UUID, in storage: InMemoryStorageService) async throws -> Note? {
        for _ in 0..<40 {
            if let note = await storage.savedNotes[noteID] { return note }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test func aNoteWithOnlyAMeetingIsKeptAndSaved() async throws {
        let (store, storage) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)

        store.updateMeeting(meeting, of: noteID)
        store.createNote()

        #expect(store.notes[noteID]?.meeting == meeting)
        let saved = try await waitForSave(of: noteID, in: storage)
        #expect(saved?.meeting == meeting)
    }

    @Test func anEmptyNoteIsStillDiscarded() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)

        store.updateMeeting(MeetingDetails(title: "", start: .now), of: noteID)
        store.createNote()

        #expect(store.notes[noteID] == nil)
    }

    @Test func importsAFileIntoANote() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ics")
        defer { try? FileManager.default.removeItem(at: url) }
        try "BEGIN:VEVENT\r\nSUMMARY:Sync\r\nDTSTART:20261020T090000Z\r\nRRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n"
            .write(to: url, atomically: true, encoding: .utf8)

        let model = MeetingImportModel()
        model.importFile(at: url, into: noteID, store: store)

        #expect(store.notes[noteID]?.meeting == meeting)
        #expect(model.warnings.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test func letsTheUserChooseWhenAFileHasSeveralMeetings() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ics")
        defer { try? FileManager.default.removeItem(at: url) }
        let event = "BEGIN:VEVENT\r\nSUMMARY:Sync\r\nDTSTART:20261020T090000Z\r\nEND:VEVENT\r\n"
        try (event + event.replacingOccurrences(of: "Sync", with: "Other")).write(to: url, atomically: true, encoding: .utf8)

        let model = MeetingImportModel()
        model.importFile(at: url, into: noteID, store: store)
        #expect(model.eventChoices.count == 2)
        #expect(store.notes[noteID]?.meeting == nil)

        model.apply(model.eventChoices[0], to: noteID, store: store)
        #expect(model.eventChoices.isEmpty)
        #expect(store.notes[noteID]?.meeting == meeting)
    }

    @Test func reportsFilesThatCantBeRead() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)

        let model = MeetingImportModel()
        model.importFile(at: URL(filePath: "/nonexistent/meeting.ics"), into: noteID, store: store)

        #expect(model.errorMessage != nil)
        #expect(store.notes[noteID]?.meeting == nil)
    }

    @Test func protocolsAreAttachedToTheirNote() async throws {
        let (store, storage) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)

        let protocolNote = Note(folderID: "Notes", meeting: meeting, sourceNoteID: noteID, document: NoteDocument(blocks: [.paragraph(.title, "Protokoll")]))
        store.addProtocol(protocolNote)

        // It lands in its own folder, and the user stays on their note.
        #expect(store.selectedNoteID == noteID)
        #expect(store.notes[protocolNote.id]?.folderID == NoteFolder.meetingProtocolsName)
        #expect(store.folders.map(\.name) == [NoteFolder.defaultName, NoteFolder.meetingProtocolsName])
        #expect(store.attachments(of: noteID).map(\.id) == [protocolNote.id])
        let saved = try await waitForSave(of: protocolNote.id, in: storage)
        #expect(saved?.sourceNoteID == noteID)

        store.deleteNote(protocolNote.id)
        #expect(store.attachments(of: noteID).isEmpty)
    }

    @Test func revealsANoteInItsFolder() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        let protocolNote = Note(folderID: "Notes", sourceNoteID: noteID, document: NoteDocument(blocks: [.paragraph(.title, "Protokoll")]))
        store.addProtocol(protocolNote)

        store.reveal(protocolNote.id)
        #expect(store.selectedFolderID == NoteFolder.meetingProtocolsName)
        #expect(store.selectedNoteID == protocolNote.id)

        store.reveal(noteID)
        #expect(store.selectedFolderID == NoteFolder.defaultName)
        #expect(store.selectedNoteID == noteID)
    }

    @Test func theReviewedProtocolIsTheOneCreated() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateMeeting(meeting, of: noteID)

        let model = ProtocolGenerationModel()
        model.sourceNoteID = noteID
        model.pendingMinutes = MeetingProtocol(language: "en", actionItems: [.init(task: "Write", owner: nil, dueDate: nil)])
        model.pendingMinutes?.actionItems[0].owner = "Bo"
        model.createProtocol(store: store)

        let attachment = try #require(store.attachments(of: noteID).first)
        #expect(attachment.document.blocks.last == .listItem(ListItem(kind: .checklist, text: "Write – Bo")))
        #expect(model.createdProtocolID == attachment.id)
        #expect(model.pendingMinutes == nil)
        #expect(model.sourceNoteID == nil)
    }

    @Test func marksANoteAsSent() async throws {
        let (store, storage) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        let modified = store.notes[noteID]?.modified

        store.toggleSent(noteID)
        #expect(store.notes[noteID]?.sentAt != nil)
        #expect(store.notes[noteID]?.modified == modified)
        let saved = try await waitForSave(of: noteID, in: storage)
        #expect(saved?.sentAt != nil)

        store.toggleSent(noteID)
        #expect(store.notes[noteID]?.sentAt == nil)
    }

    @Test func sentNotesMoveToTheSentView() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let first = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "First")]), of: first)
        store.createNote()
        let second = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Second")]), of: second)

        store.toggleSent(second)
        #expect(store.visibleNotes.map(\.id) == [first])
        #expect(store.selectedNoteID == first)
        #expect(store.noteCount(in: NoteFolder.defaultName) == 1)
        #expect(store.noteCount(in: NoteFolder.sent.id) == 1)
        // The file stays in its folder.
        #expect(store.notes[second]?.folderID == NoteFolder.defaultName)

        store.selectedFolderID = NoteFolder.sent.id
        #expect(store.visibleNotes.map(\.id) == [second])

        store.searchText = "Second"
        #expect(store.visibleNotes.map(\.id) == [second])
        store.searchText = ""

        store.toggleSent(second)
        #expect(store.visibleNotes.isEmpty)
        store.selectedFolderID = NoteFolder.defaultName
        #expect(store.visibleNotes.count == 2)
    }

    @Test func aDeletedSentNoteIsInRecentlyDeleted() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        store.toggleSent(noteID)
        store.deleteNote(noteID)

        #expect(store.noteCount(in: NoteFolder.sent.id) == 0)
        #expect(store.noteCount(in: NoteFolder.recentlyDeletedName) == 1)
    }

    @Test func theSentViewComesBeforeRecentlyDeleted() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        store.deleteNote(noteID)

        #expect(store.sidebarFolders.map(\.name) == [NoteFolder.defaultName, NoteFolder.sent.name, NoteFolder.recentlyDeletedName])
    }

    @Test func revealFindsASentNote() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        store.toggleSent(noteID)

        store.reveal(noteID)
        #expect(store.selectedFolderID == NoteFolder.sent.id)
        #expect(store.selectedNoteID == noteID)
    }

    @Test func protocolsAreNotMadeFromProtocols() {
        let text = NoteDocument(blocks: [.paragraph(.body, "Text")])
        #expect(Note(folderID: "Notes", document: text).canGenerateProtocol)
        #expect(!Note(folderID: "Notes", sourceNoteID: UUID(), document: text).canGenerateProtocol)
        #expect(!Note(folderID: "Notes").canGenerateProtocol)
    }

    @Test func protocolNeedsAMeetingTitle() {
        let model = ProtocolGenerationModel()
        model.requestProtocol(for: Note(folderID: "Notes"))
        #expect(model.isMeetingFormPresented)
        #expect(model.sourceNoteID == nil)

        let note = Note(folderID: "Notes", meeting: meeting)
        model.requestProtocol(for: note)
        #expect(model.sourceNoteID == note.id)
    }
}
