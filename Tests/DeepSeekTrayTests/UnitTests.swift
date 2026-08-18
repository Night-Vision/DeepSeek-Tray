import XCTest
@testable import DeepSeekTray

final class UnitTests: XCTestCase {
    func testTokenFormatterShort() {
        XCTAssertEqual(TokenFormatter.short(500), "500")
        XCTAssertEqual(TokenFormatter.short(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.short(2_300_000), "2.30M")
    }

    func testCostForWindowWithinMonthEstimates() {
        // All window days inside the current calendar month → proportional estimate.
        let today = Date()
        let snapshot = UsageSnapshot(
            totalCost: 10.0,
            totalRequests: 400,
            totalTokens: 400,
            usageCurrency: "USD",
            dailyTotals: [
                DailyUsage(date: today, totalTokens: 300, totalCost: 0, totalRequests: 300, breakdown: []),
                DailyUsage(date: today.addingTimeInterval(-86_400), totalTokens: 100, totalCost: 0, totalRequests: 100, breakdown: []),
            ],
            keyBreakdown: [],
            lastUpdated: today
        )
        let cost = snapshot.costForWindow(days: 7)
        XCTAssertTrue(cost.estimated)
        XCTAssertEqual(cost.amount, 10.0, accuracy: 0.001)
    }

    func testCostForWindowAcrossMonthFallback() {
        // Window spans into the previous month → raw monthly total, not estimated.
        let today = Date()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
        let snapshot = UsageSnapshot(
            totalCost: 10.0,
            totalRequests: 400,
            totalTokens: 400,
            usageCurrency: "USD",
            dailyTotals: [
                DailyUsage(date: lastMonth, totalTokens: 300, totalCost: 0, totalRequests: 300, breakdown: []),
                DailyUsage(date: today, totalTokens: 100, totalCost: 0, totalRequests: 100, breakdown: []),
            ],
            keyBreakdown: [],
            lastUpdated: today
        )
        let cost = snapshot.costForWindow(days: 7)
        XCTAssertFalse(cost.estimated)
        XCTAssertEqual(cost.amount, 10.0, accuracy: 0.001)
    }
}
