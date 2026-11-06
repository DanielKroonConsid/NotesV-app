import Foundation

/// A task the user follows up on. It is stored in the front matter of the protocol it came from.
struct ActionItem: Hashable, Sendable {
    enum Status: String, Sendable {
        case open
        case done
        /// The user doesn't want this checkbox in the list, so it isn't suggested again.
        case ignored
    }

    /// A step of a task. The id only exists in memory, to keep rows apart while they are edited.
    struct Subtask: Identifiable, Hashable, Sendable {
        let id = UUID()
        var title: String
        var isDone: Bool

        init(title: String, isDone: Bool = false) {
            self.title = title
            self.isDone = isDone
        }

        /// Reads the form it has in the front matter: `[ ] title` or `[x] title`.
        init?(line: String) {
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix("[ ] ") || lowercased.hasPrefix("[x] ") else { return nil }
            self.init(title: String(line.dropFirst(4)), isDone: lowercased.hasPrefix("[x]"))
        }

        var line: String {
            "\(isDone ? "[x]" : "[ ]") \(title)"
        }

        static func == (lhs: Subtask, rhs: Subtask) -> Bool {
            lhs.title == rhs.title && lhs.isDone == rhs.isDone
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(isDone)
        }
    }

    /// The checkbox line in the protocol, which shows that it has been handled.
    var source: String
    var task: String
    /// The name of someone else. `nil` when the task is the user's own or has no owner.
    var owner: String?
    var isMine: Bool
    /// The start of the day the task is due.
    var dueDate: Date?
    /// A task for later. It has no due date, and is only listed in the backlog.
    var isBacklog: Bool
    /// Only for the user. It isn't part of the protocol's text.
    var note: String?
    var subtasks: [Subtask]
    var status: Status

    init(
        source: String,
        task: String,
        owner: String? = nil,
        isMine: Bool = false,
        dueDate: Date? = nil,
        isBacklog: Bool = false,
        note: String? = nil,
        subtasks: [Subtask] = [],
        status: Status = .open
    ) {
        self.source = source
        self.task = task
        self.owner = owner
        self.isMine = isMine
        self.dueDate = dueDate
        self.isBacklog = isBacklog
        self.note = note
        self.subtasks = subtasks
        self.status = status
    }

