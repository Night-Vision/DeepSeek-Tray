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

    func testParseUsageBucketsUseUTCDayNotLocalTimeZone() throws {
        // epoch 0 = 1970-01-01T00:00:00Z. Must land on Jan 1 UTC regardless of
        // the test machine's local time zone.
        let json = """
        {"data":{"biz_data":{"series":[{"model":"deepseek-chat","buckets":[
            {"time":0,"usage":{"REQUEST":1,"RESPONSE_TOKEN":100,"PROMPT_CACHE_HIT_TOKEN":0,"PROMPT_CACHE_MISS_TOKEN":0}}
        ]}]}}}
        """.data(using: .utf8)!

        let endpoint = DiscoveredDashboardUsageClient.DiscoveredEndpoint(
            url: "", method: "GET", headers: [:], discoveredAt: Date()
        )
        let client = DiscoveredDashboardUsageClient(endpoint: endpoint)
        let snapshot = try client.parseUsage(json, days: 7)

        XCTAssertEqual(snapshot.dailyTotals.count, 1)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month, .day], from: snapshot.dailyTotals[0].date)
        XCTAssertEqual(comps.year, 1970)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
    }

    func testBudgetThresholdsPending() {
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 90, budget: 100, alreadyFired: []), [80])
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 110, budget: 100, alreadyFired: []), [80, 100])
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 110, budget: 100, alreadyFired: ["80"]), [100])
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 110, budget: 100, alreadyFired: ["80", "100"]), [])
    }

    func testBudgetDisabledAtZero() {
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 90, budget: 0, alreadyFired: []), [])
        XCTAssertEqual(NotificationManager.pendingThresholds(cost: 0, budget: 100, alreadyFired: []), [])
    }

    func testBudgetMonthKey() {
        let date = Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        XCTAssertEqual(NotificationManager.monthKey(date: date), "2025-7")
    }

    // MARK: - Export

    private func exportFixture() -> UsageSnapshot {
        let day0 = Date(timeIntervalSince1970: 0)
        return UsageSnapshot(
            totalCost: 9.0,
            totalRequests: 30,
            totalTokens: 300,
            usageCurrency: "USD",
            dailyTotals: [
                DailyUsage(date: day0, totalTokens: 100, totalCost: 0, totalRequests: 10,
                           breakdown: [UsageBreakdown(category: "deepseek-chat", tokens: 100, cost: 0)]),
                DailyUsage(date: day0.addingTimeInterval(86_400), totalTokens: 200, totalCost: 0, totalRequests: 20,
                           breakdown: [UsageBreakdown(category: "deepseek-chat", tokens: 200, cost: 0)]),
            ],
            keyBreakdown: [KeyUsage(name: "Prod", maskedKeyId: "sk-1...9", tokens: 300, percentage: 100)],
            lastUpdated: day0
        )
    }

    /// Guards the all-zeros regression: DailyUsage.totalCost is always 0 from the
    /// API, so export must allocate the real billed total across days.
    func testDailyCostsAllocateBilledTotal() {
        let costs = UsageExporter.dailyCosts(exportFixture())
        XCTAssertEqual(costs.reduce(0, +), 9.0, accuracy: 0.0001)
        XCTAssertEqual(costs[0], 3.0, accuracy: 0.0001)
        XCTAssertEqual(costs[1], 6.0, accuracy: 0.0001)
    }

    func testDailyCostsZeroTokensDoesNotDivideByZero() {
        var snapshot = exportFixture()
        snapshot.dailyTotals = [DailyUsage(date: Date(), totalTokens: 0, totalCost: 0, totalRequests: 0, breakdown: [])]
        XCTAssertEqual(UsageExporter.dailyCosts(snapshot), [0])
    }

    func testCSVShape() {
        let lines = UsageExporter.csv(exportFixture()).split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3) // header + 2 days
        XCTAssertEqual(lines[0], "date,tokens,requests,estimated_cost_usd")
        XCTAssertEqual(lines[1], "1970-01-01,100,10,3.0000")
    }

    func testJSONTopLevelKeys() throws {
        let data = try UsageExporter.json(exportFixture(), windowDays: 7)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try XCTUnwrap(obj)
        XCTAssertEqual(root["billedMonthlyCost"] as? Double, 9.0)
        XCTAssertEqual(root["costAllocationIsEstimated"] as? Bool, true)
        XCTAssertEqual(root["windowDays"] as? Int, 7)
        XCTAssertEqual((root["daily"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((root["keys"] as? [[String: Any]])?.count, 1)
    }
}

