import Foundation

/// Reads and writes the YAML front matter at the top of a note file.
///
/// Only the small YAML subset that NotesV writes is supported: `key: value` pairs, one level of
/// nested mappings, and one list of mappings (`tasks`). Unknown keys are ignored.
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
        var actionItems: [ActionItem] = []
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
        if !note.actionItems.isEmpty {
            lines.append("tasks:")
            for item in note.actionItems {
                lines.append("  - source: \(quoted(item.source))")
                lines.append("    task: \(quoted(item.task))")
                if let owner = item.owner { lines.append("    owner: \(quoted(owner))") }
                lines.append("    mine: \(item.isMine)")
                if let dueDate = item.dueDate { lines.append("    due: \(ActionItem.dayString(from: dueDate))") }
                lines.append("    status: \(item.status.rawValue)")
            }
        }
        lines.append(delimiter)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Splits a file into its front matter fields and the Markdown body after it.
    /// Returns `nil` fields if the file has no front matter.
    static func split(_ text: String) -> (fields: Fields?, body: Substring) {
        guard text.hasPrefix(delimiter + "\n") else { return (nil, Substring(text)) }

        let afterOpening = text.index(text.startIndex, offsetBy: delimiter.count + 1)
        var lines: [Substring] = []
        var cursor = afterOpening
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd]
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            if line == delimiter {
                return (parse(lines), text[next...])
            }
            lines.append(line)
            cursor = next
        }
        // No closing delimiter: treat the whole file as Markdown.
        return (nil, Substring(text))
    }

    // MARK: - Parsing

    private static func parse(_ lines: [Substring]) -> Fields {
        var fields = Fields()
        var values: [String: String] = [:]
        var meetingValues: [String: String] = [:]
        var attendees: [String] = []
        var taskValues: [[String: String]] = []
        var currentMap: String?

        for var line in lines {
            if currentMap == "tasks", let dash = line.firstIndex(of: "-"),
               line[..<dash].allSatisfy({ $0 == " " }), line[line.index(after: dash)...].first == " " {
                taskValues.append([:])
                line = "  " + line[line.index(after: dash)...]
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let isIndented = line.first == " " || line.first == "\t"
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: colon)...]
            let value = parseScalar(rawValue)

            if isIndented, currentMap == "meeting" {
                if key == "attendees" {
                    attendees = parseList(rawValue)
                } else {
                    meetingValues[key] = value
                }
            } else if isIndented, currentMap == "tasks" {
                if !taskValues.isEmpty {
                    taskValues[taskValues.count - 1][key] = value
                }
            } else if !isIndented {
                currentMap = value.isEmpty ? key : nil
                values[key] = value
            }
        }

        fields.id = values["id"].flatMap(UUID.init(uuidString:))
        fields.created = values["created"].flatMap(parseDate)
        fields.modified = values["modified"].flatMap(parseDate)
        fields.isPinned = values["pinned"].map { $0.lowercased() == "true" }
        fields.sourceNoteID = values["sourceNote"].flatMap(UUID.init(uuidString:))
        fields.sentAt = values["sent"].flatMap(parseDate)
        fields.actionItems = taskValues.compactMap(parseActionItem)
        if let start = meetingValues["start"].flatMap(parseDate) {
            // Older notes have an empty eventId for meetings that didn't come from Outlook.
            let eventID = meetingValues["eventId"].flatMap { $0.isEmpty ? nil : $0 }
            fields.meeting = MeetingDetails(
                eventID: eventID,
                title: meetingValues["subject"] ?? "",
                start: start,
                end: meetingValues["end"].flatMap(parseDate),
                location: meetingValues["location"] ?? "",
                organizer: meetingValues["organizer"] ?? "",
                attendees: attendees,
                agenda: meetingValues["agenda"] ?? ""
            )
        }
        return fields
    }

    /// A task needs its line in the protocol, so a damaged entry is left out.
    private static func parseActionItem(_ values: [String: String]) -> ActionItem? {
        guard let source = values["source"], !source.isEmpty else { return nil }
        return ActionItem(
            source: source,
            task: values["task"].flatMap { $0.isEmpty ? nil : $0 } ?? source,
            owner: values["owner"].flatMap { $0.isEmpty ? nil : $0 },
            isMine: values["mine"]?.lowercased() == "true",
            dueDate: values["due"].flatMap(ActionItem.day),
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
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
