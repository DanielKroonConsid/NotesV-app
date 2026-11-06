import Foundation
import Testing
@testable import NotesV

@MainActor
struct ActionItemTests {
    /// Wednesday 2026-11-04.
    private let meetingDate = DueDateParser.calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DueDateParser.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func checkbox(_ text: String, checked: Bool = false) -> Block {
        .listItem(ListItem(kind: .checklist, isChecked: checked, text: RichText(plain: text)))
    }

    private func protocolNote(_ blocks: [Block], actionItems: [ActionItem] = [], folder: String = NoteFolder.meetingProtocolsName, sentAt: Date? = nil) -> Note {
        Note(
            folderID: folder,
            meeting: MeetingDetails(title: "Sync", start: meetingDate, organizer: "Ada Ek", attendees: ["Bo Berg"]),
            sourceNoteID: UUID(),
            sentAt: sentAt,
            actionItems: actionItems,
            document: NoteDocument(blocks: [.paragraph(.title, "Protokoll")] + blocks)
        )
    }

    private func makeStore(_ notes: [Note]) async -> (NoteStore, InMemoryStorageService) {
        let storage = InMemoryStorageService()
        let store = NoteStore(storage: storage)
        await store.load()
        for note in notes { store.addProtocol(note) }
        // addProtocol files a note in Meeting Protocols; put it back where the test wants it.
        for note in notes where note.folderID != NoteFolder.meetingProtocolsName {
            store.moveNote(note.id, to: note.folderID)
        }
        return (store, storage)
    }

    // MARK: - Reading lines

    @Test(arguments: ["sv", "en"])
    func readsTheLinesTheFormatterWrites(language: String) {
        let minutes = MeetingProtocol(language: language, actionItems: [
            .init(task: "Skicka offert – utkast", owner: "Ada Ek", dueDate: "fredag, senast 12"),
            .init(task: "Boka lokal", owner: nil, dueDate: nil),
            .init(task: "Ring Bo", owner: "Bo Berg", dueDate: nil),
        ])
        let document = ProtocolFormatter.document(for: minutes, meeting: MeetingDetails(title: "Sync", start: meetingDate))
        let lines = document.checklistItems.map { ActionItemLine($0.item.text.plainText) }

        #expect(lines[0] == { var l = ActionItemLine("x"); l.task = "Skicka offert – utkast"; l.owner = "Ada Ek"; l.dueText = "fredag, senast 12"; return l }())
        #expect(lines[1].task == "Boka lokal")
        #expect(lines[1].owner == nil)
        #expect(lines[2].owner == "Bo Berg")
        #expect(lines[2].dueText == nil)
    }

    @Test func aLineWithoutSeparatorIsOnlyATask() {
        let line = ActionItemLine("Köp kaffe, gärna snart")
        #expect(line.task == "Köp kaffe, gärna snart")
        #expect(line.owner == nil)
        #expect(line.dueText == nil)
    }

    @Test func hyphensInsideWordsAreNotSeparators() {
        #expect(ActionItemLine("Följ upp e-post").task == "Följ upp e-post")
        #expect(ActionItemLine("Skriv rapport - Ada").owner == "Ada")
    }

    @Test func aDraftFillsInWhatItCanRead() {
        let draft = ActionItemDraft(noteID: UUID(), line: "Skicka offert – Daniel Kroon, 2026-11-20", meetingDate: meetingDate, myNames: ["Daniel Kroon"])
        #expect(draft.item.task == "Skicka offert")
        #expect(draft.item.isMine)
        #expect(draft.item.owner == nil)
        #expect(draft.item.dueDate == day(2026, 11, 20))
        #expect(draft.unreadDueText == nil)

        let unclear = ActionItemDraft(noteID: UUID(), line: "Skicka offert – Bo Berg, innan jul", meetingDate: meetingDate, myNames: ["Daniel Kroon"])
        #expect(!unclear.item.isMine)
        #expect(unclear.item.owner == "Bo Berg")
        #expect(unclear.item.dueDate == nil)
        #expect(unclear.unreadDueText == "innan jul")

        let dateOnly = ActionItemDraft(noteID: UUID(), line: "Skicka offert - fredag", meetingDate: meetingDate, myNames: [])
        #expect(dateOnly.item.owner == nil)
        #expect(dateOnly.item.dueDate == day(2026, 11, 6))
    }

