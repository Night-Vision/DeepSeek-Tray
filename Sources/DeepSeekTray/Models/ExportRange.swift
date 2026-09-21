import Foundation

/// A half-open day range `[start, end)` — the convention the platform's usage API
/// uses for its `start`/`end` query items, where `end` is the midnight *after*
/// the last day the user means to include.
struct DateRange: Equatable, Hashable {
    let start: Date
    let end: Date

    var dayCount: Int { max(0, Int((end.timeIntervalSince(start) / 86_400).rounded())) }

    /// A whole-day range ending today, `days` calendar days long — the shape the
    /// dashboard has always requested for its 30-day window.
    static func trailing(days: Int, now: Date, calendar: Calendar) -> DateRange {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)
            ?? end.addingTimeInterval(-Double(days) * 86_400)
        return DateRange(start: start, end: end)
    }

    /// Midnight starting the last included day — needed to test whether a loaded
    /// snapshot really covers this range.
    func lastDayStart(_ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end) ?? end
    }

    func contains(instant: Date) -> Bool { instant >= start && instant < end }

    /// Calendar months the range touches, oldest first. The platform bills by
    /// month, so any cost lookup has to work in these units.
    func coveredMonths(calendar: Calendar) -> [MonthKey] {
        guard end > start else { return [] }
        var months: [MonthKey] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let lastMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: lastDayStart(calendar))
        ) ?? start
        while cursor <= lastMonth {
            months.append(MonthKey(cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    /// The whole months this range touches, as one span. Requesting the usage for
    /// this gives every requested day *and* each month's true token total, which
    /// is the denominator a monthly bill has to be spread across.
    func wholeMonthsSpan(calendar: Calendar) -> DateRange {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let lastMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: lastDayStart(calendar))
        ) ?? start
        let end = calendar.date(byAdding: .month, value: 1, to: lastMonth) ?? self.end
        return DateRange(start: first, end: end)
    }
}

/// A calendar month, the unit the platform's billing API bills in.
struct MonthKey: Hashable, Comparable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.year = c.year ?? 0
        self.month = c.month ?? 1
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    var label: String { String(format: "%04d-%02d", year, month) }
}

/// What the user picked in Preferences → Export Usage Data.
enum ExportPreset: String, CaseIterable, Identifiable, Hashable {
    case last7, last30, thisMonth, lastMonth, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last7: return "Last 7 days"
        case .last30: return "Last 30 days"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .custom: return "Custom\u{2026}"
        }
    }

    /// `customStart`/`customEnd` are inclusive calendar days and are only read
    /// for `.custom`. Days are the user's own calendar days; the platform's
    /// payload buckets by UTC day, which is why an export can include one day
    /// more at the edges for a non-UTC account — see `ExportBundleBuilder`.
    func resolve(now: Date = Date(),
                 calendar: Calendar = .current,
                 customStart: Date? = nil,
                 customEnd: Date? = nil) -> DateRange {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .last7:
            return .trailing(days: 7, now: now, calendar: calendar)
        case .last30:
            return .trailing(days: 30, now: now, calendar: calendar)
        case .thisMonth:
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            return DateRange(start: first, end: dayAfter(today, calendar))
        case .lastMonth:
            let firstThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let firstLastMonth = calendar.date(byAdding: .month, value: -1, to: firstThisMonth) ?? firstThisMonth
            return DateRange(start: firstLastMonth, end: firstThisMonth)
        case .custom:
            let start = calendar.startOfDay(for: customStart ?? today)
            let pickedEnd = calendar.startOfDay(for: customEnd ?? today)
            let end = max(start, pickedEnd)
            return DateRange(start: start, end: dayAfter(end, calendar))
        }
    }
}

/// Where an export's usage data comes from. Pure, so the whole decision is
/// testable without a network or a tracker.
enum ExportSource: Equatable {
    /// Every requested day already sits inside the loaded window.
    case loaded
    /// The range has to be requested. `wholeMonths` spans whole months so one
    /// request also yields the token denominators the monthly bills need.
    case fetch(wholeMonths: DateRange, months: [MonthKey])

    static func plan(range: DateRange,
                     loadedWindow: DateRange?,
                     calendar: Calendar) -> ExportSource {
        let months = range.coveredMonths(calendar: calendar)
        if let loadedWindow, loadedWindow.start <= range.start, range.end <= loadedWindow.end {
            return .loaded
        }
        return .fetch(wholeMonths: range.wholeMonthsSpan(calendar: calendar), months: months)
    }
}

/// The export pipeline runs on the platform's own day grid: `parseUsage` buckets
/// by UTC day, and a UTC bucket cannot be made to line up with a local civil day
/// anyway. Using one calendar everywhere keeps the day rows, the month
/// denominators and the billed month consistent with each other.
enum ExportCalendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

private func dayAfter(_ day: Date, _ calendar: Calendar) -> Date {
    calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
}
