import SwiftUI

/// Shows the protocols attached to a note, or the note a protocol is attached to.
struct NoteAttachmentsBar: View {
    let note: Note

    @Environment(NoteStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let attachments = store.attachments(of: note.id)
        let source = note.sourceNoteID.flatMap { store.notes[$0] }

        if !attachments.isEmpty || source != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let source {
                        Button {
                            store.reveal(source.id)
                        } label: {
                            Label {
                                Text("Attached to “\(source.title)”")
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                    }
                    ForEach(attachments) { attachment in
                        Button {
                            openWindow(id: ProtocolWindowView.windowID, value: attachment.id)
                        } label: {
                            Label {
                                Text(verbatim: attachment.title)
                            } icon: {
                                Image(systemName: attachment.sentAt == nil ? "paperclip" : "paperplane.fill")
                            }
                        }
                        .help(Text("Open the protocol"))
                        .contextMenu {
                            Button("Open the protocol") {
                                openWindow(id: ProtocolWindowView.windowID, value: attachment.id)
                            }
                            Button("Copy for Email") {
                                EmailClipboard.copy(attachment.document)
                            }
                            Button(attachment.sentAt == nil ? "Mark as Sent" : "Mark as Not Sent") {
                                store.toggleSent(attachment.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.deleteNote(attachment.id)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
        }
    }
}
