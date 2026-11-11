import Foundation

/// Everything the app has stored: all folders and all notes in them.
struct NoteLibrary: Sendable {
    var folders: [NoteFolder]
    var notes: [Note]
}

/// Stores notes as Markdown files, one subfolder per app folder.
protocol StorageService: Sendable {
    func loadLibrary() async throws -> NoteLibrary

    /// Creates or updates the note's file. Renames or moves the file if the title or folder changed.
    /// Throws `StorageError.changedOutsideApp` instead of overwriting a file someone else has changed.
    func save(_ note: Note) async throws

    func deletePermanently(_ noteID: UUID) async throws

    func createFolder(named name: String) async throws -> NoteFolder

    func renameFolder(_ folderID: NoteFolder.ID, to newName: String) async throws -> NoteFolder

    /// Deletes an empty folder. Move its notes elsewhere first.
    func deleteFolder(_ folderID: NoteFolder.ID) async throws
}

enum StorageError: LocalizedError {
    case folderAlreadyExists(String)
    case folderNotEmpty(String)
    case changedOutsideApp(String)
    case unsavedChanges(Int)

    var errorDescription: String? {
        switch self {
        case .folderAlreadyExists(let name):
            String(localized: "A folder named “\(name)” already exists.")
        case .folderNotEmpty(let name):
            String(localized: "The folder “\(name)” isn’t empty.")
        case .changedOutsideApp(let name):
            String(localized: "“\(name)” was changed outside NotesV.")
        case .unsavedChanges(let count):
            String(localized: "\(count) notes couldn’t be saved, so the notes folder wasn’t changed. Check that the current folder is available and try again.")
        }
    }
}
