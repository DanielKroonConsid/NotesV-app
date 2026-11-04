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
