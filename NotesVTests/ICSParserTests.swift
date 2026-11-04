import Foundation
import Testing
@testable import NotesV

struct ICSParserTests {
    private let stockholm = TimeZone(identifier: "Europe/Stockholm")!

    /// 2026-11-04 09:00 UTC, which is 10:00 in Stockholm.
    private let nineUTC = Date(timeIntervalSince1970: 1_793_782_800)

    private func calendar(_ event: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(event.replacingOccurrences(of: "\n", with: "\r\n"))\r\nEND:VCALENDAR\r\n"
    }

    private func parseOne(_ event: String) throws -> ICSEvent {
        let events = try ICSParser.parse(calendar(event), defaultTimeZone: stockholm)
        return try #require(events.first)
    }

    @Test func readsAnOutlookInvitation() throws {
        let event = try parseOne(#"""
        BEGIN:VEVENT
        ORGANIZER;CN="Ek, Ada":mailto:ada@example.com
        ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;CN=Bo Berg:mailto:bo@example.com
        ATTENDEE;ROLE=OPT-PARTICIPANT;PARTSTAT=DECLINED;CN=Cia Ceder:mailto:cia@example.com
        ATTENDEE;CUTYPE=ROOM;CN=Rum 1:mailto:rum1@example.com
        ATTENDEE:mailto:dan@example.com
        DESCRIPTION:Gå igenom releasen\, och\nbudgeten.\n\n___________________________\nMicrosoft Teams meeting\nJoin: https://teams.example/abc\nPasscode: 123
        DTSTART;TZID=W. Europe Standard Time:20261104T100000
        DTEND;TZID=W. Europe Standard Time:20261104T110000
        LOCATION:Rum 1\; plan 2
        SUMMARY:Veckomöte
        UID:abc
        BEGIN:VALARM
        DESCRIPTION:Reminder
        TRIGGER:-PT15M
        END:VALARM
        END:VEVENT
        """#)

        #expect(event.details.title == "Veckomöte")
        #expect(event.details.start == nineUTC)
        #expect(event.details.end == nineUTC.addingTimeInterval(3600))
        #expect(event.details.location == "Rum 1; plan 2")
        #expect(event.details.organizer == "Ek, Ada")
        #expect(event.details.attendees == ["Bo Berg", "dan@example.com"])
        #expect(event.details.agenda == "Gå igenom releasen, och\nbudgeten.")
        #expect(!event.usedFallbackTimeZone)
        #expect(!event.isRecurring)
    }

    @Test func readsAFileFromCalendar() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        DTSTART;TZID=Europe/Stockholm:20261104T100000
        DURATION:PT1H30M
        SUMMARY:Sync
        END:VEVENT
        """)
        #expect(event.details.start == nineUTC)
        #expect(event.details.end == nineUTC.addingTimeInterval(5400))
    }

    @Test func joinsFoldedLines() throws {
        let text = "BEGIN:VEVENT\r\nSUMMARY:Lång\r\n  rubrik\r\n\tsom fortsätter\r\nDTSTART:20261104T090000Z\r\nEND:VEVENT\r\n"
        let event = try #require(try ICSParser.parse(text).first)
        #expect(event.details.title == "Lång rubriksom fortsätter")
        #expect(event.details.start == nineUTC)
    }

    @Test func keepsColonsAndSemicolonsInQuotedParameters() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        ORGANIZER;CN="Team: A; B":mailto:team@example.com
        DTSTART:20261104T090000Z
        END:VEVENT
        """)
        #expect(event.details.organizer == "Team: A; B")
    }

    @Test func allDayEventsHaveNoEndTime() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261104
        DTEND;VALUE=DATE:20261105
        SUMMARY:Konferens
        END:VEVENT
        """)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stockholm
        #expect(event.details.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 4)))
        #expect(event.details.end == nil)
    }

    @Test func unknownTimeZonesFallBackToLocalTimeWithAWarning() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        DTSTART;TZID=Customized Time Zone:20261104T100000
        END:VEVENT
        """)
        #expect(event.details.start == nineUTC)
        #expect(event.usedFallbackTimeZone)
    }

    @Test func timesWithoutTimeZoneAreLocal() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        DTSTART:20261104T100000
        END:VEVENT
        """)
        #expect(event.details.start == nineUTC)
        #expect(!event.usedFallbackTimeZone)
    }

    @Test func marksRecurringMeetings() throws {
        let event = try parseOne("""
        BEGIN:VEVENT
        DTSTART:20261104T090000Z
        RRULE:FREQ=WEEKLY
        END:VEVENT
        """)
        #expect(event.isRecurring)
    }

    @Test func readsSeveralEvents() throws {
        let events = try ICSParser.parse(calendar("""
        BEGIN:VEVENT
        DTSTART:20261104T090000Z
        SUMMARY:Ett
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20261105T090000Z
        SUMMARY:Två
        END:VEVENT
        """))
        #expect(events.map(\.details.title) == ["Ett", "Två"])
    }

    @Test func rejectsFilesWithoutEvents() {
        #expect(throws: ICSParser.ParseError.noEvents) { try ICSParser.parse("not a calendar") }
        #expect(throws: ICSParser.ParseError.noEvents) { try ICSParser.parse(calendar("BEGIN:VTODO\nEND:VTODO")) }
        // An event without a readable start can't be used.
        #expect(throws: ICSParser.ParseError.noEvents) {
            try ICSParser.parse(calendar("BEGIN:VEVENT\nSUMMARY:Ingen tid\nEND:VEVENT"))
        }
    }

    @Test func rejectsFilesThatAreTooLarge() {
        let data = Data(count: ICSParser.maximumFileSize + 1)
        #expect(throws: ICSParser.ParseError.fileTooLarge) { try ICSParser.parse(data: data) }
    }
}
