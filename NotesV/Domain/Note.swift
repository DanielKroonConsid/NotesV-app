import Foundation

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
    /// The meeting the note was written for.
    var meeting: MeetingDetails?
    var document: NoteDocument

    init(
        id: UUID = UUID(),
        folderID: NoteFolder.ID,
        created: Date = .nowWholeSeconds,
        modified: Date = .nowWholeSeconds,
        isPinned: Bool = false,
        meeting: MeetingDetails? = nil,
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

    /// The first line of the note, or the meeting title if the note has no text yet.
    var title: String {
        let title = document.title
        return title.isEmpty ? meeting?.title ?? "" : title
    }

    /// A note with only a meeting is worth keeping, so it isn't discarded as empty.
    var hasContent: Bool {
        document.hasContent || meeting != nil
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchable = [document.plainText, meeting?.title ?? ""]
        return searchable.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

extension Date {
    /// The current time without fractional seconds, so dates survive a round trip through the
    /// front matter unchanged.
    static var nowWholeSeconds: Date {
        Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    }
}
