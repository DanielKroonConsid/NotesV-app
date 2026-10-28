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

    @ObservationIgnored private let storage: any StorageService
    @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private static let saveDelay: Duration = .milliseconds(600)

    init(storage: any StorageService) {
        self.storage = storage
    }

    // MARK: - Derived state

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
            ? notes.values.filter { $0.folderID != NoteFolder.recentlyDeletedName && $0.matches(searchText: searchText) }
            : notes.values.filter { $0.folderID == selectedFolderID }
        return candidates.sorted { lhs, rhs in
            lhs.modified != rhs.modified ? lhs.modified > rhs.modified : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Pinned notes first, then the rest grouped by date, like in Notes.
    var noteSections: [NoteSection] {
        let notes = visibleNotes
        let showsPins = selectedFolder?.kind != .recentlyDeleted || isSearching
        var sections: [NoteSection] = []
        let pinned = showsPins ? notes.filter(\.isPinned) : []
        if !pinned.isEmpty {
            sections.append(NoteSection(id: .pinned, notes: pinned))
        }

        var groups: [(NoteDateGroup, [Note])] = []
        for note in notes where !(showsPins && note.isPinned) {
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

    func noteCount(in folderID: NoteFolder.ID) -> Int {
        notes.values.filter { $0.folderID == folderID }.count
    }

    private var defaultFolderID: NoteFolder.ID? {
        let regular = folders.filter { $0.kind == .regular }
        return (regular.first { $0.name == NoteFolder.defaultName } ?? regular.first)?.id
    }

    // MARK: - Loading

    func load() async {
        do {
            var library = try await storage.loadLibrary()
            if !library.folders.contains(where: { $0.kind == .regular }) {
                library.folders.append(try await storage.createFolder(named: NoteFolder.defaultName))
            }
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

    /// Adds a finished note, e.g. a generated protocol, saves it and selects it.
    func addNote(_ note: Note) {
        var note = note
        if note.folderID == NoteFolder.recentlyDeletedName || !folders.contains(where: { $0.id == note.folderID }),
           let defaultFolderID {
            note.folderID = defaultFolderID
        }
        notes[note.id] = note
        searchText = ""
        selectedFolderID = note.folderID
        selectedNoteID = note.id
        scheduleSave(note.id)
    }

    func updateDocument(_ document: NoteDocument, of noteID: UUID) {
        guard var note = notes[noteID], note.document != document else { return }
        note.document = document
        note.modified = .nowWholeSeconds
        notes[noteID] = note
        scheduleSave(noteID)
    }

    func togglePin(_ noteID: UUID) {
        notes[noteID]?.isPinned.toggle()
        scheduleSave(noteID)
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
        }
        guard note.document.hasContent else {
            discard(noteID)
            return
        }
        notes[noteID]?.folderID = NoteFolder.recentlyDeletedName
        notes[noteID]?.isPinned = false
        if !folders.contains(where: { $0.kind == .recentlyDeleted }) {
            folders.append(NoteFolder(name: NoteFolder.recentlyDeletedName))
            sortFolders()
        }
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
                if note.document.hasContent {
                    notes[note.id]?.folderID = NoteFolder.recentlyDeletedName
                    notes[note.id]?.isPinned = false
                    await save(note.id)
                } else {
                    discard(note.id)
                }
            }
            if !folders.contains(where: { $0.kind == .recentlyDeleted }) {
                folders.append(NoteFolder(name: NoteFolder.recentlyDeletedName))
            }
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
        if let selectedNoteID, notes[selectedNoteID]?.document.hasContent == false {
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
        guard let note = notes[noteID], note.document.hasContent else { return }
        do {
            try await storage.save(note)
        } catch {
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
        if let note = notes[noteID], !note.document.hasContent {
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

    private func selectFirstVisibleNote() {
        selectedNoteID = visibleNotes.first?.id
    }

    /// Selects the note after `noteID` in the list, or the one before it.
    private func selectNeighbor(of noteID: UUID) {
        let ids = visibleNotes.map(\.id)
        guard let index = ids.firstIndex(of: noteID) else { return }
        if index + 1 < ids.count {
            selectedNoteID = ids[index + 1]
        } else if index > 0 {
            selectedNoteID = ids[index - 1]
        } else {
            selectedNoteID = nil
        }
    }

    private func sortFolders() {
        folders.sort { lhs, rhs in
            func rank(_ folder: NoteFolder) -> Int {
                if folder.kind == .recentlyDeleted { return 2 }
                return folder.name == NoteFolder.defaultName ? 0 : 1
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
