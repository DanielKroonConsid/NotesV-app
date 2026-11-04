import Foundation

/// A meeting read from an `.ics` file.
struct ICSEvent: Hashable, Sendable {
    var details: MeetingDetails
    /// The file describes a series, and `details.start` is its first occurrence.
    var isRecurring = false
    /// The file's time zone was unknown, so the times were read as local time.
    var usedFallbackTimeZone = false
}

/// Reads calendar events from iCalendar (`.ics`) files, as exported by Outlook and Calendar.
///
/// The files often come from other people, so everything in them is treated as plain text.
enum ICSParser {
    enum ParseError: LocalizedError, Equatable {
        case fileTooLarge
        case noEvents

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: String(localized: "The file is too large to be a calendar event.")
            case .noEvents: String(localized: "The file doesn’t contain a calendar event.")
            }
        }
    }

    static let maximumFileSize = 1_000_000

    /// Outlook names time zones the Windows way, and these names aren't known to `TimeZone`.
    private static let windowsTimeZones = [
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw",
        "Romance Standard Time": "Europe/Paris",
        "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik",
        "FLE Standard Time": "Europe/Helsinki",
        "GTB Standard Time": "Europe/Athens",
        "E. Europe Standard Time": "Europe/Chisinau",
        "Russian Standard Time": "Europe/Moscow",
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "Pacific Standard Time": "America/Los_Angeles",
        "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai",
        "Tokyo Standard Time": "Asia/Tokyo",
        "AUS Eastern Standard Time": "Australia/Sydney",
    ]

    private struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }

    static func parse(data: Data, defaultTimeZone: TimeZone = .current) throws -> [ICSEvent] {
        guard data.count <= maximumFileSize else { throw ParseError.fileTooLarge }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return try parse(text, defaultTimeZone: defaultTimeZone)
    }

    static func parse(_ text: String, defaultTimeZone: TimeZone = .current) throws -> [ICSEvent] {
        var events: [ICSEvent] = []
        // Components nest (an event can hold an alarm), so only properties directly in VEVENT count.
        var components: [String] = []
        var properties: [Property] = []

        for line in unfoldedLines(of: text) {
            guard let property = parseProperty(line) else { continue }
            switch property.name {
            case "BEGIN":
                components.append(property.value.uppercased())
                if components.last == "VEVENT" { properties = [] }
            case "END":
                if components.last == "VEVENT", let event = makeEvent(from: properties, defaultTimeZone: defaultTimeZone) {
                    events.append(event)
                }
                components.removeLast(min(components.count, 1))
            default:
                if components.last == "VEVENT" { properties.append(property) }
            }
        }

        guard !events.isEmpty else { throw ParseError.noEvents }
        return events
    }

    // MARK: - Lines and properties

    /// Normalizes line endings and joins lines that were folded, which continue with a space or tab.
    private static func unfoldedLines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: "\n")
    }

    /// Splits `NAME;PARAM=value;PARAM="a:b":VALUE`. Colons and semicolons in quotes don't separate.
    private static func parseProperty(_ line: String) -> Property? {
        var parts: [String] = []
        var current = ""
        var isQuoted = false
        var valueStart: String.Index?

        for index in line.indices {
            let character = line[index]
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character == ":", !isQuoted {
                valueStart = line.index(after: index)
                break
            } else if character == ";", !isQuoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        guard let valueStart else { return nil }
        parts.append(current)

        var parameters: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let value = part[part.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            parameters[part[..<equals].uppercased()] = value
        }
        return Property(name: parts[0].uppercased(), parameters: parameters, value: String(line[valueStart...]))
    }

    private static func unescaped(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            result.append(next == "n" || next == "N" ? "\n" : next)
        }
        return result
    }

    // MARK: - Events

    private static func makeEvent(from properties: [Property], defaultTimeZone: TimeZone) -> ICSEvent? {
        func first(_ name: String) -> Property? { properties.first { $0.name == name } }

        guard let startProperty = first("DTSTART"),
              let start = parseDate(startProperty, defaultTimeZone: defaultTimeZone) else { return nil }

        var end: Date?
        if !start.isAllDay {
            if let endProperty = first("DTEND") {
                end = parseDate(endProperty, defaultTimeZone: defaultTimeZone)?.date
            } else if let duration = first("DURATION").flatMap({ parseDuration($0.value) }) {
                end = start.date.addingTimeInterval(duration)
            }
        }

        var attendees: [String] = []
        for property in properties where property.name == "ATTENDEE" && isPerson(property) {
            let name = displayName(of: property)
            if !name.isEmpty, !attendees.contains(name) { attendees.append(name) }
        }

        let details = MeetingDetails(
            title: first("SUMMARY").map { unescaped($0.value) } ?? "",
            start: start.date,
            end: end,
            location: first("LOCATION").map { unescaped($0.value) } ?? "",
            organizer: first("ORGANIZER").map(displayName) ?? "",
            attendees: attendees,
            agenda: first("DESCRIPTION").map { removingJoinInformation(from: unescaped($0.value)) } ?? ""
        )
        return ICSEvent(details: details, isRecurring: first("RRULE") != nil, usedFallbackTimeZone: start.usedFallbackTimeZone)
    }

    /// Whether an attendee should count as invited: not someone who declined, and not a room.
    private static func isPerson(_ attendee: Property) -> Bool {
        let hasDeclined = attendee.parameters["PARTSTAT"]?.uppercased() == "DECLINED"
        let type = attendee.parameters["CUTYPE"]?.uppercased()
        return !hasDeclined && type != "ROOM" && type != "RESOURCE"
    }

    /// The common name if there is one, otherwise the email address.
    private static func displayName(of property: Property) -> String {
        if let name = property.parameters["CN"], !name.isEmpty {
            return unescaped(name)
        }
        var address = property.value
        if address.lowercased().hasPrefix("mailto:") {
            address.removeFirst("mailto:".count)
        }
        return address
    }

    /// Removes the block Outlook appends to invitations, with the Teams link and passcode.
    /// It starts at a line of underscores or a `-::~:~` line. The join link shouldn't reach the AI provider.
    private static func removingJoinInformation(from description: String) -> String {
        var lines: [Substring] = []
        for line in description.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isUnderscores = trimmed.count >= 10 && trimmed.allSatisfy { $0 == "_" }
            if isUnderscores || trimmed.hasPrefix("-::~:") { break }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Dates

    private struct ParsedDate {
        var date: Date
        var isAllDay: Bool
        var usedFallbackTimeZone: Bool
    }

    /// Reads `20261104T100000Z` (UTC), `20261104T100000` with or without `TZID`, and `20261104` (all day).
    /// A time without `TZID` or `Z` is local time, as the iCalendar format defines it.
    private static func parseDate(_ property: Property, defaultTimeZone: TimeZone) -> ParsedDate? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let digits = value.filter(\.isNumber).map { Int(String($0)) ?? 0 }
        guard digits.count == 8 || digits.count == 14 else { return nil }

        func number(_ range: Range<Int>) -> Int {
            digits[range].reduce(0) { $0 * 10 + $1 }
        }

        var timeZone = defaultTimeZone
        var usedFallbackTimeZone = false
        if value.hasSuffix("Z") {
            timeZone = .gmt
        } else if let identifier = property.parameters["TZID"] {
            if let known = self.timeZone(named: identifier) {
                timeZone = known
            } else {
                usedFallbackTimeZone = true
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let isAllDay = digits.count == 8
        let components = DateComponents(
            year: number(0..<4),
            month: number(4..<6),
            day: number(6..<8),
            hour: isAllDay ? 0 : number(8..<10),
            minute: isAllDay ? 0 : number(10..<12),
            second: isAllDay ? 0 : number(12..<14)
        )
        guard let date = calendar.date(from: components) else { return nil }
        return ParsedDate(date: date, isAllDay: isAllDay, usedFallbackTimeZone: usedFallbackTimeZone)
    }

    private static func timeZone(named identifier: String) -> TimeZone? {
        let name = identifier.hasPrefix("/") ? String(identifier.dropFirst()) : identifier
        return windowsTimeZones[name].flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: name)
    }

    /// Reads durations such as `PT1H30M` or `P1D`.
    private static func parseDuration(_ value: String) -> TimeInterval? {
        guard value.hasPrefix("P") else { return nil }
        var seconds: TimeInterval = 0
        var number = ""
        for character in value.dropFirst() {
            if character.isNumber {
                number.append(character)
                continue
            }
            let amount = TimeInterval(number) ?? 0
            number = ""
            switch character {
            case "W": seconds += amount * 604_800
            case "D": seconds += amount * 86_400
            case "H": seconds += amount * 3_600
            case "M": seconds += amount * 60
            case "S": seconds += amount
            default: break // The "T" between date and time.
            }
        }
        return seconds
    }
}
