import SwiftUI

/// Confirms the meeting and language, and creates a protocol note from the selected note.
struct GenerateProtocolSheet: View {
    let note: Note

    @Environment(NoteStore.self) private var store
    @Environment(AISettings.self) private var settings
    @Environment(ProtocolGenerationModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    @State private var language = ProtocolLanguage.automatic

    var body: some View {
        if let meeting = note.meeting, let minutes = model.pendingMinutes {
            ActionItemsReview(
                minutes: Binding(get: { model.pendingMinutes ?? minutes }, set: { model.pendingMinutes = $0 }),
                meeting: meeting,
                onCreate: { model.createProtocol(store: store) },
                onCancel: { model.discardPendingProtocol() }
            )
        } else {
            generateView
        }
    }

    private var generateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate Protocol")
                .font(.headline)

            Form {
                if let meeting = note.meeting {
                    LabeledContent("Meeting") {
                        Text(verbatim: meeting.title)
                    }
                    LabeledContent("Start") {
                        Text(verbatim: meeting.start.formatted(date: .long, time: .shortened))
                    }
                }
                Picker("Language", selection: $language) {
                    Text("Same as the notes").tag(ProtocolLanguage.automatic)
                    Text(verbatim: "Svenska").tag(ProtocolLanguage.swedish)
                    Text(verbatim: "English").tag(ProtocolLanguage.english)
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
                    model.start(language: language, store: store, settings: settings)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isGenerating)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(model.isGenerating)
        .onAppear { model.errorMessage = nil }
    }
}
