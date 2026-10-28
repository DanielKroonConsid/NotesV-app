import Foundation
import Observation

/// Runs protocol generation for the Generate Protocol sheet.
@MainActor
@Observable
final class ProtocolGenerationModel {
    /// The note with the meeting notes. The sheet is shown while this is set.
    var sourceNoteID: UUID?
    private(set) var isGenerating = false
    var errorMessage: String?
    /// Shown after a protocol was created, e.g. when an older model had to be used.
    var warning: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(meeting: MeetingDetails, language: ProtocolLanguage, store: NoteStore, settings: AISettings) {
        guard let sourceNoteID, let sourceNote = store.notes[sourceNoteID], !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        task = Task {
            defer { isGenerating = false }
            do {
                let generator = try settings.makeGenerator()
                let result = try await generator.generateProtocol(
                    meeting: meeting, notes: sourceNote.document, language: language
                )
                let protocolNote = Note(
                    folderID: sourceNote.folderID,
                    // A manually entered meeting has no Outlook event id yet.
                    meeting: MeetingReference(eventID: "", subject: meeting.title, start: meeting.start),
                    document: ProtocolFormatter.document(for: result.minutes, meeting: meeting)
                )
                store.addNote(protocolNote)
                warning = result.warning
                self.sourceNoteID = nil
            } catch is CancellationError {
                // The user cancelled; keep the sheet open.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
