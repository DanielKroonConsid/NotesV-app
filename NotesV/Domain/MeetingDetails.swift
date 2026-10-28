import Foundation

/// The facts about a meeting that the protocol is based on.
///
/// Entered by hand for now. Later they will be read from the Outlook calendar.
struct MeetingDetails: Hashable, Sendable, Codable {
    var title: String
    var start: Date
    var end: Date?
    var location: String = ""
    var organizer: String = ""
    /// The people who were invited.
    var attendees: [String] = []
    var agenda: String = ""
}

/// The language a protocol is written in.
enum ProtocolLanguage: String, CaseIterable, Hashable, Sendable {
    /// The same language as the user's notes.
    case automatic
    case swedish = "sv"
    case english = "en"
}
