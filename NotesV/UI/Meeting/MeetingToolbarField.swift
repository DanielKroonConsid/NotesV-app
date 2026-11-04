import SwiftUI
import UniformTypeIdentifiers

/// The meeting field in the toolbar. Takes an `.ics` file, and a click opens the meeting details.
struct MeetingToolbarField: View {
    @Environment(NoteStore.self) private var store
    @Environment(ProtocolGenerationModel.self) private var protocolGeneration
    @Environment(MeetingImportModel.self) private var meetingImport
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var protocolGeneration = protocolGeneration

        Button {
            protocolGeneration.isMeetingFormPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                fieldText
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: 240)
            .background(.quaternary.opacity(isDropTargeted ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Add a meeting from an .ics file, or enter it by hand"))
        .accessibilityLabel(Text("Meeting"))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "ics" }),
                  let noteID = store.selectedNoteID else { return false }
            meetingImport.importFile(at: url, into: noteID, store: store)
            if meetingImport.needsAttention {
                protocolGeneration.isMeetingFormPresented = true
            }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onChange(of: store.selectedNoteID) { meetingImport.clearMessages() }
        .popover(isPresented: $protocolGeneration.isMeetingFormPresented, arrowEdge: .bottom) {
            if let noteID = store.selectedNoteID {
                MeetingDetailsForm(noteID: noteID)
            }
        }
    }

    @ViewBuilder
    private var fieldText: some View {
        if let meeting = store.selectedNote?.meeting {
            let date = meeting.start.formatted(date: .abbreviated, time: .shortened)
            Text(verbatim: meeting.title.isEmpty ? date : "\(meeting.title) · \(date)")
        } else {
            Text("Add meeting (.ics)")
                .foregroundStyle(.secondary)
        }
    }
}
