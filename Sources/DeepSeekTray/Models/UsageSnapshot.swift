import Foundation

struct UsageSnapshot {
    // Dashboard usage totals
    var totalCost: Double
    var totalRequests: Int
    var totalTokens: Int
    var usageCurrency: String

    var dailyTotals: [DailyUsage]
    var keyBreakdown: [KeyUsage]
    var lastUpdated: Date

    static let empty = UsageSnapshot(
        totalCost: 0,
        totalRequests: 0,
        totalTokens: 0,
        usageCurrency: "USD",
        dailyTotals: [],
        keyBreakdown: [],
        lastUpdated: Date()
    )

    static let mock: UsageSnapshot = {
        let calendar = Calendar.current
        let today = Date()
        let dailyTotals = (0..<30).map { offset -> DailyUsage in
            let date = calendar.date(byAdding: .day, value: -(29 - offset), to: today)!
            let tokens = [120_000, 210_000, 95_000, 310_000, 450_000, 180_000, 290_000][offset % 7]
            let cost = Double(tokens) / 1_000_000 * 0.07
            return DailyUsage(
                date: date,
                totalTokens: tokens,
                totalCost: cost,
                totalRequests: tokens / 150,
                breakdown: [
                    UsageBreakdown(category: "deepseek-chat", tokens: Int(Double(tokens) * 0.7), cost: cost * 0.7),
                    UsageBreakdown(category: "deepseek-coder", tokens: Int(Double(tokens) * 0.3), cost: cost * 0.3)
                ]
            )
        }
        return UsageSnapshot(
            totalCost: 1.45,
            totalRequests: 11_032,
            totalTokens: 1_655_000,
            usageCurrency: "USD",
            dailyTotals: dailyTotals,
            keyBreakdown: [
                KeyUsage(name: "Prod-Server-App", maskedKeyId: "sk-8f2a...991c", tokens: 1_156_845, percentage: 69.9),
                KeyUsage(name: "Local-Dev-CLI", maskedKeyId: "sk-4b19...00ab", tokens: 498_155, percentage: 30.1)
            ],
            lastUpdated: Date()
        )
    }()
}

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let totalTokens: Int
    let totalCost: Double
    let totalRequests: Int
    let breakdown: [UsageBreakdown]
}

struct KeyUsage: Identifiable {
    let id = UUID()
    let name: String
    let maskedKeyId: String
    let tokens: Int
    let percentage: Double
}

struct UsageBreakdown: Identifiable {
    let id = UUID()
    let category: String
    let tokens: Int
    let cost: Double
}
