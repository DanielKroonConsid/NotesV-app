import Foundation

/// The date sections that Notes uses in its note list.
enum NoteDateGroup: Hashable, Sendable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(year: Int, month: Int)

    init(date: Date, now: Date = .now, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0

        switch days {
        case ...0:
            self = .today
        case 1:
            self = .yesterday
        case 2...7:
            self = .previous7Days
        case 8...30:
            self = .previous30Days
        default:
            let components = calendar.dateComponents([.year, .month], from: date)
            self = .month(year: components.year ?? 0, month: components.month ?? 1)
        }
    }
}
