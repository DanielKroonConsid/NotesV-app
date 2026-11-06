import Foundation
import Observation

/// The app's state: folders, notes, selection and search. Saves changes through a `StorageService`.
@MainActor
@Observable
final class NoteStore {
    struct NoteSection: Identifiable {
        enum ID: Hashable {
            case pinned
            case date(NoteDateGroup)
            case noMeeting
            /// The start of the day the meetings were held.
            case meetingDay(Date)
        }

        let id: ID
        let notes: [Note]
    }

    private(set) var folders: [NoteFolder] = []
    private(set) var notes: [UUID: Note] = [:]
    private(set) var isLoaded = false

    var selectedFolderID: NoteFolder.ID? {
        didSet {
            guard oldValue != selectedFolderID else { return }
            if let selectedNoteID, !visibleNotes.contains(where: { $0.id == selectedNoteID }) {
                selectFirstVisibleNote()
            } else if selectedNoteID == nil {
                selectFirstVisibleNote()
            }
        }
    }

    var selectedNoteID: UUID? {
        didSet {
            guard oldValue != selectedNoteID, let oldValue else { return }
            noteDidLoseSelection(oldValue)
        }
    }

    var searchText = ""
    var errorMessage: String?
    var isCreatingFolder = false
    var notePendingPermanentDeletion: UUID?
    /// A new note whose editor should get keyboard focus.
    private(set) var noteToFocus: UUID?

