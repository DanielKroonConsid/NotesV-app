import Foundation

/// Turns a `MeetingProtocol` into a note, using the app's own paragraph styles so it stays editable.
enum ProtocolFormatter {
    /// The fixed texts in a protocol. They follow the protocol's language, not the app's,
    /// so they are kept here instead of in the String Catalog.
    struct Labels: Sendable {
        var titlePrefix: String
        var meetingInfo: String
        var date: String
        var location: String
        var organizer: String
        var attendees: String
        var present: String
        var absent: String
        var agenda: String
        var decisions: String
        var actionItems: String
        var none: String
        var missingOwner: String
        var missingDueDate: String

        static let swedish = Labels(
            titlePrefix: "Protokoll", meetingInfo: "Mötesinformation", date: "Datum", location: "Plats",
            organizer: "Organisatör", attendees: "Deltagare", present: "Närvarande", absent: "Frånvarande",
            agenda: "Agenda och diskussion", decisions: "Beslut", actionItems: "Åtgärdspunkter",
            none: "Inga noterade", missingOwner: "[Ansvarig saknas]", missingDueDate: "[Datum saknas]"
        )

        static let english = Labels(
            titlePrefix: "Minutes", meetingInfo: "Meeting info", date: "Date", location: "Location",
            organizer: "Organizer", attendees: "Attendees", present: "Present", absent: "Absent",
            agenda: "Agenda and discussion", decisions: "Decisions", actionItems: "Action items",
            none: "None noted", missingOwner: "[Owner missing]", missingDueDate: "[Due date missing]"
        )

        /// Swedish for "sv", English for everything else.
        init(languageCode: String) {
            self = languageCode.lowercased().hasPrefix("sv") ? .swedish : .english
        }

        private init(
            titlePrefix: String, meetingInfo: String, date: String, location: String, organizer: String,
            attendees: String, present: String, absent: String, agenda: String, decisions: String,
            actionItems: String, none: String, missingOwner: String, missingDueDate: String
        ) {
            self.titlePrefix = titlePrefix
            self.meetingInfo = meetingInfo
            self.date = date
            self.location = location
            self.organizer = organizer
            self.attendees = attendees
            self.present = present
            self.absent = absent
            self.agenda = agenda
            self.decisions = decisions
            self.actionItems = actionItems
            self.none = none
            self.missingOwner = missingOwner
            self.missingDueDate = missingDueDate
        }
    }

    static func title(for meeting: MeetingDetails, languageCode: String) -> String {
        "\(Labels(languageCode: languageCode).titlePrefix) – \(meeting.title)"
    }

    static func document(
        for minutes: MeetingProtocol,
        meeting: MeetingDetails,
        timeZone: TimeZone = .current
    ) -> NoteDocument {
        let labels = Labels(languageCode: minutes.language)
        var blocks: [Block] = [.paragraph(.title, RichText(plain: title(for: meeting, languageCode: minutes.language)))]

        // 1. Meeting info, straight from the meeting details.
        blocks.append(.paragraph(.heading, RichText(plain: labels.meetingInfo)))
        blocks.append(labeledItem(labels.date, dateText(for: meeting, languageCode: minutes.language, timeZone: timeZone)))
        if !meeting.location.isEmpty {
            blocks.append(labeledItem(labels.location, meeting.location))
        }
        if !meeting.organizer.isEmpty {
            blocks.append(labeledItem(labels.organizer, meeting.organizer))
        }

        // 2. Attendees.
        blocks.append(.paragraph(.heading, RichText(plain: labels.attendees)))
        blocks.append(.paragraph(.subheading, RichText(plain: labels.present)))
        blocks += bulletList(minutes.attendeesPresent, none: labels.none)
        if !minutes.attendeesAbsent.isEmpty {
            blocks.append(.paragraph(.subheading, RichText(plain: labels.absent)))
            blocks += bulletList(minutes.attendeesAbsent, none: labels.none)
        }

        // 3. Agenda and discussion.
        blocks.append(.paragraph(.heading, RichText(plain: labels.agenda)))
        if minutes.agendaItems.isEmpty {
            blocks.append(.paragraph(.body, RichText(plain: labels.none)))
        }
        for item in minutes.agendaItems {
            blocks.append(.paragraph(.subheading, RichText(plain: item.title)))
            blocks.append(.paragraph(.body, RichText(plain: item.summary)))
        }

        // 4. Decisions.
        blocks.append(.paragraph(.heading, RichText(plain: labels.decisions)))
        blocks += bulletList(minutes.decisions, none: labels.none)

        // 5. Action items, as a checklist. Missing owners and dates get a placeholder, never a guess.
        blocks.append(.paragraph(.heading, RichText(plain: labels.actionItems)))
        if minutes.actionItems.isEmpty {
            blocks.append(.paragraph(.body, RichText(plain: labels.none)))
        }
        for item in minutes.actionItems {
            let owner = nonEmpty(item.owner) ?? labels.missingOwner
            let dueDate = nonEmpty(item.dueDate) ?? labels.missingDueDate
            blocks.append(.listItem(ListItem(kind: .checklist, text: RichText(plain: "\(item.task) – \(owner), \(dueDate)"))))
        }
        return NoteDocument(blocks: blocks)
    }

    private static func labeledItem(_ label: String, _ value: String) -> Block {
        .listItem(ListItem(kind: .bulleted, text: RichText([TextRun("\(label):", style: .bold), TextRun(" \(value)")])))
    }

    private static func bulletList(_ items: [String], none: String) -> [Block] {
        let items = items.compactMap(nonEmpty)
        guard !items.isEmpty else { return [.paragraph(.body, RichText(plain: none))] }
        return items.map { .listItem(ListItem(kind: .bulleted, text: RichText(plain: $0))) }
    }

    private static func dateText(for meeting: MeetingDetails, languageCode: String, timeZone: TimeZone) -> String {
        let locale = Locale(identifier: languageCode.lowercased().hasPrefix("sv") ? "sv_SE" : "en_US")
        var style = Date.FormatStyle(date: .long, time: .shortened, locale: locale)
        style.timeZone = timeZone
        let start = meeting.start.formatted(style)
        guard let end = meeting.end else { return start }
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        timeStyle.timeZone = timeZone
        return "\(start)–\(end.formatted(timeStyle))"
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
