import Foundation

struct NoteFolder: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case regular
        case meetingProtocols
        case actionItems
        case taskFiles
        case manualTasks
        case sent
        case recentlyDeleted
    }

    /// The directory with one file per task. The Tasks view shows them, not the folder list.
    static let tasksName = "Tasks"
    /// Where earlier versions kept manual tasks. `NoteStore` moves them to `tasksName`.
    static let manualTasksName = "Manual Tasks"
    /// The folder name that new installations start with.
    static let defaultName = "Notes"
    /// The name of the folder that deleted notes are moved to.
    static let recentlyDeletedName = "Recently Deleted"
    /// The name of the folder that generated meeting protocols are stored in.
    static let meetingProtocolsName = "Meeting Protocols"
    /// The view that collects all sent notes. It isn't a directory, and sent notes stay in their
    /// folder on disk. The leading dot can't clash with a real folder, which never has one.
    static let sent = NoteFolder(name: ".sent")
    /// The overview of the tasks in all protocols. Like `sent`, it isn't a directory.
    static let actionItems = NoteFolder(name: ".tasks")

    /// A folder is identified by its name, which is also its directory name in storage.
    var id: String { name }
    var name: String

    var kind: Kind {
        switch name {
        case Self.recentlyDeletedName: .recentlyDeleted
        case Self.meetingProtocolsName: .meetingProtocols
        case Self.sent.name: .sent
        case Self.actionItems.name: .actionItems
        case Self.tasksName: .taskFiles
        case Self.manualTasksName: .manualTasks
        default: .regular
        }
    }

    /// A folder the user created, which the sidebar shows under Notes.
    var isSubfolder: Bool {
        kind == .regular && name != Self.defaultName
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
    /// For a meeting protocol: the note it is attached to.
    var sourceNoteID: UUID?
    /// When the user marked the note as sent. `nil` if it isn't marked.
    var sentAt: Date?
    /// Set if this note is a task's file. Its title, note and subtasks are also the document.
    var task: ActionItem?
    /// Tasks stored by earlier versions, until `NoteStore` has moved them to files of their own.
    var actionItems: [ActionItem]
    /// Front matter NotesV doesn't use, such as another app's `tags`. It is written back unchanged.
    var extraFrontMatter: [FrontMatter.RawEntry]
    var document: NoteDocument

    init(
        id: UUID = UUID(),
        folderID: NoteFolder.ID,
        created: Date = .nowWholeSeconds,
        modified: Date = .nowWholeSeconds,
        isPinned: Bool = false,
        meeting: MeetingDetails? = nil,
        sourceNoteID: UUID? = nil,
        sentAt: Date? = nil,
        task: ActionItem? = nil,
        actionItems: [ActionItem] = [],
        extraFrontMatter: [FrontMatter.RawEntry] = [],
        document: NoteDocument = .newNote
    ) {
        self.id = id
        self.folderID = folderID
        self.created = created
        self.modified = modified
        self.isPinned = isPinned
        self.meeting = meeting
        self.sourceNoteID = sourceNoteID
        self.sentAt = sentAt
        self.task = task
        self.actionItems = actionItems
        self.extraFrontMatter = extraFrontMatter
        self.document = document
    }

    /// The file of a task.
    static func taskFile(_ item: ActionItem, id: UUID = UUID(), created: Date = .nowWholeSeconds) -> Note {
        Note(id: id, folderID: NoteFolder.tasksName, created: created, modified: created, task: item, document: item.document)
    }

    /// The list of manual tasks that earlier versions kept. A folder is checked, so that a copy
    /// kept after a conflict with the file is moved too.
    var holdsManualTasks: Bool {
        folderID == NoteFolder.manualTasksName
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

    /// A generated protocol. Older protocols have no link to a note, but are in the protocols folder.
    var isMeetingProtocol: Bool {
        sourceNoteID != nil || folderID == NoteFolder.meetingProtocolsName
    }

    /// Only protocols can be sent. An ordinary note marked by an earlier version counts as not sent.
    var isSent: Bool {
        sentAt != nil && isMeetingProtocol
    }

    /// A protocol needs written notes to work from, and isn't made from another protocol.
    var canGenerateProtocol: Bool {
        document.hasContent && sourceNoteID == nil
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
