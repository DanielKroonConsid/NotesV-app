import SwiftUI

/// The folder list in the first column.
struct FolderSidebarView: View {
    @Environment(NoteStore.self) private var store
    @State private var newFolderName = ""
    @State private var folderBeingRenamed: NoteFolder?
    @State private var renamedFolderName = ""
    @State private var folderBeingDeleted: NoteFolder?
    @State private var hoveredFolderID: NoteFolder.ID?

    private static let subfolderIndent: CGFloat = 16

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedFolderID) {
            Section("On My Mac") {
                ForEach(store.sidebarFolders) { folder in
                    FolderRow(folder: folder)
                        .padding(.leading, folder.isSubfolder ? Self.subfolderIndent : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                hoveredFolderID = folder.id
                            } else if hoveredFolderID == folder.id {
                                hoveredFolderID = nil
                            }
                        }
                        .badge(badgeCount(for: folder))
                        .tag(folder.id)
                        .contextMenu {
                            if folder.isSubfolder {
                                Button("Rename Folder…") {
                                    renamedFolderName = folder.name
                                    folderBeingRenamed = folder
                                }
                                Button("Delete Folder", role: .destructive) {
                                    folderBeingDeleted = folder
                                }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                newFolderName = ""
                store.isCreatingFolder = true
            } label: {
                Label("New Folder", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .alert("New Folder", isPresented: $store.isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { store.createFolder(named: newFolderName) }
        }
        .alert(
            "Rename Folder",
            isPresented: Binding(get: { folderBeingRenamed != nil }, set: { if !$0 { folderBeingRenamed = nil } })
        ) {
            TextField("Name", text: $renamedFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let folder = folderBeingRenamed {
                    store.renameFolder(folder.id, to: renamedFolderName)
                }
            }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(get: { folderBeingDeleted != nil }, set: { if !$0 { folderBeingDeleted = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderBeingDeleted {
                    store.deleteFolder(folder.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The notes in the folder will be moved to Recently Deleted.")
        }
    }

    /// What needs attention: unsent protocols and new tasks. The total shows on hover.
    private func badgeCount(for folder: NoteFolder) -> Int {
        let isHovered = hoveredFolderID == folder.id
        if folder.kind == .actionItems {
            return isHovered ? store.openActionItemCount : store.newActionItemCount
        }
        return isHovered ? store.noteCount(in: folder.id) : store.unsentProtocolCount(in: folder.id)
    }
}

private struct FolderRow: View {
    let folder: NoteFolder

    var body: some View {
        switch folder.kind {
        case .recentlyDeleted:
            Label("Recently Deleted", systemImage: "trash")
        case .meetingProtocols:
            Label("Meeting Protocols", systemImage: "doc.text")
        case .actionItems, .manualTasks:
            Label("Tasks", systemImage: "checklist")
        case .sent:
            Label("Sent Notes", systemImage: "paperplane")
        case .regular where folder.name == NoteFolder.defaultName:
            Label("Notes", systemImage: "folder")
        case .regular:
            Label(folder.name, systemImage: "folder")
        }
    }
}
