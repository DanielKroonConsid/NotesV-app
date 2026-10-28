import SwiftUI

/// Asks for the meeting details and creates a protocol note from the selected note.
struct GenerateProtocolSheet: View {
    let note: Note

    @Environment(NoteStore.self) private var store
    @Environment(AISettings.self) private var settings
    @Environment(ProtocolGenerationModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    @State private var title = ""
    @State private var start = Date.now
    @State private var hasEnd = true
    @State private var end = Date.now.addingTimeInterval(3600)
    @State private var location = ""
    @State private var organizer = ""
    @State private var attendees = ""
    @State private var agenda = ""
    @State private var language = ProtocolLanguage.automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate Protocol")
                .font(.headline)

            Form {
                Section("Meeting") {
                    TextField("Title", text: $title)
                    DatePicker("Start", selection: $start)
                    Toggle("End time", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("End", selection: $end, in: start...)
                    }
                    TextField("Location", text: $location, prompt: Text("Room or meeting link"))
                    TextField("Organizer", text: $organizer)
                    TextField("Attendees", text: $attendees, prompt: Text("Comma-separated names"))
                    TextField("Agenda", text: $agenda, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Language", selection: $language) {
                        Text("Same as the notes").tag(ProtocolLanguage.automatic)
                        Text(verbatim: "Svenska").tag(ProtocolLanguage.swedish)
                        Text(verbatim: "English").tag(ProtocolLanguage.english)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(model.isGenerating)

            Group {
                if settings.configuration.isLocal {
                    Text("The notes are sent to a server on this Mac.")
                } else {
                    Text("The notes are sent to \(settings.configuration.endpointID), outside your Microsoft 365 organization.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage = model.errorMessage {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(verbatim: errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Open Settings…") { openSettings() }
                }
                .font(.callout)
            }

            HStack {
                if model.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Writing the protocol…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    if model.isGenerating {
                        model.cancel()
                    } else {
                        model.errorMessage = nil
                        model.sourceNoteID = nil
                    }
                }
                .keyboardShortcut(.cancelAction)
                Button("Generate") {
                    model.start(meeting: meetingDetails, language: language, store: store, settings: settings)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || model.isGenerating)
            }
        }
        .padding(20)
        .frame(width: 500)
        .interactiveDismissDisabled(model.isGenerating)
        .onAppear(perform: prefill)
    }

    private var meetingDetails: MeetingDetails {
        MeetingDetails(
            title: title.trimmingCharacters(in: .whitespaces),
            start: start,
            end: hasEnd ? end : nil,
            location: location.trimmingCharacters(in: .whitespaces),
            organizer: organizer.trimmingCharacters(in: .whitespaces),
            attendees: attendees.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            agenda: agenda.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func prefill() {
        model.errorMessage = nil
        if let meeting = note.meeting {
            title = meeting.subject
            start = meeting.start
            end = meeting.start.addingTimeInterval(3600)
        } else {
            title = note.document.title
        }
    }
}
