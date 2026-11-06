import CryptoKit
import Foundation

/// Stores notes as Markdown files in a folder on this Mac.
actor LocalStorageService: StorageService {
    private let rootURL: URL
    private let fileManager = FileManager.default
    /// Where each loaded or saved note lives on disk.
    private var fileURLs: [UUID: URL] = [:]
    /// Each note's file as NotesV last read or wrote it, to notice changes made by others.
    private var fileHashes: [UUID: SHA256.Digest] = [:]

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
        moveFoldersIntoNotes()
        let previousURLs = fileURLs
        fileURLs = [:]
        fileHashes = [:]

        var folders: [NoteFolder] = []
        var notes: [Note] = []
        // A folder that couldn't be moved into Notes is still read from its old place.
        for folderURL in try directories(in: rootURL) + directories(in: notesFolderURL) {
            let folder = NoteFolder(name: folderURL.lastPathComponent)
            if !folders.contains(folder) {
                folders.append(folder)
            }

            let fileURLs = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == FileNaming.noteExtension {
                if let note = try? readNote(at: fileURL, folderID: folder.id, previousURLs: previousURLs) {
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
        let wantedBaseName = FileNaming.sanitizedName(note.title)
        let targetURL: URL
        if let currentURL,
           currentURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL,
           FileNaming.baseName(ofNoteFileName: currentURL.lastPathComponent) == wantedBaseName {
            targetURL = currentURL
        } else {
            targetURL = availableURL(in: folderURL, title: note.title, ignoring: currentURL)
        }

        if let currentURL, let knownHash = fileHashes[note.id],
           let fileOnDisk = try? Data(contentsOf: currentURL), SHA256.hash(data: fileOnDisk) != knownHash {
            throw StorageError.changedOutsideApp(note.title)
        }

        let data = Data(MarkdownCodec.encode(note).utf8)
        try data.write(to: targetURL, options: .atomic)
        if let currentURL, currentURL != targetURL {
            try? fileManager.removeItem(at: currentURL)
        }
        fileURLs[note.id] = targetURL
        fileHashes[note.id] = SHA256.hash(data: data)
    }

    func deletePermanently(_ noteID: UUID) async throws {
        fileHashes[noteID] = nil
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

    private func readNote(at fileURL: URL, folderID: NoteFolder.ID, previousURLs: [UUID: URL]) throws -> Note {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let decoded = MarkdownCodec.decode(text)
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let fileModified = values?.contentModificationDate ?? .nowWholeSeconds

        // A file keeps its id between loads. A copied file has the same id as the original,
        // so the copy gets a new one.
        let knownID = previousURLs.first { $0.value.standardizedFileURL == fileURL.standardizedFileURL }?.key
        var id = knownID ?? decoded.fields?.id ?? UUID()
        let originalExists = previousURLs[id].map { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        if knownID == nil, fileURLs[id] != nil || originalExists {
            id = UUID()
        }
        fileURLs[id] = fileURL
        fileHashes[id] = SHA256.hash(data: data)

        return Note(
            id: id,
            folderID: folderID,
            created: decoded.fields?.created ?? values?.creationDate ?? fileModified,
            modified: decoded.fields?.modified ?? fileModified,
            isPinned: decoded.fields?.isPinned ?? false,
            meeting: decoded.fields?.meeting,
            sourceNoteID: decoded.fields?.sourceNoteID,
            sentAt: decoded.fields?.sentAt,
            document: decoded.document
        )
    }

    private var notesFolderURL: URL {
        rootURL.appending(path: NoteFolder.defaultName, directoryHint: .isDirectory)
    }

    /// The user's folders are inside Notes. Notes and the system folders are in the root.
    private func url(forFolder folderID: NoteFolder.ID) -> URL {
        let parentURL = NoteFolder(name: folderID).isSubfolder ? notesFolderURL : rootURL
        return parentURL.appending(path: folderID, directoryHint: .isDirectory)
    }

    private func directories(in url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter(isDirectory)
    }

    /// Earlier versions kept the user's folders next to Notes, and a Mac that still runs one can
    /// add more, so this runs on every load.
    private func moveFoldersIntoNotes() {
        let folderURLs = (try? directories(in: rootURL)) ?? []
        for folderURL in folderURLs
        where NoteFolder(name: folderURL.lastPathComponent).isSubfolder && isNoteFolder(folderURL) {
            let targetURL = url(forFolder: folderURL.lastPathComponent)
            do {
                try fileManager.createDirectory(at: notesFolderURL, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                    try mergeFolder(folderURL, into: targetURL)
                } else {
                    try fileManager.moveItem(at: folderURL, to: targetURL)
                }
            } catch {
                continue
            }
        }
    }

    /// Whether the directory is empty or holds a NotesV note. A picked folder can already be named
    /// NotesV and hold other things, and those must stay where they are.
    private func isNoteFolder(_ folderURL: URL) -> Bool {
        let itemURLs = (try? fileManager.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return itemURLs.isEmpty || itemURLs.contains { itemURL in
            guard itemURL.pathExtension.lowercased() == FileNaming.noteExtension,
                  let text = try? String(contentsOf: itemURL, encoding: .utf8) else { return false }
            return MarkdownCodec.decode(text).fields?.id != nil
        }
    }

    /// Moves the files over. Nothing is lost: an identical file is dropped, and a different note
    /// with the same name gets a number. The folder is removed only if nothing is left in it.
    private func mergeFolder(_ folderURL: URL, into targetURL: URL) throws {
        let itemURLs = try fileManager.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        for itemURL in itemURLs {
            let name = itemURL.lastPathComponent
            let candidateURL = targetURL.appending(path: name)
            if !fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
                try fileManager.moveItem(at: itemURL, to: candidateURL)
            } else if fileManager.contentsEqual(
                atPath: itemURL.path(percentEncoded: false), andPath: candidateURL.path(percentEncoded: false)
            ) {
                try fileManager.removeItem(at: itemURL)
            } else if itemURL.pathExtension.lowercased() == FileNaming.noteExtension {
                let title = FileNaming.baseName(ofNoteFileName: name)
                try fileManager.moveItem(at: itemURL, to: availableURL(in: targetURL, title: title, ignoring: nil))
            }
        }
        let remaining = try fileManager.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        if remaining.isEmpty {
            try fileManager.removeItem(at: folderURL)
        }
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
