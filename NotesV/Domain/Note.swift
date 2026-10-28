import Foundation

/// A link from a note to the Outlook meeting it was written for.
struct MeetingReference: Hashable, Sendable {
    var eventID: String
    var subject: String
    var start: Date
}

struct NoteFolder: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case regular
        case recentlyDeleted
    }

    /// The folder name that new installations start with.
    static let defaultName = "Notes"
    /// The name of the folder that deleted notes are moved to.
    static let recentlyDeletedName = "Recently Deleted"

    /// A folder is identified by its name, which is also its directory name in storage.
    var id: String { name }
    var name: String

    var kind: Kind {
        name == Self.recentlyDeletedName ? .recentlyDeleted : .regular
    }
}

struct Note: Identifiable, Hashable, Sendable {
    let id: UUID
    var folderID: NoteFolder.ID
    var created: Date
    var modified: Date
    var isPinned: Bool
    var meeting: MeetingReference?
    var document: NoteDocument

    init(
        id: UUID = UUID(),
        folderID: NoteFolder.ID,
        created: Date = .nowWholeSeconds,
        modified: Date = .nowWholeSeconds,
        isPinned: Bool = false,
        meeting: MeetingReference? = nil,
        document: NoteDocument = .newNote
    ) {
        self.id = id
        self.folderID = folderID
        self.created = created
        self.modified = modified
        self.isPinned = isPinned
        self.meeting = meeting
        self.document = document
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return document.plainText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension Date {
    /// The current time without fractional seconds, so dates survive a round trip through the
    /// front matter unchanged.
    static var nowWholeSeconds: Date {
        Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    }
}