    /// The task without an empty note or empty subtasks, which aren't worth storing.
    /// A task in the backlog has no due date.
    var cleaned: ActionItem {
        var item = self
        if isBacklog {
            item.dueDate = nil
        }
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = note?.isEmpty == false ? note : nil
        item.subtasks.removeAll { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return item
    }

    /// The form dates have in the front matter: a calendar day with no time zone.
    static func dayString(from date: Date) -> String {
        let parts = DueDateParser.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func day(from text: String) -> Date? {
        guard text.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil else { return nil }
        return DueDateParser.parse(text, relativeTo: .now)
    }
}

/// What can be read from a checkbox line in a protocol.
struct ActionItemLine: Hashable, Sendable {
    var task: String
    var owner: String?
    var dueText: String?

    /// Reads `task – owner, due date`, the form `ProtocolFormatter` writes. The owner and date are
    /// only suggestions, so a line in another form is kept as a task without them.
    init(_ line: String) {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        task = line
        let separators = [" – ", " — ", " - "].compactMap { line.range(of: $0, options: .backwards) }
        guard let separator = separators.max(by: { $0.lowerBound < $1.lowerBound }) else { return }
        let task = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !task.isEmpty else { return }
        self.task = task

        let details = line[separator.upperBound...]
        if let comma = details.firstIndex(of: ",") {
            owner = Self.nonEmpty(details[..<comma])
            dueText = Self.nonEmpty(details[details.index(after: comma)...])
        } else {
            owner = Self.nonEmpty(details)
        }
        let placeholders = [ProtocolFormatter.Labels.swedish.missingOwner, ProtocolFormatter.Labels.english.missingOwner]
        if let owner, placeholders.contains(owner) {
            self.owner = nil
        }
    }

    private static func nonEmpty(_ text: Substring) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}

/// A new checkbox as the user reviews it, filled in with what the app could read from the line.
struct ActionItemDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    let noteID: UUID
    var item: ActionItem
    /// The date as the protocol has it, when the app couldn't read it as a date.
    var unreadDueText: String?
    var isIncluded = true

    init(noteID: UUID, line: String, meetingDate: Date, myNames: [String]) {
        self.noteID = noteID
        let parsed = ActionItemLine(line)
        var owner = parsed.owner
        var dueText = parsed.dueText
        // A line written by hand can have only a date after the dash.
        if dueText == nil, let text = owner, DueDateParser.parse(text, relativeTo: meetingDate) != nil {
            owner = nil
            dueText = text
        }
        let dueDate = dueText.flatMap { DueDateParser.parse($0, relativeTo: meetingDate) }
        let isMine = owner.map { Self.owner($0, isOneOf: myNames) } ?? false
        item = ActionItem(source: line, task: parsed.task, owner: isMine ? nil : owner, isMine: isMine, dueDate: dueDate)
        unreadDueText = dueDate == nil ? dueText : nil
    }

    /// Whether one of `names` is in `owner` as whole words, so "Ada Ek" also matches "Ada Ek och Bo".
    static func owner(_ owner: String, isOneOf names: [String]) -> Bool {
        names.contains { name in
            var searchRange = owner.startIndex..<owner.endIndex
            while !name.isEmpty, let match = owner.range(of: name, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                let startsWord = match.lowerBound == owner.startIndex || !owner[owner.index(before: match.lowerBound)].isLetter
                let endsWord = match.upperBound == owner.endIndex || !owner[match.upperBound].isLetter
                if startsWord, endsWord { return true }
                searchRange = match.upperBound..<owner.endIndex
            }
            return false
        }
    }
}

/// The new checkboxes in one protocol.
struct ActionItemProposal: Identifiable, Hashable, Sendable {
    var id: UUID { noteID }
    let noteID: UUID
    let title: String
    let people: [String]
    var drafts: [ActionItemDraft]
}

extension Note {
    /// Pairs the stored tasks with the protocol's checkboxes. Every checkbox is claimed once, so a
    /// line that occurs twice counts as two. Returns the block of each task, and the unclaimed blocks.
    func matchActionItems() -> (blocks: [Int?], unclaimed: [Int]) {
        var available: [String: [Int]] = [:]
        for (index, item) in document.checklistItems {
            available[item.text.plainText, default: []].append(index)
        }
        let blocks = actionItems.map { item -> Int? in
            guard let block = available[item.source]?.first else { return nil }
            available[item.source]?.removeFirst()
            return block
        }
        return (blocks, available.values.flatMap { $0 }.sorted())
    }

    /// The checkboxes that aren't in the list yet. Ticked ones are finished, so they aren't suggested.
    func newActionItemLines() -> [String] {
        guard isMeetingProtocol, folderID != NoteFolder.recentlyDeletedName else { return [] }
        return matchActionItems().unclaimed.compactMap { block in
            guard case .listItem(let item) = document.blocks[block], !item.isChecked else { return nil }
            let line = item.text.plainText
            return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : line
        }
    }

    /// The people a task from this protocol can be assigned to.
    var actionItemPeople: [String] {
        var seen = Set<String>()
        let names = (meeting?.attendees ?? []) + [meeting?.organizer ?? ""]
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var actionItemMeetingDate: Date {
        meeting?.start ?? created
    }

    var actionItemMeetingTitle: String {
        if let title = meeting?.title, !title.isEmpty { return title }
        return title
    }
}

/// A task in the overview, with its link to the protocol.
struct ActionItemRow: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let noteID: UUID
        /// The task's position in its note.
        let index: Int
    }

    let id: ID
    let item: ActionItem
    let isDone: Bool
    let meetingTitle: String
    let meetingDate: Date
    /// Written by the user, so it has no protocol.
    var isManual = false

    var noteID: UUID { id.noteID }

