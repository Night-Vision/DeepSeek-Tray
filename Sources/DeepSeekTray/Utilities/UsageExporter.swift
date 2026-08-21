import Foundation

/// CSV / JSON export of the currently loaded usage window.
///
/// The app keeps no history on disk — `UsageTracker.snapshot` only ever holds
/// the 7- or 30-day window last fetched, so that window is what gets exported.
enum UsageExporter {

    // MARK: - Cost allocation

    /// Per-day cost is NOT available from the platform: `parseUsage` hardcodes
    /// `DailyUsage.totalCost = 0` because the usage payload is token-only. The
    /// only real money figure is `snapshot.totalCost` (the monthly bill from
    /// `fetchCost`). Allocate it across days by token share — same ratio math as
    /// `UsageSnapshot.costForWindow`. Always an estimate; both outputs say so.
    static func dailyCosts(_ snapshot: UsageSnapshot) -> [Double] {
        let totalTokens = snapshot.dailyTotals.reduce(0) { $0 + $1.totalTokens }
        guard totalTokens > 0 else { return snapshot.dailyTotals.map { _ in 0 } }
        return snapshot.dailyTotals.map {
            snapshot.totalCost * Double($0.totalTokens) / Double(totalTokens)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - CSV

    /// Flat daily table — no preamble, no stacked sections, so it imports clean.
    /// Every field is a date or a number, so no CSV escaping is needed (model and
    /// key names, the only free text, appear in the JSON export only).
    static func csv(_ snapshot: UsageSnapshot) -> String {
        let costs = dailyCosts(snapshot)
        let currency = snapshot.usageCurrency.isEmpty ? "USD" : snapshot.usageCurrency
        var lines = ["date,tokens,requests,estimated_cost_\(currency.lowercased())"]
        for (day, cost) in zip(snapshot.dailyTotals, costs) {
            lines.append("\(dayFormatter.string(from: day.date)),\(day.totalTokens),\(day.totalRequests),\(String(format: "%.4f", cost))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - JSON

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
        struct Key: Encodable {
            let name: String
            let maskedId: String
            let tokens: Int
            let percentage: Double
        }
        let exportedAt: Date
        let windowDays: Int
        let currency: String
        let billedMonthlyCost: Double
        let costAllocationIsEstimated: Bool
        let totalTokens: Int
        let totalRequests: Int
        let daily: [Day]
        let keys: [Key]
    }

    static func json(_ snapshot: UsageSnapshot, windowDays: Int) throws -> Data {
        let costs = dailyCosts(snapshot)
        let payload = Payload(
            exportedAt: Date(),
            windowDays: windowDays,
            currency: snapshot.usageCurrency.isEmpty ? "USD" : snapshot.usageCurrency,
            billedMonthlyCost: snapshot.totalCost,
            costAllocationIsEstimated: true,
            totalTokens: snapshot.totalTokens,
            totalRequests: snapshot.totalRequests,
            daily: zip(snapshot.dailyTotals, costs).map { day, cost in
                Payload.Day(
                    date: day.date,
                    tokens: day.totalTokens,
                    requests: day.totalRequests,
                    estimatedCost: cost,
                    models: day.breakdown.map { Payload.Model(name: $0.category, tokens: $0.tokens) }
                )
            },
            keys: snapshot.keyBreakdown.map {
                Payload.Key(name: $0.name, maskedId: $0.maskedKeyId, tokens: $0.tokens, percentage: $0.percentage)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// `deepseek-usage-2026-08-20.csv`
    static func suggestedFilename(ext: String) -> String {
        "deepseek-usage-\(dayFormatter.string(from: Date())).\(ext)"
    }
}
