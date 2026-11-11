import AppKit
import SwiftUI

@main
struct NotesVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.store)
                .environment(appDelegate.aiSettings)
                .environment(appDelegate.protocolGeneration)
                .environment(appDelegate.meetingImport)
                .environment(appDelegate.profileSettings)
                .frame(minWidth: 760, minHeight: 420)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            NotesCommands(store: appDelegate.store, protocolGeneration: appDelegate.protocolGeneration)
        }

        WindowGroup("Meeting Protocol", id: ProtocolWindowView.windowID, for: UUID.self) { $noteID in
            ProtocolWindowView(noteID: noteID)
                .environment(appDelegate.store)
                .frame(minWidth: 420, minHeight: 360)
        }
        .defaultSize(width: 680, height: 760)

        Settings {
            SettingsView()
                .environment(appDelegate.aiSettings)
                .environment(appDelegate.storageSettings)
                .environment(appDelegate.profileSettings)
                .environment(appDelegate.settingsBackup)
                .environment(appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    let aiSettings: AISettings
    let storageSettings: StorageSettings
    let profileSettings: ProfileSettings
    let settingsBackup: SettingsBackup
    let protocolGeneration = ProtocolGenerationModel()
    let meetingImport = MeetingImportModel()

    override init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Tests run inside the app; keep them away from the user's notes and settings.
            let rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesV-TestHost-\(UUID().uuidString)")
            storageSettings = StorageSettings(defaultRootURL: rootURL, defaultsSuiteName: "NotesV-TestHost")
            aiSettings = AISettings(
                keychain: KeychainService(service: "se.consid.NotesV.test-host"),
                defaultsSuiteName: "NotesV-TestHost"
            )
            profileSettings = ProfileSettings(defaultsSuiteName: "NotesV-TestHost")
        } else {
            aiSettings = AISettings()
            profileSettings = ProfileSettings()
            // Never a temporary folder as a fallback: macOS empties those, and the notes with them.
            storageSettings = StorageSettings(defaultRootURL: LocalStorageService.defaultRootURL())
        }
        store = NoteStore(storage: LocalStorageService(rootURL: storageSettings.rootURL))
        settingsBackup = SettingsBackup(aiSettings: aiSettings, profile: profileSettings, storage: storageSettings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        Task {
            await store.load()
            settingsBackup.start()
            if storageSettings.isFolderMissing {
                store.errorMessage = String(localized: "The notes folder can’t be found. NotesV is using the folder on this Mac until you choose a new one in Settings.")
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task {
            await store.refresh()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let unsavedCount = await store.prepareForTermination()
            settingsBackup.writeNow()
            sender.reply(toApplicationShouldTerminate: unsavedCount == 0 || confirmQuitWithUnsavedNotes(unsavedCount))
        }
        return .terminateLater
    }

    /// Asks before quitting with notes that couldn't be saved, since their changes would be lost.
    private func confirmQuitWithUnsavedNotes(_ count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "\(count) notes couldn’t be saved.")
        var details = [String(localized: "If you quit now, the changes in them are lost. Cancel to keep NotesV open and copy the text somewhere else, or check that the notes folder is available.")]
        if let errorMessage = store.errorMessage {
            details.insert(errorMessage, at: 0)
        }
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}
