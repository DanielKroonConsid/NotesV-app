import SwiftUI

/// The three-column Notes layout: folders, note list and editor.
struct ContentView: View {
    @Environment(NoteStore.self) private var store
    @Environment(ProtocolGenerationModel.self) private var protocolGeneration

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            FolderSidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            NoteDetailView()
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: Text("Search"))
        .confirmationDialog(
            "Delete this note permanently?",
            isPresented: Binding(
                get: { store.notePendingPermanentDeletion != nil },
                set: { if !$0 { store.notePendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { store.confirmPermanentDeletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can’t undo this action.")
        }
        .sheet(isPresented: Binding(
            get: { protocolGeneration.sourceNoteID != nil },
            set: { if !$0 { protocolGeneration.sourceNoteID = nil } }
        )) {
            if let noteID = protocolGeneration.sourceNoteID, let note = store.notes[noteID] {
                GenerateProtocolSheet(note: note)
            }
        }
        .alert(
            "Protocol created",
            isPresented: Binding(
                get: { protocolGeneration.warning != nil },
                set: { if !$0 { protocolGeneration.warning = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: protocolGeneration.warning ?? "")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
    }
}

/// The editor for the selected note, with the Notes formatting toolbar.
struct NoteDetailView: View {
    @Environment(NoteStore.self) private var store
    @Environment(ProtocolGenerationModel.self) private var protocolGeneration

    var body: some View {
        Group {
            if let note = store.selectedNote {
                NoteEditorView(note: note, focusOnLoad: store.noteToFocus == note.id) { document in
                    store.updateDocument(document, of: note.id)
                }
            } else {
                Text("No Note Selected")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    FormatMenuContent(includesShortcuts: false)
                } label: {
                    Label("Format", systemImage: "textformat")
                }
                .help(Text("Format"))
                Button {
                    EditorAction.send(#selector(NotesTextView.toggleChecklist(_:)))
                } label: {
                    Label("Checklist", systemImage: "checklist")
                }
                .help(Text("Checklist"))
                Button {
                    EditorAction.send(#selector(NotesTextView.insertNotesTable(_:)))
                } label: {
                    Label("Table", systemImage: "tablecells")
                }
                .help(Text("Table"))
                Button {
                    protocolGeneration.sourceNoteID = store.selectedNoteID
                } label: {
                    Label("Generate Protocol", systemImage: "sparkles")
                }
                .help(Text("Generate a meeting protocol from this note"))
                .disabled(store.selectedNote?.document.hasContent != true)
            }
        }
        .disabled(store.selectedNote == nil)
    }
}
