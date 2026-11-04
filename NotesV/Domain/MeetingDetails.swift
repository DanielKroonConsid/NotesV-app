import Foundation

/// The facts about a meeting that the protocol is based on.
///
/// Imported from an `.ics` file or entered by hand. Later they can also be read from the Outlook calendar.
struct MeetingDetails: Hashable, Sendable, Codable {
    /// The Outlook event id. `nil` until the Outlook calendar is connected.
    var eventID: String?
    var title: String
    var start: Date
    var end: Date?
    var location: String = ""
    var organizer: String = ""
    /// The people who were invited.
    var attendees: [String] = []
    var agenda: String = ""

    /// Whether nothing but the start time is filled in.
    var isEmpty: Bool {
        title.isEmpty && location.isEmpty && organizer.isEmpty && attendees.isEmpty && agenda.isEmpty
    }
}

/// The language a protocol is written in.
enum ProtocolLanguage: String, CaseIterable, Hashable, Sendable {
    /// The same language as the user's notes.
    case automatic
    case swedish = "sv"
    case english = "en"
}
