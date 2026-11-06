import Foundation

/// Reads a due date written in a protocol, in Swedish or English.
///
/// Relative dates count from the meeting. Anything else returns `nil`, because a date is never guessed.
enum DueDateParser {
    /// Dates are calendar days in the user's time zone, whatever calendar the Mac is set to.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static let months: [String: Int] = [
        "jan": 1, "januari": 1, "january": 1,
        "feb": 2, "februari": 2, "february": 2,
        "mar": 3, "mars": 3, "march": 3,
        "apr": 4, "april": 4,
        "maj": 5, "may": 5,
        "jun": 6, "juni": 6, "june": 6,
        "jul": 7, "juli": 7, "july": 7,
        "aug": 8, "augusti": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "okt": 10, "oct": 10, "oktober": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// `Calendar` numbers the days from Sunday, 1. Text is compared without diacritics.
    private static let weekdays: [String: Int] = [
        "sondag": 1, "sunday": 1,
        "mandag": 2, "monday": 2,
        "tisdag": 3, "tuesday": 3,
        "onsdag": 4, "wednesday": 4,
        "torsdag": 5, "thursday": 5,
        "fredag": 6, "friday": 6,
        "lordag": 7, "saturday": 7,
    ]

    private static let friday = 6

    static func parse(_ text: String, relativeTo meetingDate: Date) -> Date? {
        var text = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        for prefix in ["senast ", "by ", "on ", "pa ", "den ", "the "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        let calendar = calendar
        let base = calendar.startOfDay(for: meetingDate)

        switch text {
        case "idag", "i dag", "today":
            return base
        case "imorgon", "i morgon", "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: base)
        case "nasta vecka", "next week":
            return nextWeekFriday(after: base)
        default:
            break
        }
        if let weekday = weekdays[text] {
            return calendar.nextDate(after: base, matching: DateComponents(weekday: weekday), matchingPolicy: .strict)
        }

        // "fredag 20 november": the date decides.
        if let space = text.firstIndex(of: " "), weekdays[String(text[..<space]).trimmingCharacters(in: .punctuationCharacters)] != nil {
            text = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        }
        return date(from: text, base: base) ?? week(from: text, base: base)
    }

    private static func date(from text: String, base: Date) -> Date? {
        if let match = text.wholeMatch(of: #/(\d{4})-(\d{1,2})-(\d{1,2})/#) {
            return day(year: Int(match.1), month: Int(match.2), day: Int(match.3), base: base)
        }
        if let match = text.wholeMatch(of: #/(\d{1,2})/(\d{1,2})(?:[/ -](\d{4}))?/#) {
            return day(year: match.3.flatMap { Int($0) }, month: Int(match.2), day: Int(match.1), base: base)
        }
        if let match = text.wholeMatch(of: #/(\d{1,2})(?:st|nd|rd|th|:e|:a|e)?\s+([a-z]+)\.?(?:,?\s+(\d{4}))?/#) {
            return day(year: match.3.flatMap { Int($0) }, month: months[String(match.2)], day: Int(match.1), base: base)
        }
        if let match = text.wholeMatch(of: #/([a-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th|:e|:a|e)?(?:,?\s+(\d{4}))?/#) {
            return day(year: match.3.flatMap { Int($0) }, month: months[String(match.1)], day: Int(match.2), base: base)
        }
        return nil
    }

    /// Without a year, the first such day from the meeting and on.
    private static func day(year: Int?, month: Int?, day: Int?, base: Date) -> Date? {
        guard let month, let day else { return nil }
        let calendar = calendar
        func date(in year: Int) -> Date? {
            let parts = DateComponents(year: year, month: month, day: day)
            return parts.isValidDate(in: calendar) ? calendar.date(from: parts) : nil
        }
        if let year { return date(in: year) }

        let baseYear = calendar.component(.year, from: base)
        if let date = date(in: baseYear), date >= base { return date }
        return date(in: baseYear + 1)
    }

    /// A week counts as its Friday, the last working day.
    private static func week(from text: String, base: Date) -> Date? {
        guard let match = text.wholeMatch(of: #/(?:v|w|vecka|week)\.?\s*(\d{1,2})/#), let week = Int(match.1) else { return nil }
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = .current

        func date(in year: Int) -> Date? {
            let parts = DateComponents(weekday: friday, weekOfYear: week, yearForWeekOfYear: year)
            guard let date = isoCalendar.date(from: parts),
                  isoCalendar.component(.weekOfYear, from: date) == week else { return nil }
            return date
        }
        let year = isoCalendar.component(.yearForWeekOfYear, from: base)
        if let date = date(in: year), date >= base { return date }
        return date(in: year + 1)
    }

    private static func nextWeekFriday(after base: Date) -> Date? {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = .current
        guard let nextWeek = isoCalendar.date(byAdding: .weekOfYear, value: 1, to: base) else { return nil }
        var parts = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeek)
        parts.weekday = friday
        return isoCalendar.date(from: parts)
    }
}
