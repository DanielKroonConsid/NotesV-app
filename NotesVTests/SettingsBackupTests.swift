import Foundation
import Testing
@testable import NotesV

@MainActor
struct SettingsBackupTests {
    private struct Mac {
        let ai: AISettings
        let profile: ProfileSettings
        let storage: StorageSettings
        let backup: SettingsBackup
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "NotesV-Tests-\(UUID().uuidString)")
    }

    private func makeMac(root: URL) -> Mac {
        let suite = "NotesV-Tests-\(UUID().uuidString)"
        let ai = AISettings(keychain: KeychainService(service: "se.consid.NotesV.tests"), defaultsSuiteName: suite)
        let profile = ProfileSettings(defaultsSuiteName: suite)
        let storage = StorageSettings(defaultRootURL: root, defaultsSuiteName: suite)
        return Mac(ai: ai, profile: profile, storage: storage, backup: SettingsBackup(aiSettings: ai, profile: profile, storage: storage))
    }

    @Test func theFileHoldsTheSettingsButNoKey() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeMac(root: root)
        mac.ai.configuration = AIEndpointConfiguration(preset: .custom, baseURL: "https://ai.example.com/v1", modelChoice: .specific("modell-1"))
        mac.profile.namesText = "Ada Ek, Ada"

        mac.backup.writeNow()

        let text = try String(contentsOf: SettingsFile.url(in: root), encoding: .utf8)
        #expect(text.contains("https://ai.example.com/v1"))
        #expect(text.contains("Ada Ek, Ada"))
        #expect(!text.lowercased().contains("key"))
        #expect(SettingsFile.read(in: root)?.ai == mac.ai.configuration)
    }

    @Test func aNewMacAsksBeforeRestoring() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = AppSettingsSnapshot(ai: AIEndpointConfiguration(preset: .openRouter), myNames: "Ada")
        try SettingsFile.write(saved, in: root)

        let mac = makeMac(root: root)
        mac.backup.start()
        #expect(mac.ai.configuration == .default)
        #expect(SettingsFile.read(in: root) == saved)

        mac.backup.folderDidChange()
        #expect(mac.backup.pendingRestore == saved)
        #expect(mac.ai.configuration == .default)

        // Nothing replaces the file while the user decides.
        mac.backup.writeNow()
        #expect(SettingsFile.read(in: root) == saved)

        mac.backup.restore()
        #expect(mac.ai.configuration == saved.ai)
        #expect(mac.profile.namesText == "Ada")
        #expect(mac.backup.pendingRestore == nil)
    }

    @Test func decliningKeepsTheCurrentSettings() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try SettingsFile.write(AppSettingsSnapshot(ai: AIEndpointConfiguration(preset: .openRouter), myNames: "Ada"), in: root)
        let mac = makeMac(root: root)

        mac.backup.offerRestore()
        mac.backup.cancelRestore()

        #expect(mac.backup.pendingRestore == nil)
        #expect(mac.ai.configuration == .default)
    }

    @Test func aFolderWithoutAFileGetsTheCurrentSettings() {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeMac(root: root)
        mac.profile.namesText = "Bo"

        mac.backup.folderDidChange()

        #expect(mac.backup.pendingRestore == nil)
        #expect(SettingsFile.read(in: root)?.myNames == "Bo")
    }

    @Test(arguments: [
        "inte json",
        #"{"version": 99, "myNames": "", "ai": {"preset": "openAI", "baseURL": "https://api.openai.com/v1", "authStyle": "bearer", "modelChoice": {"latest": {}}}}"#,
        #"{"version": 1, "myNames": "", "ai": {"preset": "custom", "baseURL": "http://attacker.example.com/v1", "authStyle": "bearer", "modelChoice": {"latest": {}}}}"#,
    ])
    func unusableFilesAreNotOffered(text: String) throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try text.write(to: SettingsFile.url(in: root), atomically: true, encoding: .utf8)

        #expect(SettingsFile.read(in: root) == nil)
    }

    @Test func aNewMacGetsAllTasksBackFromTheFolder() async throws {
        let oldRoot = temporaryFolder()
        let newRoot = temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }
        let source = NoteStore(storage: LocalStorageService(rootURL: oldRoot))
        await source.load()
        source.addProtocol(Note(
            folderID: NoteFolder.meetingProtocolsName,
            sourceNoteID: UUID(),
            actionItems: [ActionItem(source: "Ett", task: "Ett", note: "Notering", subtasks: [.init(title: "Steg", isDone: true)])],
            document: NoteDocument(blocks: [.paragraph(.title, "Protokoll")])
        ))
        source.addManualActionItem(ActionItem(source: "Egen", task: "Egen", isBacklog: true))
        await source.prepareForTermination()

        // The new Mac starts empty, and the user picks the folder from the old one.
        let newMac = NoteStore(storage: LocalStorageService(rootURL: newRoot))
        await newMac.load()
        try await newMac.moveLibrary(to: LocalStorageService(rootURL: oldRoot))

        let items = newMac.actionItemRows.map(\.item)
        #expect(Set(items.map(\.task)) == ["Ett", "Egen"])
        #expect(items.first { $0.task == "Ett" }?.note == "Notering")
        #expect(items.first { $0.task == "Ett" }?.subtasks.first?.isDone == true)
        #expect(items.first { $0.task == "Egen" }?.isBacklog == true)
    }
}
