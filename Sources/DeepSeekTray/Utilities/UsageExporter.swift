import Foundation

/// Everything one export needs, already resolved: the days in the chosen range,
/// the per-day cost estimate, and the monthly bills those estimates came from.
struct ExportBundle {
    struct Model: Equatable {
        let name: String
        let tokens: Int
    }

    struct Day: Equatable {
        let date: Date
        let tokens: Int
        let requests: Int
        let estimatedCost: Double
        let models: [Model]
    }

    struct Month: Equatable {
        let key: MonthKey
        /// The platform's real charge for that month.
        let billedCost: Double
        /// The share of it the exported days account for.
        let allocatedCost: Double
        let currency: String
        /// The range covers only part of this month, so the allocation is a share.
        let partial: Bool
    }

    let range: DateRange
    let currency: String
    let days: [Day]
    let months: [Month]
    let keyBreakdown: [KeyUsage]
    let generatedAt: Date

    var totalTokens: Int { days.reduce(0) { $0 + $1.tokens } }
    var totalRequests: Int { days.reduce(0) { $0 + $1.requests } }
    var allocatedCost: Double { days.reduce(0) { $0 + $1.estimatedCost } }
    var billedCost: Double { months.reduce(0) { $0 + $1.billedCost } }
}

/// Turns raw usage into an `ExportBundle`. Pure: no network, no clock, no disk.
enum ExportBundleBuilder {

