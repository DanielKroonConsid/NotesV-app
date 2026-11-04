import SwiftUI

/// A window for reading and editing one protocol. Edits are saved automatically, as in the main window.
struct ProtocolWindowView: View {
    static let windowID = "meeting-protocol"

    let noteID: UUID?

    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        if let note = noteID.flatMap({ store.notes[$0] }) {
            NoteEditorView(note: note, focusOnLoad: false) { document in
                store.updateDocument(document, of: note.id)
            }
            .navigationTitle(Text(verbatim: note.title))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        EmailClipboard.copy(note.document)
                        didCopy = true
                    } label: {
                        Label("Copy for Email", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .help(Text("Copy the whole protocol, ready to paste into an email"))
                    .task(id: didCopy) {
                        guard didCopy else { return }
                        try? await Task.sleep(for: .seconds(2))
                        didCopy = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    SentButton(note: note)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.deleteNote(note.id)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .help(Text("Delete"))
                }
            }
        } else if store.isLoaded {
            Text("This protocol no longer exists.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
