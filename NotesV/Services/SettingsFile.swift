import Foundation

/// The settings that can be restored on another Mac. API keys are never part of it: they stay in
/// the Keychain. The storage folder isn't either, because the file lives inside that folder.
struct AppSettingsSnapshot: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var ai: AIEndpointConfiguration
    var myNames: String
}

/// `settings.json` in the root of the notes folder, so a new Mac can get the settings back.
enum SettingsFile {
    static let name = "settings.json"

    static func url(in rootURL: URL) -> URL {
        rootURL.appending(path: name)
    }

    /// Returns `nil` if the file is missing, damaged, from a newer app or has an unusable server.
    /// The file can come from a shared folder, so nothing in it is trusted without a check.
    static func read(in rootURL: URL) -> AppSettingsSnapshot? {
        guard let data = try? Data(contentsOf: url(in: rootURL)),
              let snapshot = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: data),
              snapshot.version <= AppSettingsSnapshot.currentVersion,
              (try? snapshot.ai.validatedBaseURL()) != nil else { return nil }
        return snapshot
    }

    /// Whether `write` may replace the file. A file this version can't read is kept, since it may
    /// come from a newer version or be a sync that hasn't finished, and holds settings worth keeping.
    static func canOverwrite(in rootURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: url(in: rootURL)) else {
            return !FileManager.default.fileExists(atPath: url(in: rootURL).path(percentEncoded: false))
        }
        guard let snapshot = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: data) else { return false }
        return snapshot.version <= AppSettingsSnapshot.currentVersion
    }

    static func write(_ snapshot: AppSettingsSnapshot, in rootURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url(in: rootURL), options: .atomic)
    }
}
