import Foundation

/// Remembers a folder the user picked, so the sandboxed app can open it again after a restart.
enum StorageFolderBookmark {
    static let notesFolderName = "NotesV"

    /// The folder the notes go in. A separate folder keeps NotesV from treating the other contents
    /// of the picked folder, such as the whole OneDrive, as note folders.
    static func notesRoot(in folderURL: URL) -> URL {
        folderURL.lastPathComponent == notesFolderName
            ? folderURL
            : folderURL.appending(path: notesFolderName, directoryHint: .isDirectory)
    }

    static func make(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(options: .withSecurityScope)
    }

    /// The folder, also after a rename or move. `isStale` means the bookmark should be made again.
    static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }
}
