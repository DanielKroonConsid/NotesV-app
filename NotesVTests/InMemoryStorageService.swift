import Foundation
@testable import NotesV

/// A `StorageService` in memory, for testing `NoteStore` without touching the disk.
actor InMemoryStorageService: StorageService {
    private(set) var savedNotes: [UUID: Note] = [:]
    private var folders = [NoteFolder(name: NoteFolder.defaultName)]

    func loadLibrary() async throws -> NoteLibrary {
        NoteLibrary(folders: folders, notes: Array(savedNotes.values))
    }

    /// Makes every save fail, like a notes folder that has gone away.
    private var failsToSave = false

    func setFailsToSave(_ fails: Bool) {
        failsToSave = fails
    }

    func save(_ note: Note) async throws {
        if failsToSave {
            throw CocoaError(.fileWriteNoPermission)
        }
        savedNotes[note.id] = note
    }

    func deletePermanently(_ noteID: UUID) async throws {
        savedNotes[noteID] = nil
    }

    func createFolder(named name: String) async throws -> NoteFolder {
        let folder = NoteFolder(name: name)
        folders.append(folder)
        return folder
    }

    func renameFolder(_ folderID: NoteFolder.ID, to newName: String) async throws -> NoteFolder {
        NoteFolder(name: newName)
    }

    func deleteFolder(_ folderID: NoteFolder.ID) async throws {
        folders.removeAll { $0.id == folderID }
    }
}
