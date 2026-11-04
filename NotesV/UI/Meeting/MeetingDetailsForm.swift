import SwiftUI
import UniformTypeIdentifiers

/// Imports an `.ics` file and shows the note's meeting details. Edits are saved as you type.
struct MeetingDetailsForm: View {
    let noteID: UUID

    @Environment(NoteStore.self) private var store
    @Environment(MeetingImportModel.self) private var meetingImport
    @State private var isImporting = false
    @State private var attendeesText = ""
    /// The start time used until the note has a meeting.
    @State private var defaultStart = Date.nowWholeSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose .ics File…") { isImporting = true }
                Spacer()
                Button("Clear", role: .destructive) {
                    meetingImport.clearMessages()
                    store.updateMeeting(nil, of: noteID)
                }
                .disabled(store.notes[noteID]?.meeting == nil)
            }

            messages

            if !meetingImport.eventChoices.isEmpty {
                eventChoices
            } else {
                form
            }
        }
        .padding(16)
        .frame(width: 400)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.calendarTypes) { result in
            switch result {
            case .success(let url): meetingImport.importFile(at: url, into: noteID, store: store)
            case .failure: break // The user cancelled, or the panel already showed the problem.
            }
        }
        .onAppear { attendeesText = details.attendees.joined(separator: ", ") }
        .onChange(of: details.attendees) { _, attendees in
            // An import replaces the list. Typing must not, or ", " would vanish while typing.
            if Self.names(in: attendeesText) != attendees {
                attendeesText = attendees.joined(separator: ", ")
            }
        }
    }

    private static let calendarTypes = [UTType(filenameExtension: "ics") ?? .calendarEvent]

    private static func names(in text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var details: MeetingDetails {
        store.notes[noteID]?.meeting ?? MeetingDetails(title: "", start: defaultStart)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MeetingDetails, Value>) -> Binding<Value> {
        Binding(
            get: { details[keyPath: keyPath] },
            set: { value in
                var updated = details
                updated[keyPath: keyPath] = value
                store.updateMeeting(updated, of: noteID)
            }
        )
    }

    @ViewBuilder
    private var messages: some View {
        if let errorMessage = meetingImport.errorMessage {
            Label {
                Text(verbatim: errorMessage)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
        }
        ForEach(meetingImport.warnings, id: \.self) { warning in
            Label {
                Text(verbatim: warning)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var eventChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The file contains several meetings. Choose one.")
                .font(.callout)
            ForEach(meetingImport.eventChoices, id: \.self) { event in
                Button {
                    meetingImport.apply(event, to: noteID, store: store)
                } label: {
                    Text(verbatim: "\(event.details.title) · \(event.details.start.formatted(date: .abbreviated, time: .shortened))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Title", text: binding(\.title))
            DatePicker("Start", selection: binding(\.start))
            Toggle("End time", isOn: Binding(
                get: { details.end != nil },
                set: { binding(\.end).wrappedValue = $0 ? details.start.addingTimeInterval(3600) : nil }
            ))
            if let end = details.end {
                DatePicker("End", selection: Binding(
                    get: { end },
                    set: { binding(\.end).wrappedValue = $0 }
                ), in: details.start...)
            }
            TextField("Location", text: binding(\.location), prompt: Text("Room or meeting link"))
            TextField("Organizer", text: binding(\.organizer))
            TextField("Attendees", text: $attendeesText, prompt: Text("Comma-separated names"))
                .onChange(of: attendeesText) { _, text in
                    binding(\.attendees).wrappedValue = Self.names(in: text)
                }
            TextField("Agenda", text: binding(\.agenda), prompt: Text("Optional"), axis: .vertical)
                .lineLimit(2...6)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
