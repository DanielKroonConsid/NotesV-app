import Foundation

/// Reads and writes the YAML front matter at the top of a note file.
///
/// Only the small YAML subset that NotesV writes is supported: `key: value` pairs and one level of
/// nested mappings. Unknown keys are ignored.
enum FrontMatter {
    /// The metadata stored in the front matter. Every field is optional, because files edited
    /// outside the app may lack some or all of it.
    struct Fields: Hashable, Sendable {
        var id: UUID?
        var created: Date?
        var modified: Date?
        var isPinned: Bool?
        var meeting: MeetingReference?
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
        if let meeting = note.meeting {
            lines += [
                "meeting:",
                "  eventId: \(quoted(meeting.eventID))",
                "  subject: \(quoted(meeting.subject))",
                "  start: \(formatDate(meeting.start))",
            ]
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
        var currentMap: String?

        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let isIndented = line.first == " " || line.first == "\t"
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = parseScalar(line[line.index(after: colon)...])

            if isIndented, currentMap == "meeting" {
                meetingValues[key] = value
            } else if !isIndented {
                currentMap = value.isEmpty ? key : nil
                values[key] = value
            }
        }

        fields.id = values["id"].flatMap(UUID.init(uuidString:))
        fields.created = values["created"].flatMap(parseDate)
        fields.modified = values["modified"].flatMap(parseDate)
        fields.isPinned = values["pinned"].map { $0.lowercased() == "true" }
        if let eventID = meetingValues["eventId"], let start = meetingValues["start"].flatMap(parseDate) {
            fields.meeting = MeetingReference(eventID: eventID, subject: meetingValues["subject"] ?? "", start: start)
        }
        return fields
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
        for character in value {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            default: result.append(character)
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
