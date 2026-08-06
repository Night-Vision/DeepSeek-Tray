import Foundation

struct BalanceInfo {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String
}

struct UsageSnapshot {
    // Official API balance
    var balance: BalanceInfo?

    // Dashboard usage totals
    var totalCost: Double
    var totalRequests: Int
    var totalTokens: Int
    var usageCurrency: String

    var dailyTotals: [DailyUsage]
    var hourlyTotalsToday: [HourlyUsage]
    var keyBreakdown: [KeyUsage]
    var lastUpdated: Date

    static let empty = UsageSnapshot(
        balance: nil,
        totalCost: 0,
        totalRequests: 0,
        totalTokens: 0,
        usageCurrency: "USD",
        dailyTotals: [],
        hourlyTotalsToday: [],
        keyBreakdown: [],
        lastUpdated: Date()
    )

    static let mock: UsageSnapshot = {
        let calendar = Calendar.current
        let today = Date()
        let dailyTotals = (0..<7).map { offset -> DailyUsage in
            let date = calendar.date(byAdding: .day, value: -(6 - offset), to: today)!
            let tokens = [120_000, 210_000, 95_000, 310_000, 450_000, 180_000, 290_000][offset]
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
        let hourlyTotalsToday = [
            HourlyUsage(hour: 8, tokens: 1_200),
            HourlyUsage(hour: 9, tokens: 3_100),
            HourlyUsage(hour: 10, tokens: 5_000),
            HourlyUsage(hour: 11, tokens: 3_800),
            HourlyUsage(hour: 12, tokens: 6_900),
            HourlyUsage(hour: 13, tokens: 4_200),
            HourlyUsage(hour: 14, tokens: 12_400),
            HourlyUsage(hour: 15, tokens: 5_600),
            HourlyUsage(hour: 16, tokens: 2_100),
            HourlyUsage(hour: 17, tokens: 8_200)
        ]
        return UsageSnapshot(
            balance: BalanceInfo(currency: "USD", totalBalance: "1.45", grantedBalance: "0.00", toppedUpBalance: "1.45"),
            totalCost: 1.45,
            totalRequests: 866,
            totalTokens: 52_910_584,
            usageCurrency: "USD",
            dailyTotals: dailyTotals,
            hourlyTotalsToday: hourlyTotalsToday,
            keyBreakdown: [
                KeyUsage(name: "Prod-Server-App", maskedKeyId: "sk-8f2a...991c", tokens: 37_000_000, percentage: 69.9),
                KeyUsage(name: "Local-Dev-CLI", maskedKeyId: "sk-4b19...00ab", tokens: 15_910_584, percentage: 30.1)
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

struct HourlyUsage: Identifiable {
    let id = UUID()
    let hour: Int
    let tokens: Int
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