    @Test func ownersMatchOnWholeWords() {
        #expect(ActionItemDraft.owner("Ada Ek och Bo", isOneOf: ["ada ek"]))
        #expect(ActionItemDraft.owner("Åsa Berg", isOneOf: ["Asa"]))
        #expect(!ActionItemDraft.owner("Adam Ek", isOneOf: ["Ada"]))
        #expect(!ActionItemDraft.owner("Ada", isOneOf: []))
    }

    // MARK: - Due dates

    @Test func readsDates() {
        func parse(_ text: String) -> Date? { DueDateParser.parse(text, relativeTo: meetingDate) }

        #expect(parse("2026-11-20") == day(2026, 11, 20))
        #expect(parse("20/11") == day(2026, 11, 20))
        #expect(parse("20/11 2027") == day(2027, 11, 20))
        #expect(parse("20 november") == day(2026, 11, 20))
        #expect(parse("20:e november") == day(2026, 11, 20))
        #expect(parse("Nov 20") == day(2026, 11, 20))
        #expect(parse("November 20, 2027") == day(2027, 11, 20))
        #expect(parse("senast 20 nov.") == day(2026, 11, 20))
        #expect(parse("fredag 20 november") == day(2026, 11, 20))
        #expect(parse("20 maj") == day(2027, 5, 20))
        #expect(parse("1/2") == day(2027, 2, 1))
    }

    @Test func readsRelativeDatesFromTheMeeting() {
        func parse(_ text: String) -> Date? { DueDateParser.parse(text, relativeTo: meetingDate) }

        #expect(parse("idag") == day(2026, 11, 4))
        #expect(parse("i morgon") == day(2026, 11, 5))
        #expect(parse("Tomorrow") == day(2026, 11, 5))
        #expect(parse("Fredag") == day(2026, 11, 6))
        #expect(parse("måndag") == day(2026, 11, 9))
        #expect(parse("onsdag") == day(2026, 11, 11))
        #expect(parse("nästa vecka") == day(2026, 11, 13))
        #expect(parse("next week") == day(2026, 11, 13))
    }

    @Test func aWeekCountsAsItsFriday() {
        func parse(_ text: String) -> Date? { DueDateParser.parse(text, relativeTo: meetingDate) }

        #expect(parse("v. 46") == day(2026, 11, 13))
        #expect(parse("v46") == day(2026, 11, 13))
        #expect(parse("vecka 46") == day(2026, 11, 13))
        #expect(parse("week 46") == day(2026, 11, 13))
        // Week 2 has passed in 2026, so it is the one in 2027.
        #expect(parse("v. 2") == day(2027, 1, 15))
    }

    @Test func aWeekAcrossTheNewYear() {
        let december = day(2026, 12, 30)
        #expect(DueDateParser.parse("v. 1", relativeTo: december) == day(2027, 1, 8))
        #expect(DueDateParser.parse("nästa vecka", relativeTo: december) == day(2027, 1, 8))
        #expect(DueDateParser.parse("3 januari", relativeTo: december) == day(2027, 1, 3))
    }

    @Test(arguments: ["innan jul", "snart", "Q4", "31/2", "13/13", "2026-13-01", "v. 60", "innan fredag", "", "20 smörgås"])
    func unclearDatesAreNotGuessed(text: String) {
        #expect(DueDateParser.parse(text, relativeTo: meetingDate) == nil)
    }

    // MARK: - Storage

