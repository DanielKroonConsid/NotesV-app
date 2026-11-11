import Foundation
import Observation

/// Keeps `settings.json` in the notes folder up to date, and restores from it when the user agrees.
///
/// The file is only read after the user has seen what it contains. It can be in a shared folder,
/// and a changed server address would otherwise send meeting data and an API key to that server.
@MainActor
@Observable
final class SettingsBackup {
    /// Settings the user is being asked about. Nothing is written while they decide.
    private(set) var pendingRestore: AppSettingsSnapshot?
    private(set) var errorMessage: String?

    @ObservationIgnored private let aiSettings: AISettings
    @ObservationIgnored private let profile: ProfileSettings
    @ObservationIgnored private let storage: StorageSettings
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    private static let writeDelay: Duration = .milliseconds(500)

    init(aiSettings: AISettings, profile: ProfileSettings, storage: StorageSettings) {
        self.aiSettings = aiSettings
        self.profile = profile
        self.storage = storage
    }

    private var current: AppSettingsSnapshot {
        AppSettingsSnapshot(ai: aiSettings.configuration, myNames: profile.namesText)
    }

    /// The settings in the notes folder.
    var stored: AppSettingsSnapshot? {
        SettingsFile.read(in: storage.rootURL)
    }

    /// Starts following changes. An existing file is left alone, since it may hold newer settings.
    func start() {
        aiSettings.onChange = { [weak self] in self?.scheduleWrite() }
        profile.onChange = { [weak self] in self?.scheduleWrite() }
        if !FileManager.default.fileExists(atPath: SettingsFile.url(in: storage.rootURL).path(percentEncoded: false)) {
            writeNow()
        }
    }

    /// After moving to another folder: offers its settings, or saves the current ones there.
    func folderDidChange() {
        if let stored {
            pendingRestore = stored == current ? nil : stored
        } else {
            writeNow()
        }
    }

    func offerRestore() {
        pendingRestore = stored
    }

    func restore() {
        guard let snapshot = pendingRestore else { return }
        pendingRestore = nil
        aiSettings.configuration = snapshot.ai
        profile.namesText = snapshot.myNames
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    func writeNow() {
        writeTask?.cancel()
        writeTask = nil
        guard pendingRestore == nil else { return }
        guard SettingsFile.canOverwrite(in: storage.rootURL) else {
            errorMessage = String(localized: "settings.json in the notes folder is from a newer version of NotesV or can’t be read, so it isn’t replaced. Your settings are still saved on this Mac.")
            return
        }
        do {
            try SettingsFile.write(current, in: storage.rootURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }
}
