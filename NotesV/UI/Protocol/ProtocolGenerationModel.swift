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
    /// A generated protocol waiting for the user to match its action items.
    var pendingMinutes: MeetingProtocol?
    /// A newly created protocol that should open in its own window.
    var createdProtocolID: UUID?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Held back until the sheet has closed, because an alert can't show on top of it.
    @ObservationIgnored private var pendingWarning: String?

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
                pendingWarning = result.warning
                pendingMinutes = result.minutes
                if result.minutes.actionItems.isEmpty {
                    createProtocol(store: store)
                }
            } catch is CancellationError {
                // The user cancelled; keep the sheet open.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Creates the protocol note from the reviewed result.
    func createProtocol(store: NoteStore) {
        guard let minutes = pendingMinutes, let sourceNoteID, let sourceNote = store.notes[sourceNoteID],
              let meeting = sourceNote.meeting else { return }
        let protocolNote = Note(
            folderID: NoteFolder.meetingProtocolsName,
            meeting: meeting,
            sourceNoteID: sourceNote.id,
            document: ProtocolFormatter.document(for: minutes, meeting: meeting)
        )
        store.addProtocol(protocolNote)
        createdProtocolID = protocolNote.id
        warning = pendingWarning
        pendingWarning = nil
        pendingMinutes = nil
        self.sourceNoteID = nil
    }

    /// Throws away a generated protocol that hasn't been created yet.
    func discardPendingProtocol() {
        pendingMinutes = nil
        pendingWarning = nil
    }

    func cancel() {
        task?.cancel()
    }
}