    /// `window` must span whole months for every month in `bills` — that is what
    /// makes `monthTokenTotals` a usable denominator, so a partial range spreads
    /// the bill over the whole month instead of absorbing all of it.
    ///
    /// The platform reports usage per UTC-aligned day, so days are enumerated on
    /// that grid. Gaps inside the returned span become zero rows, which keeps the
    /// file contiguous for a spreadsheet.
    static func build(range: DateRange,
                      window: [DailyUsage],
                      keyBreakdown: [KeyUsage],
                      monthTokenTotals: [MonthKey: Int],
                      bills: [MonthKey: (cost: Double, currency: String)],
                      generatedAt: Date = Date()) -> ExportBundle {
        let calendar = ExportCalendar.utc
        let inRange = window.filter { range.contains(instant: $0.date) }.sorted { $0.date < $1.date }

        var days: [ExportBundle.Day] = []
        if let first = inRange.first?.date, let last = inRange.last?.date {
            let byDate = Dictionary(inRange.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
            var cursor = first
            while cursor <= last {
                let usage = byDate[cursor]
                let tokens = usage?.totalTokens ?? 0
                let month = MonthKey(cursor, calendar: calendar)
                let denominator = monthTokenTotals[month] ?? 0
                let bill = bills[month]?.cost ?? 0
                let cost = denominator > 0 ? bill * Double(tokens) / Double(denominator) : 0
                days.append(ExportBundle.Day(
                    date: cursor,
                    tokens: tokens,
                    requests: usage?.totalRequests ?? 0,
                    estimatedCost: cost,
                    models: (usage?.breakdown ?? []).map { ExportBundle.Model(name: $0.category, tokens: $0.tokens) }
                ))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        var months: [ExportBundle.Month] = []
        for key in range.coveredMonths(calendar: calendar) {
            let bill = bills[key]
            let allocated = days
                .filter { MonthKey($0.date, calendar: calendar) == key }
                .reduce(0) { $0 + $1.estimatedCost }
            months.append(ExportBundle.Month(
                key: key,
                billedCost: bill?.cost ?? 0,
                allocatedCost: allocated,
                currency: bill?.currency ?? "",
                partial: isPartial(key, range: range, calendar: calendar)
            ))
        }

        let currency = months.map(\.currency).first { !$0.isEmpty } ?? "USD"
        return ExportBundle(
            range: range,
            currency: currency,
            days: days,
            months: months,
            keyBreakdown: keyBreakdown,
            generatedAt: generatedAt
        )
    }

    /// True when the range covers only part of that month.
    private static func isPartial(_ key: MonthKey, range: DateRange, calendar: Calendar) -> Bool {
        var components = DateComponents()
        components.year = key.year
        components.month = key.month
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return true }
        return !(range.start <= start && end <= range.end)
    }
}

/// CSV / JSON export of a chosen range.
///
/// The app keeps no history on disk, so a range is either sliced out of the
/// window already loaded or fetched on demand — see `UsageExportService`.
enum UsageExporter {

    static func csv(_ bundle: ExportBundle) -> String {
        let currency = bundle.currency.isEmpty ? "USD" : bundle.currency
        var lines = ["date,tokens,requests,estimated_cost_\(currency.lowercased())"]
        for day in bundle.days {
            lines.append("\(dayStamp.string(from: day.date)),\(day.tokens),\(day.requests),\(String(format: "%.4f", day.estimatedCost))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // Explicit export schema rather than Codable on the models: keeps the file
    // format stable across internal refactors and keeps the models' `id = UUID()`
    // (meaningless outside SwiftUI list diffing) out of the payload.
    private struct Payload: Encodable {
        struct Model: Encodable {
            let name: String
            let tokens: Int
        }
        struct Day: Encodable {
            let date: Date
            let tokens: Int
            let requests: Int
            let estimatedCost: Double
            let models: [Model]
        }
        struct Month: Encodable {
            let month: String
            let billedCost: Double
            let allocatedCost: Double
            let currency: String
            let partial: Bool
        }
        struct Key: Encodable {
            let name: String
            let maskedId: String
            let tokens: Int
            let percentage: Double
        }
        let exportedAt: Date
        let rangeStart: Date
        /// Exclusive, matching the platform's own `end` convention.
        let rangeEnd: Date
        let dayCount: Int
        /// Kept from the previous schema so existing consumers keep working.
        let windowDays: Int
        let currency: String
        /// Sum of the monthly bills the range touches.
        let billedMonthlyCost: Double
        let allocatedCost: Double
        let costAllocationIsEstimated: Bool
        let totalTokens: Int
        let totalRequests: Int
        let daily: [Day]
        let months: [Month]
        let keys: [Key]
    }

    static func json(_ bundle: ExportBundle) throws -> Data {
        let payload = Payload(
            exportedAt: bundle.generatedAt,
            rangeStart: bundle.range.start,
            rangeEnd: bundle.range.end,
            dayCount: bundle.days.count,
            windowDays: bundle.days.count,
            currency: bundle.currency.isEmpty ? "USD" : bundle.currency,
            billedMonthlyCost: bundle.billedCost,
            allocatedCost: bundle.allocatedCost,
            costAllocationIsEstimated: true,
            totalTokens: bundle.totalTokens,
            totalRequests: bundle.totalRequests,
            daily: bundle.days.map { day in
                Payload.Day(date: day.date, tokens: day.tokens, requests: day.requests,
                            estimatedCost: day.estimatedCost,
                            models: day.models.map { Payload.Model(name: $0.name, tokens: $0.tokens) })
            },
            months: bundle.months.map {
                Payload.Month(month: $0.key.label, billedCost: $0.billedCost,
                              allocatedCost: $0.allocatedCost, currency: $0.currency, partial: $0.partial)
            },
            keys: bundle.keyBreakdown.map {
                Payload.Key(name: $0.name, maskedId: $0.maskedKeyId, tokens: $0.tokens, percentage: $0.percentage)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// `deepseek-usage-2026-08-01_to_2026-08-21.csv`
    static func suggestedFilename(_ bundle: ExportBundle, ext: String) -> String {
        let calendar = ExportCalendar.utc
        let lastDay = calendar.date(byAdding: .day, value: -1, to: bundle.range.end) ?? bundle.range.start
        return "deepseek-usage-\(dayStamp.string(from: bundle.range.start))_to_\(dayStamp.string(from: lastDay)).\(ext)"
    }

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
