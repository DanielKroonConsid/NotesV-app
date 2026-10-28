import Foundation

/// Stores notes as Markdown files in a folder on this Mac.
actor LocalStorageService: StorageService {
    private let rootURL: URL
    private let fileManager = FileManager.default
    /// Where each loaded or saved note lives on disk.
    private var fileURLs: [UUID: URL] = [:]

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// `~/Library/Application Support/NotesV/Notes` (inside the app's sandbox container).
    static func defaultRootURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "NotesV/Notes", directoryHint: .isDirectory)
    }

    func loadLibrary() async throws -> NoteLibrary {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        fileURLs = [:]

        var folders: [NoteFolder] = []
        var notes: [Note] = []
        let folderURLs = try fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        for folderURL in folderURLs where isDirectory(folderURL) {
            let folder = NoteFolder(name: folderURL.lastPathComponent)
            folders.append(folder)

            let fileURLs = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == FileNaming.noteExtension {
                if let note = try? readNote(at: fileURL, folderID: folder.id) {
                    notes.append(note)
                }
            }
        }
        return NoteLibrary(folders: folders, notes: notes)
    }

    func save(_ note: Note) async throws {
        let folderURL = url(forFolder: note.folderID)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let currentURL = fileURLs[note.id]
        let wantedBaseName = FileNaming.sanitizedName(note.document.title)
        let targetURL: URL
        if let currentURL,
           currentURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL,
           FileNaming.baseName(ofNoteFileName: currentURL.lastPathComponent) == wantedBaseName {
            targetURL = currentURL
        } else {
            targetURL = availableURL(in: folderURL, title: note.document.title, ignoring: currentURL)
        }

        let data = Data(MarkdownCodec.encode(note).utf8)
        try data.write(to: targetURL, options: .atomic)
        if let currentURL, currentURL != targetURL {
            try? fileManager.removeItem(at: currentURL)
        }
        fileURLs[note.id] = targetURL
    }

    func deletePermanently(_ noteID: UUID) async throws {
        guard let fileURL = fileURLs.removeValue(forKey: noteID) else { return }
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func createFolder(named name: String) async throws -> NoteFolder {
        let folder = NoteFolder(name: FileNaming.sanitizedName(name))
        let folderURL = url(forFolder: folder.id)
        guard !fileManager.fileExists(atPath: folderURL.path(percentEncoded: false)) else {
            throw StorageError.folderAlreadyExists(folder.name)
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folder
    }

    func renameFolder(_ folderID: NoteFolder.ID, to newName: String) async throws -> NoteFolder {
        let folder = NoteFolder(name: FileNaming.sanitizedName(newName))
        guard folder.id != folderID else { return folder }
        let oldURL = url(forFolder: folderID)
        let newURL = url(forFolder: folder.id)
        guard !fileManager.fileExists(atPath: newURL.path(percentEncoded: false)) else {
            throw StorageError.folderAlreadyExists(folder.name)
        }
        try fileManager.moveItem(at: oldURL, to: newURL)

        for (noteID, fileURL) in fileURLs where fileURL.deletingLastPathComponent().lastPathComponent == folderID {
            fileURLs[noteID] = newURL.appending(path: fileURL.lastPathComponent)
        }
        return folder
    }

    func deleteFolder(_ folderID: NoteFolder.ID) async throws {
        let folderURL = url(forFolder: folderID)
        let contents = (try? fileManager.contentsOfDirectory(atPath: folderURL.path(percentEncoded: false))) ?? []
        guard contents.allSatisfy({ $0.hasPrefix(".") }) else {
            throw StorageError.folderNotEmpty(folderID)
        }
        try fileManager.removeItem(at: folderURL)
    }

    // MARK: - Helpers

    private func readNote(at fileURL: URL, folderID: NoteFolder.ID) throws -> Note {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let decoded = MarkdownCodec.decode(text)
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let fileModified = values?.contentModificationDate ?? .nowWholeSeconds

        // A copied file keeps the same id, so give the copy a new one.
        var id = decoded.fields?.id ?? UUID()
        if fileURLs[id] != nil {
            id = UUID()
        }
        fileURLs[id] = fileURL

        return Note(
            id: id,
            folderID: folderID,
            created: decoded.fields?.created ?? values?.creationDate ?? fileModified,
            modified: decoded.fields?.modified ?? fileModified,
            isPinned: decoded.fields?.isPinned ?? false,
            meeting: decoded.fields?.meeting,
            document: decoded.document
        )
    }

    private func url(forFolder folderID: NoteFolder.ID) -> URL {
        rootURL.appending(path: folderID, directoryHint: .isDirectory)
    }

    private func availableURL(in folderURL: URL, title: String, ignoring ignoredURL: URL?) -> URL {
        var number = 1
        while true {
            let candidate = folderURL.appending(path: FileNaming.noteFileName(title: title, number: number))
            let isTaken = fileManager.fileExists(atPath: candidate.path(percentEncoded: false))
            if !isTaken || candidate.standardizedFileURL == ignoredURL?.standardizedFileURL {
                return candidate
            }
            number += 1
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