    @Test func tasksSurviveARoundTrip() {
        let items = [
            ActionItem(source: "Citat \"här\": och\tkolon – Ada, v. 46", task: "Rad ett\nrad två: \"citat\"", owner: "Ada: Ek", dueDate: day(2026, 11, 20)),
            ActionItem(source: "Min rad", task: "Min rad", isMine: true, status: .done),
            ActionItem(source: "Bort", task: "Bort", status: .ignored),
        ]
        let note = protocolNote([checkbox("Min rad")], actionItems: items)

        let decoded = MarkdownCodec.decode(MarkdownCodec.encode(note))

        #expect(decoded.fields?.actionItems == items)
        #expect(decoded.fields?.meeting == note.meeting)
        #expect(decoded.fields?.sourceNoteID == note.sourceNoteID)
        #expect(decoded.document == note.document)
    }

    @Test func notesAndSubtasksSurviveARoundTrip() {
        let subtasks: [ActionItem.Subtask] = [
            .init(title: "Pris, \"offert\": klart [x]", isDone: true),
            .init(title: "Rad med \\ tecken\noch radbrytning"),
        ]
        let item = ActionItem(source: "Ett", task: "Ett", note: "Väntar på \"Bo\":\nring måndag, gärna #1", subtasks: subtasks)
        let note = protocolNote([checkbox("Ett")], actionItems: [item, ActionItem(source: "Två", task: "Två")])

        let decoded = MarkdownCodec.decode(MarkdownCodec.encode(note))

        #expect(decoded.fields?.actionItems == note.actionItems)
        #expect(decoded.document == note.document)
    }

    @Test func notesAndSubtasksAreOnlyInTheFrontMatter() {
        let item = ActionItem(source: "Ett", task: "Ett", note: "Hemlig notering", subtasks: [.init(title: "Hemligt steg")])
        let note = protocolNote([checkbox("Ett")], actionItems: [item])

        let text = MarkdownCodec.encode(note)
        let body = FrontMatter.split(text).body

        #expect(text.contains("note: \"Hemlig notering\""))
        #expect(text.contains("subtasks: [\"[ ] Hemligt steg\"]"))
        #expect(!body.contains("Hemlig"))
        #expect(!EmailFormatter.plainText(for: note.document).contains("Hemlig"))
    }

    @Test func tasksWithoutNotesOrSubtasksGetNoExtraLines() {
        let text = MarkdownCodec.encode(protocolNote([], actionItems: [ActionItem(source: "Ett", task: "Ett")]))
        #expect(!text.contains("note:"))
        #expect(!text.contains("subtasks:"))
    }

    @Test func aDamagedSubtaskIsLeftOut() {
        let text = """
        ---
        tasks:
          - source: "Rad"
            subtasks: ["utan ruta", "[X] Klar", "[ ] Öppen"]
            status: done
        ---
        Text
        """
        let item = MarkdownCodec.decode(text).fields?.actionItems.first
        #expect(item?.subtasks == [.init(title: "Klar", isDone: true), .init(title: "Öppen")])
        #expect(item?.status == .done)
    }

    @Test func emptyNotesAndSubtasksAreNotStored() async throws {
        let (store, _) = await makeStore([])
        var item = ActionItem(source: "Ett", task: "Ett", note: "  \n ", subtasks: [.init(title: " "), .init(title: "Steg")])
        store.addManualActionItem(item)
        let row = try #require(store.actionItemRows.first)
        #expect(row.item.note == nil)
        #expect(row.item.subtasks.map(\.title) == ["Steg"])

        item.note = " Notering \n"
        item.subtasks = []
        store.updateActionItem(row.id, to: item)
        #expect(store.actionItemRows.first?.item.note == "Notering")
        #expect(store.actionItemRows.first?.item.subtasks == [])
    }

