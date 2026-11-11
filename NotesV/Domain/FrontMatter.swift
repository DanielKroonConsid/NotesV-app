import Foundation

/// Reads and writes the YAML front matter at the top of a note file.
///
/// Only a small YAML subset is supported; `parse` describes it. Keys NotesV doesn't use are kept as
/// they were written and saved again, so other apps' metadata survives.
enum FrontMatter {
    /// The metadata stored in the front matter. Every field is optional, because files edited
    /// outside the app may lack some or all of it.
    struct Fields: Hashable, Sendable {
        var id: UUID?
        var created: Date?
        var modified: Date?
        var isPinned: Bool?
        var meeting: MeetingDetails?
        var sourceNoteID: UUID?
        var sentAt: Date?
        /// A task's details. Its title, note and subtasks are in the file's body.
        var task: ActionItem?
        var actionItems: [ActionItem] = []
        /// Top-level entries NotesV doesn't use, written back unchanged.
        var extraEntries: [RawEntry] = []
    }

    /// A top-level key NotesV doesn't read, with its lines exactly as they were written.
    struct RawEntry: Hashable, Sendable {
        var key: String
        var lines: [String]
    }

    static let delimiter = "---"

    static func encode(_ note: Note) -> String {
        var lines = [
            delimiter,
            "id: \(note.id.uuidString)",
            "created: \(formatDate(note.created))",
            "modified: \(formatDate(note.modified))",
            "pinned: \(note.isPinned)",
        ]
        if let sourceNoteID = note.sourceNoteID {
            lines.append("sourceNote: \(sourceNoteID.uuidString)")
        }
        if let sentAt = note.sentAt {
            lines.append("sent: \(formatDate(sentAt))")
        }
        if let meeting = note.meeting {
            lines.append("meeting:")
            if let eventID = meeting.eventID { lines.append("  eventId: \(quoted(eventID))") }
            lines.append("  subject: \(quoted(meeting.title))")
            lines.append("  start: \(formatDate(meeting.start))")
            if let end = meeting.end { lines.append("  end: \(formatDate(end))") }
            if !meeting.location.isEmpty { lines.append("  location: \(quoted(meeting.location))") }
            if !meeting.organizer.isEmpty { lines.append("  organizer: \(quoted(meeting.organizer))") }
            if !meeting.attendees.isEmpty {
                lines.append("  attendees: [\(meeting.attendees.map(quoted).joined(separator: ", "))]")
            }
            if !meeting.agenda.isEmpty { lines.append("  agenda: \(quoted(meeting.agenda))") }
        }
        if let task = note.task {
            lines.append("task:")
            if let protocolID = task.protocolID { lines.append("  protocol: \(protocolID.uuidString)") }
            if !task.source.isEmpty { lines.append("  source: \(quoted(task.source))") }
            if let owner = task.owner { lines.append("  owner: \(quoted(owner))") }
            lines.append("  mine: \(task.isMine)")
            if let dueDate = task.dueDate { lines.append("  due: \(ActionItem.dayString(from: dueDate))") }
            if task.isBacklog { lines.append("  backlog: true") }
            lines.append("  status: \(task.status.rawValue)")
        }
        if !note.actionItems.isEmpty {
            lines.append("tasks:")
            for item in note.actionItems {
                lines.append("  - source: \(quoted(item.source))")
                lines.append("    task: \(quoted(item.task))")
                if let owner = item.owner { lines.append("    owner: \(quoted(owner))") }
                lines.append("    mine: \(item.isMine)")
                if let dueDate = item.dueDate { lines.append("    due: \(ActionItem.dayString(from: dueDate))") }
                if item.isBacklog { lines.append("    backlog: true") }
                if let note = item.note { lines.append("    note: \(quoted(note))") }
                if !item.subtasks.isEmpty {
                    lines.append("    subtasks: [\(item.subtasks.map { quoted($0.line) }.joined(separator: ", "))]")
                }
                lines.append("    status: \(item.status.rawValue)")
            }
        }
        // Another app's keys go last. One NotesV now writes itself, such as a meeting that
        // couldn't be read before, replaces the old version.
        let writtenKeys = Set(lines.dropFirst().compactMap { topLevelKey($0[...]) })
        for entry in note.extraFrontMatter where !writtenKeys.contains(entry.key) {
            lines += entry.lines
        }
        lines.append(delimiter)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Splits a file into its front matter fields and the Markdown body after it.
    /// Returns `nil` fields if the file has no front matter. Expects `\n` line endings.
    static func split(_ text: String) -> (fields: Fields?, body: Substring) {
        // Trailing spaces after a delimiter are allowed, and YAML's `...` also ends the block.
        func isDelimiter(_ line: Substring, closing: Bool) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == delimiter || closing && trimmed == "..."
        }

        let firstLineEnd = text.firstIndex(of: "\n") ?? text.endIndex
        guard firstLineEnd < text.endIndex, isDelimiter(text[..<firstLineEnd], closing: false) else {
            return (nil, Substring(text))
        }

        var lines: [Substring] = []
        var cursor = text.index(after: firstLineEnd)
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd]
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            if isDelimiter(line, closing: true) {
                return (parse(lines), text[next...])
            }
            lines.append(line)
            cursor = next
        }
        // No closing delimiter: treat the whole file as Markdown.
        return (nil, Substring(text))
    }

    // MARK: - Parsing

    /// A top-level key and the lines that belong to it.
    private struct Block {
        var key: String
        /// The text after the key's colon.
        var value: Substring
        /// The indented lines under the key, and list items written without indentation.
        var body: [Substring] = []
        /// The key's line and its body as they were written.
        var lines: [Substring]
    }

    /// Reads a small subset of YAML:
    /// - The top level is `key: value` lines. A line that starts with a space, a tab or `- ` belongs
    ///   to the key above it.
    /// - `meeting` and `task` are maps of `key: value` lines. A value can be a list on one line
    ///   (`["Ada", "Bo"]`), a list of `- item` lines, or a block (`|` keeps line breaks, `>` joins lines).
    /// - `tasks` is the list of maps earlier versions wrote.
    /// - Any other top-level key is kept as it was written (`extraEntries`), and so is a meeting
    ///   whose start can't be read, so that saving the note doesn't remove it from the file.
    private static func parse(_ lines: [Substring]) -> Fields {
        var fields = Fields()
        var values: [String: String] = [:]
        var meetingBlock: Block?
        var taskBlock: Block?
        var tasksBlock: Block?

        for block in topLevelBlocks(lines) {
            switch block.key {
            case "id", "created", "modified", "pinned", "sourceNote", "sent":
                values[block.key] = parseScalar(block.value)
            case "meeting":
                meetingBlock = block
            case "task":
                taskBlock = block
            case "tasks":
                tasksBlock = block
            default:
                fields.extraEntries.append(RawEntry(key: block.key, lines: block.lines.map(String.init)))
            }
        }

        fields.id = values["id"].flatMap(UUID.init(uuidString:))
        fields.created = values["created"].flatMap(parseDate)
        fields.modified = values["modified"].flatMap(parseDate)
        fields.isPinned = values["pinned"].map { $0.lowercased() == "true" }
        fields.sourceNoteID = values["sourceNote"].flatMap(UUID.init(uuidString:))
        fields.sentAt = values["sent"].flatMap(parseDate)
        if let tasksBlock {
            fields.actionItems = parseActionItems(tasksBlock.body)
        }
        if let taskBlock {
            let map = parseMap(taskBlock.body)
            if !map.scalars.isEmpty {
                fields.task = parseTaskDetails(map.scalars)
            }
        }
        if let meetingBlock {
            let map = parseMap(meetingBlock.body)
            if let start = map.scalars["start"].flatMap(parseDate) {
                // Older notes have an empty eventId for meetings that didn't come from Outlook.
                let eventID = map.scalars["eventId"].flatMap { $0.isEmpty ? nil : $0 }
                fields.meeting = MeetingDetails(
                    eventID: eventID,
                    title: map.scalars["subject"] ?? "",
                    start: start,
                    end: map.scalars["end"].flatMap(parseDate),
                    location: map.scalars["location"] ?? "",
                    organizer: map.scalars["organizer"] ?? "",
                    attendees: map.lists["attendees"] ?? [],
                    agenda: map.scalars["agenda"] ?? ""
                )
            } else {
                fields.extraEntries.append(RawEntry(key: meetingBlock.key, lines: meetingBlock.lines.map(String.init)))
            }
        }
        return fields
    }

    private static func topLevelBlocks(_ lines: [Substring]) -> [Block] {
        var blocks: [Block] = []
        for line in lines {
            if let key = topLevelKey(line), let colon = line.firstIndex(of: ":") {
                blocks.append(Block(key: key, value: line[line.index(after: colon)...], lines: [line]))
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].body.append(line)
                blocks[blocks.count - 1].lines.append(line)
            }
        }
        // Blank lines at the end of a block belong to neither key.
        for index in blocks.indices {
            while let last = blocks[index].lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks[index].lines.removeLast()
            }
        }
        return blocks
    }

    /// The key of a line that starts a top-level entry, or `nil` for any other line.
    private static func topLevelKey(_ line: Substring) -> String? {
        guard let first = line.first, ![" ", "\t", "-", "#"].contains(first),
              let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// Reads the `key: value` lines of a map. Lists are also returned as `lists`.
    private static func parseMap(_ lines: [Substring]) -> (scalars: [String: String], lists: [String: [String]]) {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let indent = indentation(of: line)
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: colon)...]
            let value = rawValue.trimmingCharacters(in: .whitespaces)

            if value.isEmpty || value.hasPrefix("#") {
                // A list of `- item` lines, which may be at the key's own indentation.
                var items: [String] = []
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    if item.isEmpty {
                        index += 1
                        continue
                    }
                    guard indentation(of: lines[index]) >= indent, item == "-" || item.hasPrefix("- ") else { break }
                    items.append(parseScalar(item.dropFirst()))
                    index += 1
                }
                scalars[key] = ""
                lists[key] = items.filter { !$0.isEmpty }
            } else if let folds = blockScalarFolds(value) {
                var content: [Substring] = []
                while index < lines.count {
                    let next = lines[index]
                    if !next.trimmingCharacters(in: .whitespaces).isEmpty, indentation(of: next) <= indent { break }
                    content.append(next)
                    index += 1
                }
                while let last = content.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                    content.removeLast()
                }
                let margin = content.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(indentation).min() ?? 0
                let text = content.map { String($0.dropFirst(min(margin, indentation(of: $0)))) }
                scalars[key] = text.joined(separator: folds ? " " : "\n")
            } else {
                scalars[key] = parseScalar(rawValue)
                if value.hasPrefix("[") {
                    lists[key] = parseList(rawValue)
                }
            }
        }
        return (scalars, lists)
    }

    /// For a block value's indicator: `true` if its lines are joined (`>`), `false` if kept (`|`).
    private static func blockScalarFolds(_ value: String) -> Bool? {
        guard let indicator = value.first, indicator == "|" || indicator == ">" else { return nil }
        let rest = value.dropFirst().split(separator: "#", maxSplits: 1).first ?? ""
        guard rest.trimmingCharacters(in: .whitespaces).allSatisfy({ "+-0123456789".contains($0) }) else { return nil }
        return indicator == ">"
    }

    private static func indentation(of line: Substring) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    /// The list of tasks earlier versions wrote: `- source: …` followed by the task's other keys.
    private static func parseActionItems(_ lines: [Substring]) -> [ActionItem] {
        var taskValues: [[String: String]] = []
        var taskSubtasks: [[String]] = []
        for var line in lines {
            if let dash = line.firstIndex(of: "-"),
               line[..<dash].allSatisfy({ $0 == " " }), line[line.index(after: dash)...].first == " " {
                taskValues.append([:])
                taskSubtasks.append([])
                line = line[line.index(after: dash)...]
            }
            guard !taskValues.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: colon)...]
            if key == "subtasks" {
                taskSubtasks[taskSubtasks.count - 1] = parseList(rawValue)
            } else {
                taskValues[taskValues.count - 1][key] = parseScalar(rawValue)
            }
        }
        return zip(taskValues, taskSubtasks).compactMap(parseActionItem)
    }

    private static func parseTaskDetails(_ values: [String: String]) -> ActionItem {
        ActionItem(
            source: values["source"] ?? "",
            task: "",
            owner: values["owner"].flatMap { $0.isEmpty ? nil : $0 },
            isMine: values["mine"]?.lowercased() == "true",
            dueDate: values["due"].flatMap(ActionItem.day),
            isBacklog: values["backlog"]?.lowercased() == "true",
            status: values["status"].flatMap(ActionItem.Status.init(rawValue:)) ?? .open,
            protocolID: values["protocol"].flatMap(UUID.init(uuidString:))
        )
    }

    /// A task needs its line in the protocol, so a damaged entry is left out.
    private static func parseActionItem(_ values: [String: String], subtasks: [String]) -> ActionItem? {
        guard let source = values["source"], !source.isEmpty else { return nil }
        return ActionItem(
            source: source,
            task: values["task"].flatMap { $0.isEmpty ? nil : $0 } ?? source,
            owner: values["owner"].flatMap { $0.isEmpty ? nil : $0 },
            isMine: values["mine"]?.lowercased() == "true",
            dueDate: values["due"].flatMap(ActionItem.day),
            isBacklog: values["backlog"]?.lowercased() == "true",
            note: values["note"].flatMap { $0.isEmpty ? nil : $0 },
            subtasks: subtasks.compactMap(ActionItem.Subtask.init(line:)),
            status: values["status"].flatMap(ActionItem.Status.init(rawValue:)) ?? .open
        )
    }

    private static func parseScalar(_ raw: Substring) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") {
            return unquoteDouble(trimmed)
        }
        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        // Strip a trailing comment from unquoted values.
        if let comment = trimmed.range(of: " #") {
            return String(trimmed[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// Reads a list on one line: `["Ada", "Bo"]`. Items may also be unquoted.
    private static func parseList(_ raw: Substring) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }

        var items: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = trimmed.dropFirst().dropLast().makeIterator()
        while let character = iterator.next() {
            switch character {
            case "\\" where isQuoted:
                current.append("\\")
                if let next = iterator.next() { current.append(next) }
            case "\"":
                isQuoted.toggle()
                current.append(character)
            case "," where !isQuoted:
                items.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        items.append(current)
        return items.map { parseScalar($0[...]) }.filter { !$0.isEmpty }
    }

    private static func unquoteDouble(_ text: String) -> String {
        var result = ""
        var iterator = text.dropFirst().makeIterator()
        while let character = iterator.next() {
            switch character {
            case "\"":
                return result
            case "\\":
                switch iterator.next() {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case let escaped?: result.append(escaped)
                case nil: return result
                }
            default:
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Formatting

    private static func quoted(_ value: String) -> String {
        var result = "\""
        // Scalars, because "\r\n" is a single Character and would otherwise end the line.
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": continue
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func formatDate(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) {
            return date
        }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return parseLocalDate(text)
    }

    /// Dates other editors often write without a time zone, read as local time:
    /// `2026-10-20`, `2026-10-20 09:00`, `2026-10-20T09:00` and the same with seconds.
    private static func parseLocalDate(_ text: String) -> Date? {
        let pattern = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/
        guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern) else { return nil }
        let calendar = Calendar.current
        var components = DateComponents(
            calendar: calendar, timeZone: calendar.timeZone,
            year: Int(match.1), month: Int(match.2), day: Int(match.3),
            hour: match.4.flatMap { Int($0) } ?? 0, minute: match.5.flatMap { Int($0) } ?? 0,
            second: match.6.flatMap { Int($0) } ?? 0
        )
        components.calendar = calendar
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}
