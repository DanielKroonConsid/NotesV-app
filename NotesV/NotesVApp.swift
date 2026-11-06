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
                .environment(appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    let aiSettings: AISettings
    let storageSettings: StorageSettings
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
        } else {
            aiSettings = AISettings()
            let rootURL = (try? LocalStorageService.defaultRootURL())
                ?? FileManager.default.temporaryDirectory.appending(path: "NotesV")
            storageSettings = StorageSettings(defaultRootURL: rootURL)
        }
        store = NoteStore(storage: LocalStorageService(rootURL: storageSettings.rootURL))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        Task {
            await store.load()
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
            await store.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
