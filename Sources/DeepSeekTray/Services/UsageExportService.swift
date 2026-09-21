import Foundation

/// Resolves a chosen range into an `ExportBundle`, fetching only what the loaded
/// snapshot cannot answer. Never writes to `UsageTracker.snapshot`: the dashboard
/// keeps showing the window it already has, and a failed export never disturbs it.
@MainActor
final class UsageExportService {
    static let shared = UsageExportService()

    /// The dashboard always requests this many days, so a loaded snapshot is known
    /// to cover a window this long ending at its last successful refresh.
    static let loadedWindowDays = 30

    private init() {}

    func bundle(for preset: ExportPreset,
                customStart: Date? = nil,
                customEnd: Date? = nil,
                loaded snapshot: UsageSnapshot,
                now: Date = Date(),
                calendar: Calendar = .current) async throws -> ExportBundle {
        let exportCalendar = ExportCalendar.utc
        let range = preset.resolve(now: now, calendar: calendar,
                                   customStart: customStart, customEnd: customEnd)
        let loadedWindow = DateRange.trailing(days: Self.loadedWindowDays,
                                              now: snapshot.lastUpdated,
                                              calendar: calendar)
        let source = ExportSource.plan(range: range, loadedWindow: loadedWindow, calendar: exportCalendar)
        let months = range.coveredMonths(calendar: exportCalendar)

        var windowDays = snapshot.dailyTotals
        var keyBreakdown = snapshot.keyBreakdown
        var loadedBillMonth: MonthKey?

        switch source {
        case .loaded:
            // The window already in hand is the source; only its current-month
            // bill is usable without asking (the platform bills by month).
            loadedBillMonth = MonthKey(snapshot.lastUpdated, calendar: exportCalendar)
        case let .fetch(wholeMonths, _):
            let fetched = try await Self.client().fetchUsage(window: wholeMonths, aggregateDays: nil)
            windowDays = fetched.dailyTotals
            keyBreakdown = fetched.keyBreakdown
        }

        // Whole-month token totals: the denominator each monthly bill is spread
        // across, so a partial range never absorbs the entire charge.
        var monthTokens: [MonthKey: Int] = [:]
        for day in windowDays {
            monthTokens[MonthKey(day.date, calendar: exportCalendar), default: 0] += day.totalTokens
        }

        var bills: [MonthKey: (cost: Double, currency: String)] = [:]
        if !months.isEmpty {
            let client = try Self.client()
            for month in months {
                if month == loadedBillMonth, snapshot.totalCost > 0 {
                    bills[month] = (snapshot.totalCost, snapshot.usageCurrency)
                    continue
                }
                if let cost = try? await client.fetchCost(month: month.month, year: month.year),
                   cost.cost > 0 {
                    bills[month] = cost
                }
            }
        }

        return ExportBundleBuilder.build(range: range,
                                         window: windowDays,
                                         keyBreakdown: keyBreakdown,
                                         monthTokenTotals: monthTokens,
                                         bills: bills)
    }

    private static func client() throws -> DiscoveredDashboardUsageClient {
        guard let endpoint = DiscoveredDashboardUsageClient.loadEndpoint() else {
            throw DashboardFetchError.resourceUnavailable
        }
        return DiscoveredDashboardUsageClient(endpoint: endpoint)
    }
}
