import AppKit
import SwiftUI

/// Lets the user pick the folder the notes are stored in.
struct StorageSettingsView: View {
    @Environment(StorageSettings.self) private var settings
    @Environment(NoteStore.self) private var store
    @Environment(SettingsBackup.self) private var backup

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes folder") {
                    if let folderURL = settings.folderURL {
                        Text(verbatim: StorageFolderBookmark.notesRoot(in: folderURL).path(percentEncoded: false))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } else {
                        Text("On this Mac")
                    }
                }

                HStack {
                    Button("Choose Folder…", action: chooseFolder)
                    if settings.folderURL != nil {
                        Button("Use This Mac") {
                            Task {
                                await settings.useThisMac(store: store)
                                backup.writeNow()
                            }
                        }
                    }
                    if settings.isMoving {
                        ProgressView().controlSize(.small)
                    }
                }
                .disabled(settings.isMoving)

                if settings.isFolderMissing {
                    Label("The chosen folder can’t be found. Choose a new one.", systemImage: "exclamationmark.triangle")
                }
                if let errorMessage = settings.errorMessage {
                    Label {
                        Text(verbatim: errorMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            } footer: {
                Text("Choose a folder that OneDrive or another service syncs to back up your notes and reach them on other Macs. NotesV copies the notes there and leaves the old files where they are. Notes that sync leave this Mac, including meeting details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Settings…") {
                    backup.offerRestore()
                }
                .disabled(backup.stored == nil)
                if let errorMessage = backup.errorMessage {
                    Label {
                        Text(verbatim: errorMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            } footer: {
                Text("Your settings are also saved as settings.json in the notes folder, so you can get them back on a new Mac. API keys are never saved there, so you enter them again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(
            "Restore settings from the notes folder?",
            isPresented: Binding(get: { backup.pendingRestore != nil }, set: { if !$0 { backup.cancelRestore() } }),
            presenting: backup.pendingRestore
        ) { _ in
            Button("Cancel", role: .cancel) { backup.cancelRestore() }
            Button("Restore") { backup.restore() }
        } message: { snapshot in
            Text("Meeting data will be sent to \(snapshot.ai.baseURL). Only restore if you recognize this server. Enter the API key again afterwards.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where to store your notes. NotesV creates a folder named NotesV there.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await settings.useFolder(url, store: store)
            backup.folderDidChange()
        }
    }
}
