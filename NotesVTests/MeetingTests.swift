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

    /// Adds a protocol to the Meeting Protocols folder, attached to a new note.
    private func addProtocol(to store: NoteStore) throws -> UUID {
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        let minutes = Note(folderID: "Notes", sourceNoteID: noteID, document: NoteDocument(blocks: [.paragraph(.title, "Protokoll")]))
        store.addProtocol(minutes)
        return minutes.id
    }

    /// Adds a note with a meeting, or without one if `start` is `nil`.
    private func addNote(_ title: String, start: Date? = nil, to store: NoteStore) throws -> UUID {
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, RichText(plain: title))]), of: noteID)
        if let start {
            store.updateMeeting(MeetingDetails(title: title, start: start), of: noteID)
        }
        return noteID
    }

    @Test func marksAProtocolAsSent() async throws {
        let (store, storage) = await makeStore()
        let protocolID = try addProtocol(to: store)
        let modified = store.notes[protocolID]?.modified

        store.toggleSent(protocolID)
        #expect(store.notes[protocolID]?.sentAt != nil)
        #expect(store.notes[protocolID]?.modified == modified)
        let saved = try await waitForSave(of: protocolID, in: storage)
        #expect(saved?.sentAt != nil)

        store.toggleSent(protocolID)
        #expect(store.notes[protocolID]?.sentAt == nil)
    }

    @Test func ordinaryNotesCantBeMarkedAsSent() async throws {
        let (store, _) = await makeStore()
        let noteID = try addNote("Sync", to: store)

        store.toggleSent(noteID)
        #expect(store.notes[noteID]?.sentAt == nil)
        #expect(store.selectedNoteID == noteID)
    }

    @Test func protocolsAreRecognizedWithoutALink() {
        #expect(Note(folderID: NoteFolder.meetingProtocolsName).isMeetingProtocol)
        #expect(Note(folderID: "Notes", sourceNoteID: UUID()).isMeetingProtocol)
        #expect(!Note(folderID: "Notes").isMeetingProtocol)
    }

    @Test func aNoteMarkedByAnEarlierVersionIsBackInItsFolder() async throws {
        let (store, storage) = await makeStore()
        let note = Note(folderID: NoteFolder.defaultName, sentAt: .now, document: NoteDocument(blocks: [.paragraph(.title, "Sync")]))
        try await storage.save(note)
        await store.load()

        #expect(store.visibleNotes.map(\.id) == [note.id])
        #expect(store.noteCount(in: NoteFolder.sent.id) == 0)
    }

    @Test func sentProtocolsMoveToTheSentView() async throws {
        let (store, _) = await makeStore()
        let first = try addProtocol(to: store)
        let second = try addProtocol(to: store)
        store.selectedFolderID = NoteFolder.meetingProtocolsName
        store.selectedNoteID = second

        store.toggleSent(second)
        #expect(store.visibleNotes.map(\.id) == [first])
        #expect(store.selectedNoteID == first)
        #expect(store.noteCount(in: NoteFolder.meetingProtocolsName) == 1)
        #expect(store.noteCount(in: NoteFolder.sent.id) == 1)
        // The file stays in its folder.
        #expect(store.notes[second]?.folderID == NoteFolder.meetingProtocolsName)

        store.selectedFolderID = NoteFolder.sent.id
        #expect(store.visibleNotes.map(\.id) == [second])

        store.searchText = "Protokoll"
        #expect(store.visibleNotes.count == 2)
        store.searchText = ""

        store.toggleSent(second)
        #expect(store.visibleNotes.isEmpty)
        store.selectedFolderID = NoteFolder.meetingProtocolsName
        #expect(store.visibleNotes.count == 2)
    }

    @Test func aDeletedSentProtocolIsInRecentlyDeleted() async throws {
        let (store, _) = await makeStore()
        let protocolID = try addProtocol(to: store)
        store.toggleSent(protocolID)
        store.deleteNote(protocolID)

        #expect(store.noteCount(in: NoteFolder.sent.id) == 0)
        #expect(store.noteCount(in: NoteFolder.recentlyDeletedName) == 1)
    }

    @Test func notesAreGroupedByMeetingDay() async throws {
        let (store, _) = await makeStore()
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9))!
        let earlierDay = calendar.date(byAdding: .day, value: -2, to: day)!
        let older = try addNote("Older", start: earlierDay, to: store)
        let morning = try addNote("Morning", start: day, to: store)
        let afternoon = try addNote("Afternoon", start: day.addingTimeInterval(5 * 3600), to: store)
        let plain = try addNote("Plain", to: store)

        #expect(store.noteSections.map(\.id) == [
            .noMeeting, .meetingDay(calendar.startOfDay(for: day)), .meetingDay(calendar.startOfDay(for: earlierDay)),
        ])
        #expect(store.noteSections.map { $0.notes.map(\.id) } == [[plain], [afternoon, morning], [older]])
    }

    @Test func selectionFollowsTheMeetingOrder() async throws {
        let (store, _) = await makeStore()
        let day = Date(timeIntervalSince1970: 1_792_486_800)
        let latest = try addNote("Latest", start: day, to: store)
        let earliest = try addNote("Earliest", start: day.addingTimeInterval(-7 * 86_400), to: store)
        let middle = try addNote("Middle", start: day.addingTimeInterval(-86_400), to: store)

        store.selectedNoteID = latest
        store.deleteNote(latest)
        #expect(store.selectedNoteID == middle)
        store.deleteNote(middle)
        #expect(store.selectedNoteID == earliest)
    }

    @Test func pinnedNotesStayOnTopOfTheMeetingGroups() async throws {
        let (store, _) = await makeStore()
        let pinned = try addNote("Pinned", to: store)
        let plain = try addNote("Plain", to: store)
        store.togglePin(pinned)

        #expect(store.noteSections.map(\.id) == [.pinned, .noMeeting])
        #expect(store.noteSections.map { $0.notes.map(\.id) } == [[pinned], [plain]])
    }

    @Test func onlyNoteFoldersAreGroupedByMeeting() async throws {
        let (store, _) = await makeStore()
        _ = try addNote("Sync", to: store)
        _ = try addProtocol(to: store)

        store.searchText = "Sync"
        #expect(!store.noteSections.contains { $0.id == .noMeeting })
        store.searchText = ""

        store.selectedFolderID = NoteFolder.meetingProtocolsName
        #expect(!store.noteSections.contains { $0.id == .noMeeting })
    }

    private let invited = MeetingDetails(
        title: "Sync", start: Date(timeIntervalSince1970: 1_792_486_800),
        organizer: "Ada Ek", attendees: ["Ada Ek", "Bo Berg", "Cia Lund"]
    )

    @Test func attendanceCoversEveryoneMentioned() {
        let minutes = MeetingProtocol(language: "sv", attendeesPresent: ["Bo Berg", "Gäst"], attendeesAbsent: ["Dan Ås"])
        #expect(minutes.attendanceCandidates(for: invited) == ["Ada Ek", "Bo Berg", "Cia Lund", "Gäst", "Dan Ås"])
    }

    @Test func anyoneLeftOutCountsAsAbsent() {
        var minutes = MeetingProtocol(language: "sv", attendeesPresent: ["Bo Berg"], attendeesAbsent: ["Bo Berg"])
        minutes.normalizeAttendance(for: invited)
        #expect(minutes.attendeesPresent == ["Bo Berg"])
        #expect(minutes.attendeesAbsent == ["Ada Ek", "Cia Lund"])
    }

    @Test func tickingMovesAPersonBetweenTheLists() {
        var minutes = MeetingProtocol(language: "sv", attendeesPresent: ["Bo Berg"], attendeesAbsent: ["Cia Lund"])

        minutes.setAttended(false, name: "Bo Berg")
        #expect(minutes.attendeesPresent.isEmpty)
        #expect(minutes.attendeesAbsent == ["Cia Lund", "Bo Berg"])

        minutes.setAttended(true, name: "Cia Lund")
        #expect(minutes.attendeesPresent == ["Cia Lund"])
        #expect(minutes.attendeesAbsent == ["Bo Berg"])
    }

    @Test func aReviewIsNeededForPeopleOrActionItems() {
        let alone = MeetingDetails(title: "Sync", start: .now)
        #expect(MeetingProtocol(language: "sv").needsReview(for: invited))
        #expect(MeetingProtocol(language: "sv", actionItems: [.init(task: "Ring")]).needsReview(for: alone))
        #expect(!MeetingProtocol(language: "sv").needsReview(for: alone))
    }

    @Test func unmarkedPeopleAppearUnderAbsentInTheProtocol() throws {
        var minutes = MeetingProtocol(language: "sv", attendeesPresent: ["Ada Ek", "Bo Berg", "Cia Lund"])
        minutes.setAttended(false, name: "Cia Lund")
        let text = ProtocolFormatter.document(for: minutes, meeting: invited).plainText

        let absent = try #require(text.range(of: "Frånvarande"))
        let cia = try #require(text.range(of: "Cia Lund"))
        #expect(absent.lowerBound < cia.lowerBound)
    }

    @Test func theSentViewComesBeforeRecentlyDeleted() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        store.deleteNote(noteID)

        #expect(store.sidebarFolders.map(\.name) == [NoteFolder.defaultName, NoteFolder.sent.name, NoteFolder.recentlyDeletedName])
    }

    @Test func onlyUserFoldersAreSubfolders() {
        #expect(NoteFolder(name: "Projekt").isSubfolder)
        #expect(!NoteFolder(name: NoteFolder.defaultName).isSubfolder)
        #expect(!NoteFolder(name: NoteFolder.meetingProtocolsName).isSubfolder)
        #expect(!NoteFolder(name: NoteFolder.recentlyDeletedName).isSubfolder)
        #expect(!NoteFolder.sent.isSubfolder)
    }

    @Test func revealFindsASentProtocol() async throws {
        let (store, _) = await makeStore()
        let protocolID = try addProtocol(to: store)
        store.toggleSent(protocolID)

        store.reveal(protocolID)
        #expect(store.selectedFolderID == NoteFolder.sent.id)
        #expect(store.selectedNoteID == protocolID)
    }

    @Test func countsUnsentProtocols() async throws {
        let (store, _) = await makeStore()
        store.createNote()
        let noteID = try #require(store.selectedNoteID)
        store.updateDocument(NoteDocument(blocks: [.paragraph(.title, "Sync")]), of: noteID)
        let text = NoteDocument(blocks: [.paragraph(.title, "Protokoll")])
        let first = Note(folderID: "Notes", sourceNoteID: noteID, document: text)
        let second = Note(folderID: "Notes", sourceNoteID: noteID, document: text)
        store.addProtocol(first)
        store.addProtocol(second)

        #expect(store.unsentProtocolCount(in: NoteFolder.meetingProtocolsName) == 2)
        // Ordinary notes don't count.
        #expect(store.unsentProtocolCount(in: NoteFolder.defaultName) == 0)

        store.toggleSent(first.id)
        #expect(store.unsentProtocolCount(in: NoteFolder.meetingProtocolsName) == 1)
        #expect(store.unsentProtocolCount(in: NoteFolder.sent.id) == 0)

        store.deleteNote(second.id)
        #expect(store.unsentProtocolCount(in: NoteFolder.meetingProtocolsName) == 0)
        #expect(store.unsentProtocolCount(in: NoteFolder.recentlyDeletedName) == 0)
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
