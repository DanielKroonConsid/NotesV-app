import Foundation
import Observation

/// Imports a meeting from an `.ics` file into a note.
@MainActor
@Observable
final class MeetingImportModel {
    /// The events to choose between when a file holds several.
    private(set) var eventChoices: [ICSEvent] = []
    private(set) var errorMessage: String?
    /// Asks the user to check something about the imported meeting.
    private(set) var warnings: [String] = []

    func importFile(at url: URL, into noteID: UUID, store: NoteStore) {
        clearMessages()
        // Needed for files from the open panel; dragged files already have access.
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ICSParser.maximumFileSize {
                throw ICSParser.ParseError.fileTooLarge
            }
            let events = try ICSParser.parse(data: Data(contentsOf: url))
            if events.count == 1 {
                apply(events[0], to: noteID, store: store)
            } else {
                eventChoices = events
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func apply(_ event: ICSEvent, to noteID: UUID, store: NoteStore) {
        eventChoices = []
        store.updateMeeting(event.details, of: noteID)

        warnings = []
        if event.isRecurring {
            warnings.append(String(localized: "This is a recurring meeting. The file gives the first occurrence, so check the date."))
        }
        if event.usedFallbackTimeZone {
            warnings.append(String(localized: "The file’s time zone is unknown, so the time was read as local time. Check the time."))
        }
    }

    func clearMessages() {
        eventChoices = []
        errorMessage = nil
        warnings = []
    }

    /// Whether the popover must open so the user sees a choice or a message.
    var needsAttention: Bool {
        !eventChoices.isEmpty || errorMessage != nil || !warnings.isEmpty
    }
}
