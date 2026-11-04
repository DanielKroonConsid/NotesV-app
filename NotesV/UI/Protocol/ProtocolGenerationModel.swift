import Foundation
import Observation

/// Runs protocol generation for the Generate Protocol sheet.
@MainActor
@Observable
final class ProtocolGenerationModel {
    /// The note with the meeting notes. The sheet is shown while this is set.
    var sourceNoteID: UUID?
    /// Whether the meeting popover in the toolbar is open.
    var isMeetingFormPresented = false
    private(set) var isGenerating = false
    var errorMessage: String?
    /// Shown after a protocol was created, e.g. when an older model had to be used.
    var warning: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Opens the sheet, or the meeting popover if the note has no meeting title yet.
    func requestProtocol(for note: Note) {
        if note.meeting?.title.isEmpty == false {
            sourceNoteID = note.id
        } else {
            isMeetingFormPresented = true
        }
    }

    func start(language: ProtocolLanguage, store: NoteStore, settings: AISettings) {
        guard let sourceNoteID, let sourceNote = store.notes[sourceNoteID], let meeting = sourceNote.meeting,
              !isGenerating else { return }
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
                    meeting: meeting,
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
