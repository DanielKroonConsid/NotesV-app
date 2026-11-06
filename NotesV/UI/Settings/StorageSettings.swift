import Foundation
import Observation

/// Where the notes are stored: in the app's own folder on this Mac, or in a folder the user picked.
@MainActor
@Observable
final class StorageSettings {
    /// The folder the user picked. `nil` means the app's own folder.
    private(set) var folderURL: URL?
    /// The picked folder couldn't be opened, so the app's own folder is used for now.
    private(set) var isFolderMissing = false
    private(set) var isMoving = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let defaultRootURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    private static let bookmarkKey = "storage.folderBookmark"

    init(defaultRootURL: URL, defaultsSuiteName: String? = nil) {
        self.defaultRootURL = defaultRootURL
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        restoreFolder()
    }

    var rootURL: URL {
        folderURL.map(StorageFolderBookmark.notesRoot(in:)) ?? defaultRootURL
    }

    /// Copies the notes to the picked folder and continues there. The old files are kept.
    func useFolder(_ url: URL, store: NoteStore) async {
        guard url.standardizedFileURL != folderURL?.standardizedFileURL else { return }
        let isAccessing = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try StorageFolderBookmark.make(for: url)
            try await move(store, to: StorageFolderBookmark.notesRoot(in: url))
            folderURL?.stopAccessingSecurityScopedResource()
            folderURL = url
            isFolderMissing = false
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Copies the notes back to the app's own folder and continues there.
    func useThisMac(store: NoteStore) async {
        do {
            try await move(store, to: defaultRootURL)
            folderURL?.stopAccessingSecurityScopedResource()
            folderURL = nil
            isFolderMissing = false
            defaults.removeObject(forKey: Self.bookmarkKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ store: NoteStore, to rootURL: URL) async throws {
        isMoving = true
        errorMessage = nil
        defer { isMoving = false }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try await store.moveLibrary(to: LocalStorageService(rootURL: rootURL))
    }

    private func restoreFolder() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        guard let resolved = StorageFolderBookmark.resolve(bookmark) else {
            isFolderMissing = true
            return
        }
        let isAccessing = resolved.url.startAccessingSecurityScopedResource()
        let root = StorageFolderBookmark.notesRoot(in: resolved.url)
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            if isAccessing {
                resolved.url.stopAccessingSecurityScopedResource()
            }
            isFolderMissing = true
            return
        }
        folderURL = resolved.url
        if resolved.isStale, let fresh = try? StorageFolderBookmark.make(for: resolved.url) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
    }
}