    @ObservationIgnored private var storage: any StorageService
    @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]
    /// Notes that couldn't be saved, so they only exist here.
    @ObservationIgnored private var unsavedNoteIDs: Set<UUID> = []
    private static let saveDelay: Duration = .milliseconds(600)

    init(storage: any StorageService) {
        self.storage = storage
    }

    // MARK: - Derived state

    /// The notes the task overview covers.
    private var taskNotes: [Note] {
        notes.values.filter { note in
            note.holdsManualTasks || (note.isMeetingProtocol && note.folderID != NoteFolder.recentlyDeletedName)
        }
    }

    /// The tasks in the overview. Whether a task is done follows its checkbox while the checkbox exists.
    var actionItemRows: [ActionItemRow] {
        taskNotes.flatMap { note in
            let blocks = note.matchActionItems().blocks
            return note.actionItems.enumerated().compactMap { index, item -> ActionItemRow? in
                guard item.status != .ignored else { return nil }
                var isDone = item.status == .done
                if let block = blocks[index], case .listItem(let checkbox) = note.document.blocks[block] {
                    isDone = checkbox.isChecked
                }
                return ActionItemRow(
                    id: ActionItemRow.ID(noteID: note.id, index: index),
                    item: item,
                    isDone: isDone,
                    meetingTitle: note.holdsManualTasks ? "" : note.actionItemMeetingTitle,
                    meetingDate: note.holdsManualTasks ? .distantPast : note.actionItemMeetingDate,
                    isManual: note.holdsManualTasks
                )
            }
        }
    }

    /// Everyone in the meetings or the list, to choose an owner from.
    var actionItemPeople: [String] {
        let names = taskNotes.flatMap(\.actionItemPeople) + taskNotes.flatMap(\.actionItems).compactMap(\.owner)
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var newActionItemCount: Int {
        taskNotes.reduce(0) { $0 + $1.newActionItemLines().count }
    }

    var openActionItemCount: Int {
        actionItemRows.filter { !$0.isDone }.count
    }

    /// The checkboxes that haven't been reviewed, per protocol with the latest meeting first.
    func actionItemProposals(myNames: [String]) -> [ActionItemProposal] {
        taskNotes
            .sorted { lhs, rhs in
                lhs.actionItemMeetingDate != rhs.actionItemMeetingDate
                    ? lhs.actionItemMeetingDate > rhs.actionItemMeetingDate
                    : lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { note in
                let lines = note.newActionItemLines()
                guard !lines.isEmpty else { return nil }
                return ActionItemProposal(
                    noteID: note.id,
                    title: note.actionItemMeetingTitle,
                    people: note.actionItemPeople,
                    drafts: lines.map {
                        ActionItemDraft(noteID: note.id, line: $0, meetingDate: note.actionItemMeetingDate, myNames: myNames)
                    }
                )
            }
    }

    var selectedNote: Note? {
        selectedNoteID.flatMap { notes[$0] }
    }

    var selectedFolder: NoteFolder? {
        folders.first { $0.id == selectedFolderID }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The notes in the selected folder, or all matching notes while searching. Newest first.
    var visibleNotes: [Note] {
        let candidates = isSearching
            ? notes.values.filter { $0.folderID != NoteFolder.recentlyDeletedName && !$0.holdsManualTasks && $0.matches(searchText: searchText) }
            : notes.values.filter { isNote($0, in: selectedFolderID) }
        return candidates.sorted { lhs, rhs in
            lhs.modified != rhs.modified ? lhs.modified > rhs.modified : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Pinned notes first. Note folders then group by meeting; everything else by date, like in Notes.
    var noteSections: [NoteSection] {
        let notes = visibleNotes
        let showsPins = selectedFolder?.kind != .recentlyDeleted || isSearching
        var sections: [NoteSection] = []
        let pinned = showsPins ? notes.filter(\.isPinned) : []
        if !pinned.isEmpty {
            sections.append(NoteSection(id: .pinned, notes: pinned))
        }

        let others = notes.filter { !(showsPins && $0.isPinned) }
        if selectedFolder?.kind == .regular, !isSearching {
            return sections + Self.meetingSections(of: others)
        }

        var groups: [(NoteDateGroup, [Note])] = []
        for note in others {
            let group = NoteDateGroup(date: note.modified)
            if let last = groups.last, last.0 == group {
                groups[groups.count - 1].1.append(note)
            } else {
                groups.append((group, [note]))
            }
        }
        sections += groups.map { NoteSection(id: .date($0.0), notes: $0.1) }
        return sections
    }

    /// Notes without a meeting first, then one section per meeting day, latest first.
    private static func meetingSections(of notes: [Note]) -> [NoteSection] {
        let calendar = Calendar.current
        var withoutMeeting: [Note] = []
        var days: [Date: [Note]] = [:]
        for note in notes {
            if let start = note.meeting?.start {
                days[calendar.startOfDay(for: start), default: []].append(note)
            } else {
                withoutMeeting.append(note)
            }
        }

        var sections = withoutMeeting.isEmpty ? [] : [NoteSection(id: .noMeeting, notes: withoutMeeting)]
        for day in days.keys.sorted(by: >) {
            let notes = days[day, default: []].sorted { lhs, rhs in
                lhs.meeting?.start != rhs.meeting?.start
                    ? lhs.meeting?.start ?? .distantPast > rhs.meeting?.start ?? .distantPast
                    : lhs.id.uuidString < rhs.id.uuidString
            }
            sections.append(NoteSection(id: .meetingDay(day), notes: notes))
        }
        return sections
    }

    func noteCount(in folderID: NoteFolder.ID) -> Int {
        notes.values.filter { isNote($0, in: folderID) }.count
    }

    /// The protocols in a folder that haven't been marked as sent.
    func unsentProtocolCount(in folderID: NoteFolder.ID) -> Int {
        notes.values.filter { note in
            note.isMeetingProtocol && !note.isSent && note.folderID == folderID
                && folderID != NoteFolder.recentlyDeletedName
        }.count
    }

    /// The folders in the sidebar: the stored folders plus the Tasks and Sent views.
    var sidebarFolders: [NoteFolder] {
        var result = folders.filter { $0.kind != .manualTasks }
        let deletedIndex = result.firstIndex { $0.kind == .recentlyDeleted } ?? result.endIndex
        result.insert(contentsOf: [.actionItems, .sent], at: deletedIndex)
        return result
    }

    /// Sent protocols are only listed in the Sent view, or in Recently Deleted once they are deleted.
    private func isNote(_ note: Note, in folderID: NoteFolder.ID?) -> Bool {
        let isDeleted = note.folderID == NoteFolder.recentlyDeletedName
        if folderID == NoteFolder.sent.id {
            return note.isSent && !isDeleted
        }
        return note.folderID == folderID && (!note.isSent || isDeleted)
    }

    private var defaultFolderID: NoteFolder.ID? {
        let regular = folders.filter { $0.kind == .regular }
        return (regular.first { $0.name == NoteFolder.defaultName } ?? regular.first)?.id
    }

    // MARK: - Loading

    func load() async {
        do {
            let library = try await loadLibrary()
            folders = library.folders
            sortFolders()
            notes = Dictionary(library.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            selectedFolderID = defaultFolderID
            selectFirstVisibleNote()
        } catch {
            report(error)
        }
        isLoaded = true
    }

    /// Picks up changes made to the files outside the app. Unsaved changes are saved first.
    func refresh() async {
        guard isLoaded else { return }
        await flushPendingSaves()
        await reloadFromStorage()
    }

    /// Copies everything to `destination` and continues there. The original files are kept, and a
    /// note that already exists in `destination` is left as it is.
    func moveLibrary(to destination: any StorageService) async throws {
        await flushPendingSaves()
        let source = try await storage.loadLibrary()
        let target = try await destination.loadLibrary()

        let targetFolderIDs = Set(target.folders.map(\.id))
        // Subfolders go last, because creating one also creates the Notes folder it is in.
        let sourceFolders = source.folders.sorted { !$0.isSubfolder && $1.isSubfolder }
        for folder in sourceFolders where !targetFolderIDs.contains(folder.id) {
            _ = try await destination.createFolder(named: folder.name)
        }
        let targetNoteIDs = Set(target.notes.map(\.id))
        for note in source.notes where !targetNoteIDs.contains(note.id) {
            try await destination.save(note)
        }

        storage = destination
        await load()
    }

    private func loadLibrary() async throws -> NoteLibrary {
        var library = try await storage.loadLibrary()
        if !library.folders.contains(where: { $0.kind == .regular }) {
            library.folders.append(try await storage.createFolder(named: NoteFolder.defaultName))
        }
        return library
    }

    private func reloadFromStorage() async {
        let library: NoteLibrary
        do {
            library = try await loadLibrary()
        } catch {
            report(error)
            return
        }

        func hasLocalChanges(_ noteID: UUID) -> Bool {
            saveTasks[noteID] != nil || unsavedNoteIDs.contains(noteID)
        }
        let stored = Dictionary(library.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (noteID, note) in notes where stored[noteID] == nil && note.hasContent && !hasLocalChanges(noteID) {
            notes[noteID] = nil
        }
        for (noteID, note) in stored where !hasLocalChanges(noteID) {
            // Compare as Markdown, since the file only keeps what the Markdown format can hold.
            let current = notes[noteID]
            if current?.folderID != note.folderID || current.map(MarkdownCodec.encode) != MarkdownCodec.encode(note) {
                notes[noteID] = note
            }
        }

        let storedFolderIDs = Set(library.folders.map(\.id))
        folders = library.folders + folders.filter { folder in
            !storedFolderIDs.contains(folder.id) && notes.values.contains { $0.folderID == folder.id }
        }
        sortFolders()
        if !sidebarFolders.contains(where: { $0.id == selectedFolderID }) {
            selectedFolderID = defaultFolderID
        }
        if selectedNoteID.flatMap({ notes[$0] }) == nil {
            selectFirstVisibleNote()
        }
    }

    // MARK: - Notes

    func createNote() {
        guard let folderID = selectedFolder?.kind == .regular ? selectedFolderID : defaultFolderID else { return }
        searchText = ""
        let note = Note(folderID: folderID)
        notes[note.id] = note
        selectedFolderID = folderID
        noteToFocus = note.id
        selectedNoteID = note.id
    }

    /// Stores a generated protocol in the Meeting Protocols folder. The selection stays on the source note.
    func addProtocol(_ note: Note) {
        var note = note
        note.folderID = NoteFolder.meetingProtocolsName
        notes[note.id] = note
        ensureFolder(named: NoteFolder.meetingProtocolsName)
        scheduleSave(note.id)
    }

    /// The protocols attached to a note, newest first.
    func attachments(of noteID: UUID) -> [Note] {
        notes.values
            .filter { $0.sourceNoteID == noteID && $0.folderID != NoteFolder.recentlyDeletedName }
            .sorted { $0.created > $1.created }
    }

    /// Shows a note in the main window.
    func reveal(_ noteID: UUID) {
        guard let note = notes[noteID] else { return }
        searchText = ""
        let isDeleted = note.folderID == NoteFolder.recentlyDeletedName
        selectedFolderID = note.isSent && !isDeleted ? NoteFolder.sent.id : note.folderID
        selectedNoteID = noteID
    }

    func updateDocument(_ document: NoteDocument, of noteID: UUID) {
        guard var note = notes[noteID], note.document != document else { return }
        note.document = document
        note.modified = .nowWholeSeconds
        notes[noteID] = note
        scheduleSave(noteID)
    }

    /// Sets the note's meeting. A meeting with nothing filled in is removed.
    func updateMeeting(_ meeting: MeetingDetails?, of noteID: UUID) {
        let meeting = meeting?.isEmpty == true ? nil : meeting
        guard var note = notes[noteID], note.meeting != meeting else { return }
        note.meeting = meeting
        note.modified = .nowWholeSeconds
        notes[noteID] = note
        scheduleSave(noteID)
    }

    func togglePin(_ noteID: UUID) {
        notes[noteID]?.isPinned.toggle()
        scheduleSave(noteID)
    }

    /// Marks a protocol as sent now, or removes the marking. Either way it leaves the current list.
    func toggleSent(_ noteID: UUID) {
        guard notes[noteID]?.isMeetingProtocol == true else { return }
        if selectedNoteID == noteID, !isSearching {
            selectNeighbor(of: noteID)
        }
        guard var note = notes[noteID] else { return }
        note.sentAt = note.sentAt == nil ? .nowWholeSeconds : nil
        notes[noteID] = note
        scheduleSave(noteID)
    }

    // MARK: - Tasks

    /// Adds reviewed tasks to their protocol. Tasks aren't edits to the text, so `modified` stays.
    func addActionItems(_ items: [ActionItem], to noteID: UUID) {
        guard !items.isEmpty, notes[noteID] != nil else { return }
        notes[noteID]?.actionItems += items
        scheduleSave(noteID)
    }

    /// Adds a task the user wrote, which isn't connected to a protocol.
    func addManualActionItem(_ item: ActionItem) {
        if notes[Note.manualTaskListID] == nil {
            notes[Note.manualTaskListID] = Note.manualTaskList()
            ensureFolder(named: NoteFolder.manualTasksName)
        }
        addActionItems([item], to: Note.manualTaskListID)
    }

    /// Keeps a checkbox out of the list, so it isn't suggested again.
    func ignoreActionItem(_ item: ActionItem, in noteID: UUID) {
        var item = item
        item.status = .ignored
        addActionItems([item], to: noteID)
    }

    func updateActionItem(_ id: ActionItemRow.ID, to item: ActionItem) {
        guard notes[id.noteID]?.actionItems.indices.contains(id.index) == true else { return }
        notes[id.noteID]?.actionItems[id.index] = item
        scheduleSave(id.noteID)
    }

    /// Takes a task out of the list. A protocol's checkbox stays, and isn't suggested again.
    func removeActionItem(_ id: ActionItemRow.ID) {
        guard let note = notes[id.noteID], note.actionItems.indices.contains(id.index) else { return }
        if note.holdsManualTasks {
            notes[id.noteID]?.actionItems.remove(at: id.index)
        } else {
            notes[id.noteID]?.actionItems[id.index].status = .ignored
        }
        scheduleSave(id.noteID)
    }

    /// Marks a task as done or not, in the list and on the protocol's checkbox.
    func setActionItem(_ id: ActionItemRow.ID, done: Bool) {
        guard var note = notes[id.noteID], note.actionItems.indices.contains(id.index) else { return }
        let item = note.actionItems[id.index]
        if let block = note.matchActionItems().blocks[id.index] {
            note.document.setChecked(done, block: block, expectedText: item.source)
        }
        note.actionItems[id.index].status = done ? .done : .open
        notes[id.noteID] = note
        scheduleSave(id.noteID)
    }

    func moveNote(_ noteID: UUID, to folderID: NoteFolder.ID) {
        guard var note = notes[noteID], note.folderID != folderID else { return }
        if selectedNoteID == noteID, !isSearching {
            selectNeighbor(of: noteID)
        }
        note.folderID = folderID
        notes[noteID] = note
        scheduleSave(noteID)
    }

    /// Moves a note to Recently Deleted. In Recently Deleted, asks to delete it permanently.
    func deleteNote(_ noteID: UUID) {
        guard let note = notes[noteID] else { return }
        if note.folderID == NoteFolder.recentlyDeletedName {
            notePendingPermanentDeletion = noteID
            return
        }
        if selectedNoteID == noteID {
            selectNeighbor(of: noteID)
            // The task overview has no neighbor to move on to.
            if selectedNoteID == noteID, selectedFolderID == NoteFolder.actionItems.id {
                selectedNoteID = nil
            }
        }
        guard note.hasContent else {
            discard(noteID)
            return
        }
        notes[noteID]?.folderID = NoteFolder.recentlyDeletedName
        notes[noteID]?.isPinned = false
        ensureFolder(named: NoteFolder.recentlyDeletedName)
        scheduleSave(noteID)
    }

    func confirmPermanentDeletion() {
        guard let noteID = notePendingPermanentDeletion else { return }
        notePendingPermanentDeletion = nil
        if selectedNoteID == noteID {
            selectNeighbor(of: noteID)
        }
        discard(noteID)
    }

    // MARK: - Folders

    func createFolder(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let folder = try await storage.createFolder(named: name)
                folders.append(folder)
                sortFolders()
                selectedFolderID = folder.id
            } catch {
                report(error)
            }
        }
    }

    func renameFolder(_ folderID: NoteFolder.ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folderID else { return }
        Task {
            await flushPendingSaves()
            do {
                let renamed = try await storage.renameFolder(folderID, to: name)
                folders = folders.map { $0.id == folderID ? renamed : $0 }
                sortFolders()
                for (noteID, note) in notes where note.folderID == folderID {
                    notes[noteID]?.folderID = renamed.id
                }
                if selectedFolderID == folderID {
                    selectedFolderID = renamed.id
                }
            } catch {
                report(error)
            }
        }
    }

    /// Moves the folder's notes to Recently Deleted and removes the folder.
    func deleteFolder(_ folderID: NoteFolder.ID) {
        Task {
            await flushPendingSaves()
            for note in notes.values where note.folderID == folderID {
                if note.hasContent {
                    notes[note.id]?.folderID = NoteFolder.recentlyDeletedName
                    notes[note.id]?.isPinned = false
                    await save(note.id)
                } else {
                    discard(note.id)
                }
            }
            ensureFolder(named: NoteFolder.recentlyDeletedName)
            do {
                try await storage.deleteFolder(folderID)
                folders.removeAll { $0.id == folderID }
                sortFolders()
                if selectedFolderID == folderID {
                    selectedFolderID = defaultFolderID
                }
            } catch {
                report(error)
            }
        }
    }

    // MARK: - Saving

    /// Saves everything that is waiting to be saved and drops an empty selected note. Call before quitting.
    func prepareForTermination() async {
        await flushPendingSaves()
        if let selectedNoteID, notes[selectedNoteID]?.hasContent == false {
            notes[selectedNoteID] = nil
            try? await storage.deletePermanently(selectedNoteID)
        }
    }

    private func scheduleSave(_ noteID: UUID) {
        saveTasks[noteID]?.cancel()
        saveTasks[noteID] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save(noteID)
        }
    }

    private func save(_ noteID: UUID) async {
        saveTasks[noteID] = nil
        // Empty notes are not saved, like in Notes.
        guard let note = notes[noteID], note.hasContent else { return }
        do {
            try await storage.save(note)
            unsavedNoteIDs.remove(noteID)
        } catch StorageError.changedOutsideApp {
            await keepBothVersions(of: note)
        } catch {
            unsavedNoteIDs.insert(noteID)
            report(error)
        }
    }

    /// The file changed outside the app while the note had changes here. The note shows the file's
    /// version, and the app's version continues as a new note, so nothing is lost.
    private func keepBothVersions(of note: Note) async {
        let copy = Note(
            folderID: note.folderID, created: note.created, modified: note.modified, isPinned: note.isPinned,
            meeting: note.meeting, sourceNoteID: note.sourceNoteID, sentAt: note.sentAt,
            actionItems: note.actionItems, document: note.document
        )
        notes[copy.id] = copy
        do {
            try await storage.save(copy)
            await reloadFromStorage()
            errorMessage = String(localized: "“\(note.title)” was changed outside NotesV. Both versions are kept as separate notes.")
        } catch {
            unsavedNoteIDs.insert(copy.id)
            report(error)
        }
    }

    private func flushPendingSaves() async {
        for noteID in Array(saveTasks.keys) {
            saveTasks[noteID]?.cancel()
            await save(noteID)
        }
    }

    // MARK: - Helpers

    private func noteDidLoseSelection(_ noteID: UUID) {
        if noteToFocus == noteID {
            noteToFocus = nil
        }
        if let note = notes[noteID], !note.hasContent {
            discard(noteID)
        }
    }

    private func discard(_ noteID: UUID) {
        saveTasks.removeValue(forKey: noteID)?.cancel()
        notes[noteID] = nil
        Task {
            do {
                try await storage.deletePermanently(noteID)
            } catch {
                report(error)
            }
        }
    }

    /// The visible notes in the order the list shows them.
    private var listedNoteIDs: [UUID] {
        noteSections.flatMap(\.notes).map(\.id)
    }

    private func selectFirstVisibleNote() {
        selectedNoteID = listedNoteIDs.first
    }

    /// Selects the note after `noteID` in the list, or the one before it.
    private func selectNeighbor(of noteID: UUID) {
        let ids = listedNoteIDs
        guard let index = ids.firstIndex(of: noteID) else { return }
        if index + 1 < ids.count {
            selectedNoteID = ids[index + 1]
        } else if index > 0 {
            selectedNoteID = ids[index - 1]
        } else {
            selectedNoteID = nil
        }
    }

    /// Shows a system folder in the sidebar. `StorageService.save` creates its directory.
    private func ensureFolder(named name: String) {
        guard !folders.contains(where: { $0.name == name }) else { return }
        folders.append(NoteFolder(name: name))
        sortFolders()
    }

    private func sortFolders() {
        folders.sort { lhs, rhs in
            func rank(_ folder: NoteFolder) -> Int {
                switch folder.kind {
                case .recentlyDeleted: return 4
                case .sent, .actionItems, .manualTasks: return 3
                case .meetingProtocols: return 2
                case .regular: return folder.name == NoteFolder.defaultName ? 0 : 1
                }
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
