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
        for note in notes {
            var protocolNote = note
            protocolNote.actionItems = []
            store.addProtocol(protocolNote)
            store.addActionItems(note.actionItems, to: note.id)
        }
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

        #expect(note.newActionItemLines(tasks: [handled, ignored]) == ["Ny"])
        #expect(plainNote.newActionItemLines(tasks: []).isEmpty)

        let (store, _) = await makeStore([note])
        #expect(store.newActionItemCount == 1)
    }

    @Test func theSameLineTwiceCountsAsTwoTasks() {
        let note = protocolNote([checkbox("Samma"), checkbox("Samma")], actionItems: [ActionItem(source: "Samma", task: "Samma")])
        #expect(note.newActionItemLines(tasks: note.actionItems) == ["Samma"])
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
        #expect(MarkdownCodec.encode(try #require(store.notes[id])).contains("status: done"))

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
            id: UUID(),
            item: ActionItem(source: task, task: task, owner: owner, isMine: mine, dueDate: due),
            isDone: done,
            meetingTitle: meeting,
            meetingDate: meetingDate ?? self.meetingDate,
            protocolID: noteID
        )
    }

    @Test func filtersMineAndOthers() {
        let rows = [row("Min", mine: true), row("Annans", owner: "Bo"), row("Ingen")]
        func tasks(_ filter: ActionItemOverview.Filter) -> Set<String> {
            Set(ActionItemOverview.sections(of: rows, filter: filter, sort: .dueDate).flatMap(\.rows).map(\.item.task))
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
        let sections = ActionItemOverview.sections(of: rows, filter: .all, sort: .dueDate, now: now, calendar: calendar)
        #expect(sections.map(\.id) == [.overdue, .today, .thisWeek, .later, .noDate])
        #expect(sections[0].rows.map(\.item.task) == ["Senast", "Sen"])
    }

    @Test(arguments: ActionItemOverview.Sort.allCases)
    func completedTasksAreOnlyInTheirTab(sort: ActionItemOverview.Sort) {
        let rows = [row("Klar", owner: "Bo", done: true), row("Öppen", owner: "Bo")]
        func tasks(_ filter: ActionItemOverview.Filter) -> [String] {
            ActionItemOverview.sections(of: rows, filter: filter, sort: sort).flatMap(\.rows).map(\.item.task)
        }
        #expect(tasks(.completed) == ["Klar"])
        #expect(tasks(.all) == ["Öppen"])
        #expect(tasks(.others) == ["Öppen"])
    }

    private func backlogRow(_ task: String, mine: Bool = false, done: Bool = false) -> ActionItemRow {
        ActionItemRow(
            id: UUID(),
            item: ActionItem(source: task, task: task, isMine: mine, isBacklog: true),
            isDone: done, meetingTitle: "Sync", meetingDate: meetingDate
        )
    }

    @Test(arguments: ActionItemOverview.Sort.allCases)
    func backlogTasksAreOnlyInTheirTab(sort: ActionItemOverview.Sort) {
        let rows = [backlogRow("Min senare", mine: true), backlogRow("Annans senare"), backlogRow("Klar senare", done: true), row("Nu", mine: true)]
        func tasks(_ filter: ActionItemOverview.Filter) -> Set<String> {
            Set(ActionItemOverview.sections(of: rows, filter: filter, sort: sort).flatMap(\.rows).map(\.item.task))
        }
        #expect(tasks(.backlog) == ["Min senare", "Annans senare"])
        #expect(tasks(.mine) == ["Nu"])
        #expect(tasks(.others).isEmpty)
        #expect(tasks(.all) == ["Nu"])
        #expect(tasks(.completed) == ["Klar senare"])
    }

    @Test func backlogAndCompletedAreNotGroupedByDate() {
        let rows = [backlogRow("Senare"), row("Klar", due: day(2020, 1, 1), done: true)]
        #expect(ActionItemOverview.sections(of: rows, filter: .backlog, sort: .dueDate).map(\.id) == [.backlog])
        #expect(ActionItemOverview.sections(of: rows, filter: .completed, sort: .dueDate).map(\.id) == [.done])
    }

    @Test func movingToTheBacklogRemovesTheDueDate() async throws {
        let (store, _) = await makeStore([])
        store.addManualActionItem(ActionItem(source: "Ett", task: "Ett", dueDate: day(2026, 11, 20)))
        let id = try #require(store.actionItemRows.first?.id)

        store.setActionItem(id, inBacklog: true)
        #expect(store.actionItemRows.first?.item.isBacklog == true)
        #expect(store.actionItemRows.first?.item.dueDate == nil)

        store.setActionItem(id, inBacklog: false)
        #expect(store.actionItemRows.first?.item.isBacklog == false)
    }

    @Test func aReopenedTaskReturnsToTheBacklog() async throws {
        let (store, _) = await makeStore([])
        store.addManualActionItem(ActionItem(source: "Ett", task: "Ett", isBacklog: true))
        let id = try #require(store.actionItemRows.first?.id)

        store.setActionItem(id, done: true)
        #expect(ActionItemOverview.sections(of: store.actionItemRows, filter: .backlog, sort: .dueDate).isEmpty)
        store.setActionItem(id, done: false)
        #expect(ActionItemOverview.sections(of: store.actionItemRows, filter: .backlog, sort: .dueDate).count == 1)
    }

    @Test func theBacklogSurvivesARoundTrip() {
        let items = [ActionItem(source: "Ett", task: "Ett", isBacklog: true), ActionItem(source: "Två", task: "Två")]
        let text = MarkdownCodec.encode(protocolNote([], actionItems: items))
        #expect(text.components(separatedBy: "backlog: true").count == 2)
        #expect(MarkdownCodec.decode(text).fields?.actionItems == items)
    }

    @Test func aCompletedTaskCanBeReopened() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ett")])
        let (store, _) = await makeStore([note])
        let id = try #require(store.actionItemRows.first?.id)

        store.setActionItem(id, done: true)
        store.setActionItem(id, done: false)

        #expect(store.actionItemRows.first?.isDone == false)
        #expect(store.notes[id]?.task?.status == .open)
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

        #expect(Set(store.actionItemRows.map(\.item.task)) == ["Ring Bo", "Boka lokal"])
        #expect(store.actionItemRows.filter(\.isManual).count == 2)
        #expect(store.newActionItemCount == 0)
        #expect(!store.sidebarFolders.map(\.name).contains(NoteFolder.tasksName))
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
        #expect(store.notes[first] == nil)
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
        let path = rootURL.appending(path: "Tasks/Ring Bo.md").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Task files

    @Test func aTaskFileIsReadableMarkdown() {
        let item = ActionItem(
            source: "Skicka – Ada", task: "Skicka *offert*", owner: "Ada", dueDate: day(2026, 11, 20),
            note: "Väntar på Bo.\nRing på måndag.", subtasks: [.init(title: "Hämta pris", isDone: true), .init(title: "Skriv")],
            protocolID: UUID(uuidString: "7B1C2D3E-1111-4222-8333-944455566677")
        )
        let text = MarkdownCodec.encode(Note.taskFile(item))

        #expect(text.contains("""
        task:
          protocol: 7B1C2D3E-1111-4222-8333-944455566677
          source: "Skicka – Ada"
          owner: "Ada"
          mine: false
          due: 2026-11-20
          status: open
        ---
        """))
        #expect(text.contains("- [x] Hämta pris"))
        #expect(!text.contains("subtasks:"))

        let decoded = MarkdownCodec.decode(text)
        #expect(decoded.fields?.task?.readingText(from: decoded.document) == item)
    }

    @Test func tasksWithAnEditedFileFollowTheFile() {
        let text = """
        ---
        id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
        task:
          backlog: true
          status: done
        ---
        # Ändrad i ett annat program

        Egen rad

        - [x] Klart steg
        """
        let decoded = MarkdownCodec.decode(text)
        let item = decoded.fields?.task?.readingText(from: decoded.document)

        #expect(item?.task == "Ändrad i ett annat program")
        #expect(item?.note == "Egen rad")
        #expect(item?.subtasks == [.init(title: "Klart steg", isDone: true)])
        #expect(item?.isBacklog == true)
        #expect(item?.status == .done)
        #expect(item?.protocolID == nil)
    }

    @Test func eachTaskIsItsOwnFileInTheTasksFolder() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesV-Tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let note = protocolNote([checkbox("Ett – Ada")])
        let store = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        await store.load()
        store.addProtocol(note)
        store.addActionItems([ActionItem(source: "Ett – Ada", task: "Ett", note: "Notering")], to: note.id)
        store.addManualActionItem(ActionItem(source: "Två", task: "Två"))
        await store.prepareForTermination()

        let names = try FileManager.default.contentsOfDirectory(atPath: rootURL.appending(path: "Tasks").path(percentEncoded: false))
        #expect(Set(names) == ["Ett.md", "Två.md"])

        let restarted = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        await restarted.load()
        let row = try #require(restarted.actionItemRows.first { $0.item.task == "Ett" })
        #expect(row.protocolID == note.id)
        #expect(row.item.note == "Notering")
        #expect(row.meetingTitle == "Sync")
        #expect(restarted.newActionItemCount == 0)
        #expect(restarted.folders.contains { $0.name == NoteFolder.tasksName })
        #expect(!restarted.sidebarFolders.contains { $0.name == NoteFolder.tasksName })
    }

    @Test func permanentlyDeletingAProtocolRemovesItsTasks() async throws {
        let note = protocolNote([checkbox("Ett")], actionItems: [ActionItem(source: "Ett", task: "Ett")])
        let (store, _) = await makeStore([note])
        store.deleteNote(note.id)
        store.deleteNote(note.id)
        store.confirmPermanentDeletion()

        #expect(store.notes.values.allSatisfy { $0.task == nil })
    }

    @Test func aTaskWhoseProtocolIsGoneIsKept() async throws {
        let (store, _) = await makeStore([])
        store.addActionItems([ActionItem(source: "Ett", task: "Ett")], to: UUID())

        let row = try #require(store.actionItemRows.first)
        #expect(row.isManual)
        store.removeActionItem(row.id)
        #expect(store.notes.values.allSatisfy { $0.task == nil })
    }

    @Test func oldTasksAreMovedToFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesV-Tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storage = LocalStorageService(rootURL: rootURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let note = Note(
            folderID: NoteFolder.meetingProtocolsName, modified: date, sourceNoteID: UUID(),
            actionItems: [
                ActionItem(source: "Ett", task: "Ett", owner: "Ada", dueDate: day(2026, 11, 20), note: "Rad\nRad två", subtasks: [.init(title: "Steg", isDone: true)]),
                ActionItem(source: "Bort", task: "Bort", status: .ignored),
            ],
            document: NoteDocument(blocks: [.paragraph(.title, "Protokoll"), checkbox("Ett"), checkbox("Bort")])
        )
        try await storage.save(note)
        var list = Note(folderID: NoteFolder.manualTasksName, document: NoteDocument(blocks: [.paragraph(.title, "Tasks")]))
        list.actionItems = [ActionItem(source: "Egen", task: "Egen", isMine: true, isBacklog: true)]
        try await storage.save(list)

        let store = NoteStore(storage: storage)
        await store.load()

        #expect(Set(store.actionItemRows.map(\.item.task)) == ["Ett", "Egen"])
        #expect(store.newActionItemCount == 0)
        let moved = try #require(store.actionItemRows.first { $0.item.task == "Ett" })
        #expect(moved.protocolID == note.id)
        #expect(moved.item.note == "Rad\nRad två")
        #expect(moved.item.subtasks == [.init(title: "Steg", isDone: true)])
        #expect(moved.item.dueDate == day(2026, 11, 20))
        #expect(store.actionItemRows.first { $0.item.task == "Egen" }?.item.isBacklog == true)
        #expect(store.notes[note.id]?.actionItems == [])
        #expect(store.notes[note.id]?.modified == date)
        let manualPath = rootURL.appending(path: NoteFolder.manualTasksName).path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: manualPath))

        // A second start finds nothing more to move.
        let restarted = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        await restarted.load()
        #expect(restarted.notes.values.filter { $0.task != nil }.count == 3)
        let text = try String(contentsOf: rootURL.appending(path: "Tasks/Ett.md"), encoding: .utf8)
        #expect(text.contains("- [x] Steg"))
    }

    @Test func anInterruptedMoveDoesNotDuplicateTasks() async throws {
        let storage = InMemoryStorageService()
        let protocolID = UUID()
        var note = Note(id: protocolID, folderID: NoteFolder.meetingProtocolsName, sourceNoteID: UUID(), document: NoteDocument(blocks: [.paragraph(.title, "P"), checkbox("Ett")]))
        var item = ActionItem(source: "Ett", task: "Ett")
        note.actionItems = [item]
        item.protocolID = protocolID
        // The file was written, but the protocol still has its old entry.
        try await storage.save(note)
        try await storage.save(Note.taskFile(item, id: UUID(derivedFrom: "\(protocolID.uuidString)/0")))

        let store = NoteStore(storage: storage)
        await store.load()

        #expect(store.actionItemRows.count == 1)
        #expect(store.notes[protocolID]?.actionItems == [])
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
        let meetings = ActionItemOverview.sections(of: rows, filter: .all, sort: .meeting)
        #expect(meetings.map(\.title) == ["Nytt", "Gammalt"])

        let owners = ActionItemOverview.sections(of: rows, filter: .all, sort: .owner)
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
            ActionItemOverview.sections(of: rows, filter: .all, sort: .dueDate, searchText: query).flatMap(\.rows).map(\.item.task)
        }
        #expect(tasks("offert") == ["Skicka offert"])
        #expect(tasks("asa") == ["Skicka offert"])
        #expect(tasks("styrelse") == ["Boka"])
    }
}
