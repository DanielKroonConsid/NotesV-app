import Foundation

/// Everything the app has stored: all folders and all notes in them.
struct NoteLibrary: Sendable {
    var folders: [NoteFolder]
    var notes: [Note]
}

/// Stores notes as Markdown files, one subfolder per app folder.
///
/// Phase 1 uses `LocalStorageService`. A OneDrive implementation will replace it later without
/// changes to the rest of the app.
protocol StorageService: Sendable {
    func loadLibrary() async throws -> NoteLibrary

    /// Creates or updates the note's file. Renames or moves the file if the title or folder changed.
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

    var errorDescription: String? {
        switch self {
        case .folderAlreadyExists(let name):
            String(localized: "A folder named “\(name)” already exists.")
        case .folderNotEmpty(let name):
            String(localized: "The folder “\(name)” isn’t empty.")
        }
    }
}