    func isOverdue(on day: Date) -> Bool {
        !isDone && (item.dueDate ?? .distantFuture) < day
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([item.task, item.owner ?? "", item.note ?? "", meetingTitle] + item.subtasks.map(\.title)).contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Filters, sorts and groups the tasks in the overview.
enum ActionItemOverview {
    enum Filter: String, CaseIterable, Hashable, Sendable {
        case mine
        case others
        case all
        case backlog
        case completed
    }

    enum Sort: String, CaseIterable, Hashable, Sendable {
        case dueDate
        case meeting
        case owner
    }

    struct Section: Identifiable, Hashable, Sendable {
        enum ID: Hashable, Sendable {
            case overdue
            case today
            case thisWeek
            case later
            case noDate
            case backlog
            case done
            case meeting(UUID)
            case me
            case owner(String)
            case noOwner
        }

        let id: ID
        /// The meeting's name, for a section with one meeting.
        var title: String?
        var rows: [ActionItemRow]
    }

    static func sections(
        of rows: [ActionItemRow],
        filter: Filter,
        sort: Sort,
        searchText: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Section] {
        let rows = rows
            .filter { row in
                switch filter {
                case .mine: isActive(row) && row.item.isMine
                case .others: isActive(row) && !row.item.isMine
                case .all: isActive(row)
                case .backlog: !row.isDone && row.item.isBacklog
                case .completed: row.isDone
                }
            }
            .filter { $0.matches(searchText: searchText) }
            .sorted(by: isOrderedBefore)

        switch sort {
        case .dueDate:
            // Backlog tasks have no dates to group by, and past dates mean nothing for finished tasks.
            switch filter {
            case .backlog: return rows.isEmpty ? [] : [Section(id: .backlog, rows: rows)]
            case .completed: return rows.isEmpty ? [] : [Section(id: .done, rows: rows)]
            case .mine, .others, .all: return dueDateSections(of: rows, now: now, calendar: calendar)
            }
        case .meeting:
            return meetingSections(of: rows)
        case .owner:
            return ownerSections(of: rows)
        }
    }

    /// Tasks being worked on, which the backlog and completed tabs don't have.
    private static func isActive(_ row: ActionItemRow) -> Bool {
        !row.isDone && !row.item.isBacklog
    }

    /// By date with undated tasks last, then the latest meeting.
    private static func isOrderedBefore(_ lhs: ActionItemRow, _ rhs: ActionItemRow) -> Bool {
        let lhsDue = lhs.item.dueDate ?? .distantFuture
        let rhsDue = rhs.item.dueDate ?? .distantFuture
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        if lhs.meetingDate != rhs.meetingDate { return lhs.meetingDate > rhs.meetingDate }
        if lhs.noteID != rhs.noteID { return lhs.noteID.uuidString < rhs.noteID.uuidString }
        return lhs.id.index < rhs.id.index
    }

    private static func dueDateSections(of rows: [ActionItemRow], now: Date, calendar: Calendar) -> [Section] {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? today

        func sectionID(of row: ActionItemRow) -> Section.ID {
            guard let due = row.item.dueDate else { return .noDate }
            let day = calendar.startOfDay(for: due)
            if day < today { return .overdue }
            if day == today { return .today }
            return day < weekEnd ? .thisWeek : .later
        }

        let groups = Dictionary(grouping: rows, by: sectionID)
        let order: [Section.ID] = [.overdue, .today, .thisWeek, .later, .noDate]
        return order.compactMap { id in groups[id].map { Section(id: id, rows: $0) } }
    }

    private static func meetingSections(of rows: [ActionItemRow]) -> [Section] {
        let groups = Dictionary(grouping: rows, by: \.noteID)
        return groups.values
            .sorted { lhs, rhs in
                lhs[0].meetingDate != rhs[0].meetingDate
                    ? lhs[0].meetingDate > rhs[0].meetingDate
                    : lhs[0].noteID.uuidString < rhs[0].noteID.uuidString
            }
            .map { Section(id: .meeting($0[0].noteID), title: $0[0].meetingTitle, rows: $0) }
    }

    private static func ownerSections(of rows: [ActionItemRow]) -> [Section] {
        var mine: [ActionItemRow] = []
        var noOwner: [ActionItemRow] = []
        var named: [String: [ActionItemRow]] = [:]
        for row in rows {
            if row.item.isMine {
                mine.append(row)
            } else if let owner = row.item.owner {
                named[owner, default: []].append(row)
            } else {
                noOwner.append(row)
            }
        }

        var sections = mine.isEmpty ? [] : [Section(id: .me, rows: mine)]
        for owner in named.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            sections.append(Section(id: .owner(owner), rows: named[owner, default: []]))
        }
        if !noOwner.isEmpty {
            sections.append(Section(id: .noOwner, rows: noOwner))
        }
        return sections
    }
}