    @Test func subtasksAreTickedOnTheirOwn() async throws {
        let task = ActionItem(source: "Ett", task: "Ett", subtasks: [.init(title: "A"), .init(title: "B")])
        let note = protocolNote([checkbox("Ett")], actionItems: [task])
        let (store, _) = await makeStore([note])
        let id = try #require(store.actionItemRows.first?.id)

        store.setSubtask(1, of: id, done: true)
        #expect(store.actionItemRows.first?.item.subtasks.map(\.isDone) == [false, true])
        #expect(store.actionItemRows.first?.isDone == false)
        #expect(store.notes[note.id]?.modified == note.modified)
        #expect(store.notes[note.id]?.document == note.document)

        store.setSubtask(1, of: id, done: false)
        #expect(store.actionItemRows.first?.item.subtasks.map(\.isDone) == [false, false])

        // A task can be completed with open subtasks, and an index out of range does nothing.
        store.setActionItem(id, done: true)
        store.setSubtask(9, of: id, done: true)
        #expect(store.actionItemRows.first?.isDone == true)
        #expect(store.actionItemRows.first?.item.subtasks.map(\.isDone) == [false, false])
    }

    @Test func tasksAreWrittenAsReadableYAML() {
        let note = protocolNote([], actionItems: [
            ActionItem(source: "Skicka – Ada", task: "Skicka", owner: "Ada", dueDate: day(2026, 11, 20)),
        ])
        let text = MarkdownCodec.encode(note)
        #expect(text.contains("""
        tasks:
          - source: "Skicka – Ada"
            task: "Skicka"
            owner: "Ada"
            mine: false
            due: 2026-11-20
            status: open
        """))
    }

    @Test func notesWithoutTasksDoNotGetTheField() {
        let text = MarkdownCodec.encode(protocolNote([]))
        #expect(!text.contains("tasks:"))
        #expect(MarkdownCodec.decode(text).fields?.actionItems == [])
    }

    @Test func aDamagedTaskEntryIsLeftOut() {
        let text = """
        ---
        id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
        tasks:
          - task: "Utan källa"
          - source: "Rad"
            status: okänd
            due: fredag
            mine: kanske
        pinned: true
        ---
        Text
        """
        let fields = MarkdownCodec.decode(text).fields
        #expect(fields?.actionItems == [ActionItem(source: "Rad", task: "Rad")])
        #expect(fields?.isPinned == true)
    }

    // MARK: - Finding new tasks

    @Test func findsOnlyUntickedUnhandledCheckboxesInProtocols() async {
        let handled = ActionItem(source: "Klar sen tidigare", task: "Klar sen tidigare")
        let ignored = ActionItem(source: "Ignorerad", task: "Ignorerad", status: .ignored)
        let note = protocolNote(
            [checkbox("Klar sen tidigare"), checkbox("Ignorerad"), checkbox("Ny"), checkbox("Bockad", checked: true), checkbox("  ")],
            actionItems: [handled, ignored]
        )
        let plainNote = Note(folderID: "Notes", document: NoteDocument(blocks: [checkbox("Anteckning")]))

        #expect(note.newActionItemLines() == ["Ny"])
        #expect(plainNote.newActionItemLines().isEmpty)

        let (store, _) = await makeStore([note])
        #expect(store.newActionItemCount == 1)
    }

    @Test func theSameLineTwiceCountsAsTwoTasks() {
        let note = protocolNote([checkbox("Samma"), checkbox("Samma")], actionItems: [ActionItem(source: "Samma", task: "Samma")])
        #expect(note.newActionItemLines() == ["Samma"])
    }

    @Test func addedAndIgnoredTasksAreNotSuggestedAgain() async throws {
        let note = protocolNote([checkbox("Ett – Ada"), checkbox("Två")])
        let (store, _) = await makeStore([note])

        let proposal = try #require(store.actionItemProposals(myNames: []).first)
        #expect(proposal.title == "Sync")
        #expect(proposal.people == ["Bo Berg", "Ada Ek"])
        store.addActionItems([proposal.drafts[0].item], to: note.id)
        store.ignoreActionItem(proposal.drafts[1].item, in: note.id)

        #expect(store.newActionItemCount == 0)
        #expect(store.actionItemRows.map(\.item.task) == ["Ett"])
        #expect(store.notes[note.id]?.modified == note.modified)

        // A new checkbox in the protocol is new.
        var document = try #require(store.notes[note.id]?.document)
        document = NoteDocument(blocks: document.blocks + [checkbox("Tre")])
        store.updateDocument(document, of: note.id)
        #expect(store.actionItemProposals(myNames: []).first?.drafts.map(\.item.task) == ["Tre"])
    }

    // MARK: - Done

    @Test func tickingFollowsBothWays() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ändrad text")])
        let (store, _) = await makeStore([note])
        let id = try #require(store.actionItemRows.first?.id)

        store.setActionItem(id, done: true)
        #expect(store.actionItemRows.first?.isDone == true)
        #expect(store.notes[note.id]?.document.checklistItems.first?.item.isChecked == true)
        #expect(MarkdownCodec.encode(try #require(store.notes[note.id])).contains("- [x] Ett"))
        #expect(MarkdownCodec.encode(try #require(store.notes[note.id])).contains("status: done"))

        // Unticking in the protocol reopens the task.
        store.updateDocument(NoteDocument(blocks: [checkbox("Ett")]), of: note.id)
        #expect(store.actionItemRows.first?.isDone == false)
    }

    @Test func aTaskWhoseLineIsGoneKeepsItsOwnStatus() async throws {
        let note = protocolNote([], actionItems: [ActionItem(source: "Borta", task: "Borta")])
        let (store, _) = await makeStore([note])
        let id = try #require(store.actionItemRows.first?.id)
        let document = store.notes[note.id]?.document

        store.setActionItem(id, done: true)

        #expect(store.actionItemRows.first?.isDone == true)
        #expect(store.notes[note.id]?.document == document)
    }

    @Test func changedLinesAreLeftAlone() {
        var document = NoteDocument(blocks: [checkbox("Ny text")])
        let wrongText = document.setChecked(true, block: 0, expectedText: "Gammal text")
        let wrongBlock = document.setChecked(true, block: 4, expectedText: "Ny text")
        #expect(!wrongText)
        #expect(!wrongBlock)
        #expect(document.checklistItems.first?.item.isChecked == false)
    }

    @Test func removingATaskKeepsItFromComingBack() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ett")])
        let (store, _) = await makeStore([note])
        store.removeActionItem(try #require(store.actionItemRows.first?.id))

        #expect(store.actionItemRows.isEmpty)
        #expect(store.newActionItemCount == 0)
        #expect(store.notes[note.id]?.document.checklistItems.count == 1)
    }

    // MARK: - Overview

    @Test func sentProtocolsAreCoveredAndDeletedOnesAreNot() async throws {
        let sent = protocolNote([checkbox("Skickad")], sentAt: .now)
        let deleted = protocolNote([checkbox("Raderad")], actionItems: [ActionItem(source: "Raderad", task: "Raderad")])
        let (store, _) = await makeStore([sent, deleted])

        #expect(store.newActionItemCount == 1)
        #expect(store.actionItemRows.map(\.item.task) == ["Raderad"])

        store.deleteNote(deleted.id)
        #expect(store.actionItemRows.isEmpty)

        store.moveNote(deleted.id, to: NoteFolder.meetingProtocolsName)
        #expect(store.actionItemRows.map(\.item.task) == ["Raderad"])
    }

    @Test func theViewIsInTheSidebarBeforeSent() async throws {
        let (store, _) = await makeStore([])
        let names = store.sidebarFolders.map(\.name)
        let index = try #require(names.firstIndex(of: NoteFolder.actionItems.name))
        #expect(names[index + 1] == NoteFolder.sent.name)
    }

    @Test func deletingTheShownProtocolClearsTheSelection() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ett")])
        let (store, _) = await makeStore([note])
        store.selectedFolderID = NoteFolder.actionItems.id
        store.selectedNoteID = note.id

        store.deleteNote(note.id)

        #expect(store.selectedNoteID == nil)
        #expect(store.selectedFolderID == NoteFolder.actionItems.id)
    }

    private func row(_ task: String, owner: String? = nil, mine: Bool = false, due: Date? = nil, done: Bool = false, noteID: UUID = UUID(), meeting: String = "Sync", meetingDate: Date? = nil, index: Int = 0) -> ActionItemRow {
        ActionItemRow(
            id: .init(noteID: noteID, index: index),
            item: ActionItem(source: task, task: task, owner: owner, isMine: mine, dueDate: due),
            isDone: done,
            meetingTitle: meeting,
            meetingDate: meetingDate ?? self.meetingDate
        )
    }

    @Test func filtersMineAndOthers() {
        let rows = [row("Min", mine: true), row("Annans", owner: "Bo"), row("Ingen")]
        func tasks(_ filter: ActionItemOverview.Filter) -> Set<String> {
            Set(ActionItemOverview.sections(of: rows, filter: filter, sort: .dueDate, showsDone: false).flatMap(\.rows).map(\.item.task))
        }
        #expect(tasks(.mine) == ["Min"])
        #expect(tasks(.others) == ["Annans", "Ingen"])
        #expect(tasks(.all) == ["Min", "Annans", "Ingen"])
    }

    @Test func sortsByDueDateInGroups() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let now = meetingDate
        let rows = [
            row("Utan"),
            row("Senare", due: day(2026, 11, 20)),
            row("Veckan", due: day(2026, 11, 6)),
            row("Idag", due: day(2026, 11, 4)),
            row("Sen", due: day(2026, 11, 2)),
            row("Senast", due: day(2026, 10, 2)),
            row("Klar", due: day(2026, 11, 2), done: true),
        ]
        let hidden = ActionItemOverview.sections(of: rows, filter: .all, sort: .dueDate, showsDone: false, now: now, calendar: calendar)
        #expect(hidden.map(\.id) == [.overdue, .today, .thisWeek, .later, .noDate])
        #expect(hidden[0].rows.map(\.item.task) == ["Senast", "Sen"])

        let shown = ActionItemOverview.sections(of: rows, filter: .all, sort: .dueDate, showsDone: true, now: now, calendar: calendar)
        #expect(shown.last?.id == .done)
        #expect(shown.last?.rows.map(\.item.task) == ["Klar"])
    }

    @Test(arguments: ActionItemOverview.Sort.allCases)
    func completedTasksAreTogetherLastInEverySort(sort: ActionItemOverview.Sort) {
        let rows = [row("Klar", owner: "Bo", done: true), row("Öppen", owner: "Bo")]

        let shown = ActionItemOverview.sections(of: rows, filter: .all, sort: sort, showsDone: true)
        #expect(shown.map { $0.rows.map(\.item.task) } == [["Öppen"], ["Klar"]])
        #expect(shown.last?.id == .done)

        let hidden = ActionItemOverview.sections(of: rows, filter: .all, sort: sort, showsDone: false)
        #expect(hidden.flatMap(\.rows).map(\.item.task) == ["Öppen"])
    }

    @Test func aCompletedTaskCanBeReopened() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ett")])
        let (store, _) = await makeStore([note])
        let id = try #require(store.actionItemRows.first?.id)

        store.setActionItem(id, done: true)
        store.setActionItem(id, done: false)

        #expect(store.actionItemRows.first?.isDone == false)
        #expect(store.notes[note.id]?.actionItems.first?.status == .open)
        #expect(store.notes[note.id]?.document.checklistItems.first?.item.isChecked == false)
    }

    // MARK: - Manual tasks

    @Test func manualTasksAreKeptOutsideProtocolsAndNoteLists() async throws {
        let (store, _) = await makeStore([])
        var task = ActionItem(source: "Ring Bo", task: "Ring Bo", isMine: true, dueDate: day(2026, 11, 20))
        store.addManualActionItem(task)
        task.source = "Boka lokal"
        task.task = "Boka lokal"
        store.addManualActionItem(task)

        #expect(store.actionItemRows.map(\.item.task) == ["Ring Bo", "Boka lokal"])
        #expect(store.actionItemRows.filter(\.isManual).count == 2)
        #expect(store.newActionItemCount == 0)
        #expect(!store.sidebarFolders.map(\.name).contains(NoteFolder.manualTasksName))
        store.searchText = "Tasks"
        #expect(store.visibleNotes.isEmpty)
    }

    private func isDone(_ id: ActionItemRow.ID, in store: NoteStore) -> Bool? {
        store.actionItemRows.first { $0.id == id }?.isDone
    }

    @Test func aManualTaskCanBeCompletedReopenedAndRemoved() async throws {
        let (store, _) = await makeStore([])
        store.addManualActionItem(ActionItem(source: "Ett", task: "Ett"))
        store.addManualActionItem(ActionItem(source: "Två", task: "Två"))
        let first = try #require(store.actionItemRows.first { $0.item.task == "Ett" }?.id)

        store.setActionItem(first, done: true)
        #expect(isDone(first, in: store) == true)
        store.setActionItem(first, done: false)
        #expect(isDone(first, in: store) == false)

        store.removeActionItem(first)
        #expect(store.actionItemRows.map(\.item.task) == ["Två"])
        #expect(store.notes[Note.manualTaskListID]?.actionItems.count == 1)
    }

    @Test func manualTasksSurviveARestartInTheirOwnFolder() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesV-Tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        await store.load()
        store.addManualActionItem(ActionItem(source: "Ring Bo", task: "Ring Bo", owner: "Bo", status: .done))
        await store.prepareForTermination()

        let restarted = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        await restarted.load()

        #expect(restarted.actionItemRows.map(\.item.owner) == ["Bo"])
        #expect(restarted.actionItemRows.first?.isDone == true)
        let path = rootURL.appending(path: "Manual Tasks/Tasks.md").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func sortsByMeetingAndOwner() {
        let older = UUID()
        let newer = UUID()
        let rows = [
            row("A", owner: "Örjan", noteID: older, meeting: "Gammalt", meetingDate: day(2026, 1, 1)),
            row("B", owner: "Ada", noteID: newer, meeting: "Nytt", meetingDate: day(2026, 6, 1)),
            row("C", mine: true, noteID: newer, meeting: "Nytt", meetingDate: day(2026, 6, 1), index: 1),
            row("D", noteID: older, meeting: "Gammalt", meetingDate: day(2026, 1, 1), index: 1),
        ]
        let meetings = ActionItemOverview.sections(of: rows, filter: .all, sort: .meeting, showsDone: false)
        #expect(meetings.map(\.title) == ["Nytt", "Gammalt"])

        let owners = ActionItemOverview.sections(of: rows, filter: .all, sort: .owner, showsDone: false)
        #expect(owners.map(\.id) == [.me, .owner("Ada"), .owner("Örjan"), .noOwner])
    }

    @Test func searchFindsNotesAndSubtasks() {
        var noted = row("Med notering")
        noted = ActionItemRow(
            id: noted.id,
            item: ActionItem(source: "x", task: "Med notering", note: "Väntar på Bo", subtasks: [.init(title: "Hämta pris")]),
            isDone: false, meetingTitle: "Sync", meetingDate: meetingDate
        )
        #expect(noted.matches(searchText: "väntar"))
        #expect(noted.matches(searchText: "hämta"))
        #expect(!noted.matches(searchText: "offert"))
    }

    @Test func searchesTaskOwnerAndMeeting() {
        let rows = [row("Skicka offert", owner: "Åsa"), row("Boka", meeting: "Styrelsemöte")]
        func tasks(_ query: String) -> [String] {
            ActionItemOverview.sections(of: rows, filter: .all, sort: .dueDate, showsDone: false, searchText: query).flatMap(\.rows).map(\.item.task)
        }
        #expect(tasks("offert") == ["Skicka offert"])
        #expect(tasks("asa") == ["Skicka offert"])
        #expect(tasks("styrelse") == ["Boka"])
    }
}
