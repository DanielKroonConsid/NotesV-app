import AppKit
import SwiftUI

@main
struct NotesVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.store)
                .frame(minWidth: 760, minHeight: 420)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            NotesCommands(store: appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore

    override init() {
        let rootURL: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Tests run inside the app; keep them away from the user's notes.
            rootURL = FileManager.default.temporaryDirectory.appending(path: "NotesV-TestHost-\(UUID().uuidString)")
        } else {
            rootURL = (try? LocalStorageService.defaultRootURL())
                ?? FileManager.default.temporaryDirectory.appending(path: "NotesV")
        }
        store = NoteStore(storage: LocalStorageService(rootURL: rootURL))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        Task {
            await store.load()
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
