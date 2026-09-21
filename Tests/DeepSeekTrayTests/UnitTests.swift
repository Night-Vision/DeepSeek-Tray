import XCTest
@testable import DeepSeekTray

/// Runs under Xcode (`sudo xcode-select -s /Applications/Xcode.app`): Command Line
/// Tools alone ship no XCTest module, so `swift test` cannot compile this target
/// with CLT only.
///
/// The former `testJWTExpiryDecodesWithoutSignature` was removed: it called a
/// `JWT` helper that no longer exists anywhere in the app.
final class UnitTests: XCTestCase {

    // MARK: - Fixtures

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func usage(_ date: Date, tokens: Int, requests: Int = 0) -> DailyUsage {
        DailyUsage(date: date, totalTokens: tokens, totalCost: 0, totalRequests: requests, breakdown: [])
    }

    // MARK: - Formatting

    func testTokenFormatterShort() {
        XCTAssertEqual(TokenFormatter.short(500), "500")
        XCTAssertEqual(TokenFormatter.short(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.short(2_300_000), "2.30M")
    }

    // MARK: - Window cost (dashboard)

    private func windowSnapshot(totalCost: Double, first: Date, second: Date) -> UsageSnapshot {
        UsageSnapshot(
            totalCost: totalCost,
            totalRequests: 400,
            totalTokens: 400,
            usageCurrency: "USD",
            dailyTotals: [
                DailyUsage(date: first, totalTokens: 300, totalCost: 0, totalRequests: 300, breakdown: []),
                DailyUsage(date: second, totalTokens: 100, totalCost: 0, totalRequests: 100, breakdown: []),
            ],
            keyBreakdown: [],
            lastUpdated: Date()
        )
    }

    func testCostForWindowWithinMonthEstimates() {
        let today = Date()
        let snapshot = windowSnapshot(totalCost: 10, first: today, second: today.addingTimeInterval(-86_400))
        let cost = snapshot.costForWindow(days: 7)
        XCTAssertTrue(cost.estimated)
        XCTAssertEqual(cost.amount, 10.0, accuracy: 0.001)
    }

    func testCostForWindowAcrossMonthFallback() {
        let today = Date()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
        let snapshot = windowSnapshot(totalCost: 10, first: lastMonth, second: today)
        let cost = snapshot.costForWindow(days: 7)
        XCTAssertFalse(cost.estimated)
        XCTAssertEqual(cost.amount, 10.0, accuracy: 0.001)
    }

    // MARK: - Parsing

    func testParseUsageBucketsUseUTCDayNotLocalTimeZone() throws {
        // epoch 0 = 1970-01-01T00:00:00Z. Must land on Jan 1 UTC regardless of
        // the test machine's local time zone.
        let json = """
        {"data":{"biz_data":{"series":[{"model":"deepseek-chat","buckets":[
            {"time":0,"usage":{"REQUEST":1,"RESPONSE_TOKEN":100,"PROMPT_CACHE_HIT_TOKEN":0,"PROMPT_CACHE_MISS_TOKEN":0}}
        ]}]}}}
        """.data(using: .utf8)!

        let client = DiscoveredDashboardUsageClient(endpoint: .init(url: "", method: "GET", headers: [:], discoveredAt: Date()))
        let snapshot = try client.parseUsage(json, aggregateDays: 7)

        XCTAssertEqual(snapshot.dailyTotals.count, 1)
        let comps = utc.dateComponents([.year, .month, .day], from: snapshot.dailyTotals[0].date)
        XCTAssertEqual(comps.year, 1970)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
    }

    /// An export wants every day the platform returned; the dashboard trims to
    /// its 7/30-day view. Same payload, two answers.
    func testParseUsageAllDaysModeKeepsEveryDay() throws {
        let json = """
        {"data":{"biz_data":{"series":[{"model":"deepseek-chat","buckets":[
            {"time":0,"usage":{"REQUEST":1,"RESPONSE_TOKEN":100}},
            {"time":86400,"usage":{"REQUEST":1,"RESPONSE_TOKEN":200}},
            {"time":172800,"usage":{"REQUEST":1,"RESPONSE_TOKEN":300}}
        ]}]}}}
        """.data(using: .utf8)!

        let client = DiscoveredDashboardUsageClient(endpoint: .init(url: "", method: "GET", headers: [:], discoveredAt: Date()))
        let all = try client.parseUsage(json, aggregateDays: nil)
        XCTAssertEqual(all.dailyTotals.count, 3)
        XCTAssertEqual(all.totalTokens, 600)

        let trimmed = try client.parseUsage(json, aggregateDays: 1)
        XCTAssertEqual(trimmed.dailyTotals.count, 3)
        XCTAssertEqual(trimmed.totalTokens, 300)
    }

    // MARK: - Export range model

    private let now = Date(timeIntervalSince1970: 1_787_000_000) // fixed instant

    func testPresetLast7SpansSevenDaysEndingToday() {
        let range = ExportPreset.last7.resolve(now: now, calendar: utc)
        XCTAssertEqual(range.dayCount, 7)
        let today = utc.startOfDay(for: now)
        XCTAssertEqual(range.end, utc.date(byAdding: .day, value: 1, to: today)!)
        XCTAssertEqual(range.start, utc.date(byAdding: .day, value: -6, to: today)!)
    }

    func testPresetThisMonthStartsOnTheFirst() {
        let range = ExportPreset.thisMonth.resolve(now: now, calendar: utc)
        let comps = utc.dateComponents([.year, .month], from: now)
        XCTAssertEqual(range.start, utc.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!)
        XCTAssertEqual(range.dayCount, utc.dateComponents([.day], from: range.start, to: range.end).day ?? 0)
    }

    func testPresetLastMonthIsTheWholePreviousMonth() {
        let range = ExportPreset.lastMonth.resolve(now: now, calendar: utc)
        let comps = utc.dateComponents([.year, .month], from: now)
        let firstThisMonth = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!
        XCTAssertEqual(range.end, firstThisMonth)
        XCTAssertEqual(range.start, utc.date(byAdding: .month, value: -1, to: firstThisMonth)!)
        XCTAssertEqual(range.dayCount, utc.dateComponents([.day], from: range.start, to: range.end).day ?? 0)
    }

    func testCustomRangeTreatsBothPickedDaysAsInclusive() {
        let range = ExportPreset.custom.resolve(now: now, calendar: utc,
                                                customStart: utcDay(2026, 8, 1),
                                                customEnd: utcDay(2026, 8, 3))
        XCTAssertEqual(range.start, utcDay(2026, 8, 1))
        XCTAssertEqual(range.end, utcDay(2026, 8, 4))
        XCTAssertEqual(range.dayCount, 3)
    }

    func testCustomRangeWithReversedDatesCollapsesToOneDay() {
        let range = ExportPreset.custom.resolve(now: now, calendar: utc,
                                                customStart: utcDay(2026, 8, 10),
                                                customEnd: utcDay(2026, 8, 3))
        XCTAssertEqual(range.start, utcDay(2026, 8, 10))
        XCTAssertEqual(range.end, utcDay(2026, 8, 11))
        XCTAssertEqual(range.dayCount, 1)
    }

    func testCoveredMonthsFollowsAMonthBoundary() {
        let range = DateRange(start: utcDay(2026, 7, 28), end: utcDay(2026, 8, 3))
        XCTAssertEqual(range.coveredMonths(calendar: utc), [MonthKey(year: 2026, month: 7), MonthKey(year: 2026, month: 8)])
    }

    func testWholeMonthsSpanReachesBothMonthEdges() {
        let range = DateRange(start: utcDay(2026, 7, 28), end: utcDay(2026, 8, 3))
        let span = range.wholeMonthsSpan(calendar: utc)
        XCTAssertEqual(span.start, utcDay(2026, 7, 1))
        XCTAssertEqual(span.end, utcDay(2026, 9, 1))
    }

    func testPlannerReusesLoadedWindowWhenItCoversTheRange() {
        let loaded = DateRange(start: utcDay(2026, 8, 1), end: utcDay(2026, 8, 31))
        let inside = DateRange(start: utcDay(2026, 8, 5), end: utcDay(2026, 8, 9))
        XCTAssertEqual(ExportSource.plan(range: inside, loadedWindow: loaded, calendar: utc), .loaded)
    }

    func testPlannerFetchesWholeMonthsWhenOutsideLoadedWindow() {
        let loaded = DateRange(start: utcDay(2026, 8, 1), end: utcDay(2026, 8, 31))
        let outside = DateRange(start: utcDay(2026, 7, 5), end: utcDay(2026, 7, 9))
        guard case let .fetch(wholeMonths, months) = ExportSource.plan(range: outside, loadedWindow: loaded, calendar: utc) else {
            return XCTFail("expected a fetch plan")
        }
        XCTAssertEqual(months, [MonthKey(year: 2026, month: 7)])
        XCTAssertEqual(wholeMonths.start, utcDay(2026, 7, 1))
        XCTAssertEqual(wholeMonths.end, utcDay(2026, 8, 1))
    }

    func testPlannerFetchesWhenNothingIsLoaded() {
        let range = DateRange(start: utcDay(2026, 8, 5), end: utcDay(2026, 8, 9))
        guard case .fetch = ExportSource.plan(range: range, loadedWindow: nil, calendar: utc) else {
            return XCTFail("expected a fetch plan")
        }
    }

    // MARK: - Window rewriting

    func testWindowLiveFromToRewritesStartEndAndKeepsOtherParams() {
        let url = "https://platform.deepseek.com/api/v0/usage/by_api_key/amount?start=1&end=2&tz=0&foo=bar"
        let out = UsageWindow.live(url: url,
                                   from: Date(timeIntervalSince1970: 1_000_000),
                                   to: Date(timeIntervalSince1970: 1_086_400),
                                   timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertTrue(out.contains("start=1000000"))
        XCTAssertTrue(out.contains("end=1086400"))
        XCTAssertTrue(out.contains("foo=bar"))
        XCTAssertTrue(out.contains("tz="))
    }

    func testWindowLiveReturnsUntouchedURLWithoutAWindow() {
        let url = "https://platform.deepseek.com/api/v0/usage/total?foo=bar"
        XCTAssertEqual(UsageWindow.live(url: url, from: Date(), to: Date(), timeZone: .current), url)
    }

    // MARK: - Export bundle

    private func exportFixture(range: DateRange, window: [DailyUsage]) -> ExportBundle {
        ExportBundleBuilder.build(
            range: range,
            window: window,
            keyBreakdown: [KeyUsage(name: "Prod", maskedKeyId: "sk-1...9", tokens: 400, percentage: 100)],
            monthTokenTotals: [MonthKey(year: 2026, month: 8): 4000],
            bills: [MonthKey(year: 2026, month: 8): (cost: 40, currency: "USD")],
            generatedAt: utcDay(2026, 8, 4)
        )
    }

    private func augustRange() -> DateRange {
        DateRange(start: utcDay(2026, 8, 1), end: utcDay(2026, 8, 4)) // 3 days
    }

    /// The bill is monthly, so each day gets its share of the *whole month's*
    /// tokens — not of the exported slice.
    func testBundleAllocatesTheMonthlyBillByMonthTokens() {
        let bundle = exportFixture(range: augustRange(), window: [
            usage(utcDay(2026, 8, 1), tokens: 100, requests: 1),
            usage(utcDay(2026, 8, 2), tokens: 300, requests: 3),
            usage(utcDay(2026, 8, 3), tokens: 0),
        ])
        XCTAssertEqual(bundle.days.count, 3)
        // 40 of a 4000-token month, on days worth 100 and 300 tokens.
        XCTAssertEqual(bundle.days[0].estimatedCost, 1, accuracy: 0.0001)
        XCTAssertEqual(bundle.days[1].estimatedCost, 3, accuracy: 0.0001)
        XCTAssertEqual(bundle.allocatedCost, 4, accuracy: 0.0001)
        XCTAssertEqual(bundle.billedCost, 40, accuracy: 0.0001)
        XCTAssertEqual(bundle.currency, "USD")
    }

    /// A three-day slice of a 31-day month must not claim the entire bill.
    func testBundlePartialMonthDoesNotAbsorbTheWholeBill() {
        let bundle = exportFixture(range: augustRange(), window: [
            usage(utcDay(2026, 8, 1), tokens: 100),
            usage(utcDay(2026, 8, 2), tokens: 300),
        ])
        XCTAssertEqual(bundle.months.first?.partial, true)
        XCTAssertLessThan(bundle.allocatedCost, bundle.billedCost)
    }

    func testBundleFillsGapDaysWithZeroRows() {
        let bundle = exportFixture(range: augustRange(), window: [
            usage(utcDay(2026, 8, 1), tokens: 100),
            usage(utcDay(2026, 8, 3), tokens: 200),
        ])
        XCTAssertEqual(bundle.days.count, 3)
        XCTAssertEqual(bundle.days[1].tokens, 0)
        XCTAssertEqual(bundle.totalTokens, 300)
    }

    func testBundleWithoutAMonthTotalDoesNotDivideByZero() {
        let bundle = ExportBundleBuilder.build(
            range: augustRange(),
            window: [usage(utcDay(2026, 8, 1), tokens: 100)],
            keyBreakdown: [],
            monthTokenTotals: [:],
            bills: [MonthKey(year: 2026, month: 8): (cost: 40, currency: "USD")],
            generatedAt: utcDay(2026, 8, 4)
        )
        XCTAssertEqual(bundle.allocatedCost, 0)
        XCTAssertEqual(bundle.billedCost, 40, accuracy: 0.0001)
    }

    func testCSVHasOneRowPerRangeDayAndAStableHeader() {
        let bundle = exportFixture(range: augustRange(), window: [
            usage(utcDay(2026, 8, 1), tokens: 100, requests: 1),
            usage(utcDay(2026, 8, 2), tokens: 300, requests: 3),
            usage(utcDay(2026, 8, 3), tokens: 0),
        ])
        let lines = UsageExporter.csv(bundle).split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "date,tokens,requests,estimated_cost_usd")
        XCTAssertEqual(lines[1], "2026-08-01,100,1,1.0000")
        XCTAssertEqual(lines[3], "2026-08-03,0,0,0.0000")
    }

    func testJSONCarriesTheRangeTheMonthsAndTheLegacyKeys() throws {
        let bundle = exportFixture(range: augustRange(), window: [
            usage(utcDay(2026, 8, 1), tokens: 100, requests: 1),
            usage(utcDay(2026, 8, 2), tokens: 300, requests: 3),
            usage(utcDay(2026, 8, 3), tokens: 0),
        ])
        let data = try UsageExporter.json(bundle)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(root["dayCount"] as? Int, 3)
        XCTAssertEqual(root["windowDays"] as? Int, 3)
        XCTAssertEqual(root["billedMonthlyCost"] as? Double, 40)
        XCTAssertEqual(root["costAllocationIsEstimated"] as? Bool, true)
        XCTAssertEqual((root["daily"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((root["keys"] as? [[String: Any]])?.count, 1)

        let months = try XCTUnwrap(root["months"] as? [[String: Any]])
        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(months[0]["month"] as? String, "2026-08")
        XCTAssertEqual(months[0]["partial"] as? Bool, true)
        XCTAssertEqual(months[0]["billedCost"] as? Double, 40)
    }

    func testSuggestedFilenameStampsTheRange() {
        let bundle = exportFixture(range: augustRange(), window: [usage(utcDay(2026, 8, 1), tokens: 100)])
        XCTAssertEqual(UsageExporter.suggestedFilename(bundle, ext: "csv"),
                       "deepseek-usage-2026-08-01_to_2026-08-03.csv")
    }

    // MARK: - Notifications

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

    // MARK: - Retry backoff

    func testBackoffDoublesThenSaturatesAtCap() {
        var d = Backoff.initial
        var seq = [d]
        for _ in 0..<5 { d = Backoff.next(d); seq.append(d) }
        XCTAssertEqual(seq, [30, 60, 120, 240, 300, 300])
        XCTAssertEqual(Backoff.next(Backoff.cap), Backoff.cap)
    }

    // MARK: - Snapshot merge (partial-failure matrix)

    private func previousSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            totalCost: 3.24, totalRequests: 100, totalTokens: 1000, usageCurrency: "USD",
            dailyTotals: [DailyUsage(date: Date(timeIntervalSince1970: 0), totalTokens: 1000,
                                     totalCost: 0, totalRequests: 100, breakdown: [])],
            keyBreakdown: [KeyUsage(name: "Prod", maskedKeyId: "sk-1...9", tokens: 1000, percentage: 100)],
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
    }

    func testUsageOnlyPreservesPreviousCost() {
        let fresh = UsageSnapshot(totalCost: 0, totalRequests: 250, totalTokens: 5000,
                                  usageCurrency: "USD", dailyTotals: [], keyBreakdown: [],
                                  lastUpdated: Date())
        let merged = previousSnapshot().applying(usage: fresh, cost: nil)
        XCTAssertEqual(merged.totalCost, 3.24, accuracy: 0.0001)
        XCTAssertEqual(merged.totalTokens, 5000)
    }

    func testCostOnlyPreservesPreviousUsage() {
        let merged = previousSnapshot().applying(usage: nil, cost: (cost: 9.99, currency: "USD"))
        XCTAssertEqual(merged.totalCost, 9.99, accuracy: 0.0001)
        XCTAssertEqual(merged.totalTokens, 1000)
        XCTAssertEqual(merged.dailyTotals.count, 1)
        XCTAssertEqual(merged.keyBreakdown.count, 1)
    }

    func testZeroCostDoesNotOverwriteGoodCost() {
        let merged = previousSnapshot().applying(usage: nil, cost: (cost: 0, currency: "USD"))
        XCTAssertEqual(merged.totalCost, 3.24, accuracy: 0.0001)
    }

    func testApplyingNothingIsIdentity() {
        let prev = previousSnapshot()
        let merged = prev.applying(usage: nil, cost: nil)
        XCTAssertEqual(merged.totalCost, prev.totalCost)
        XCTAssertEqual(merged.totalTokens, prev.totalTokens)
        XCTAssertEqual(merged.dailyTotals.count, prev.dailyTotals.count)
    }

    // MARK: - Session renewal

    func testRenewalPolicyConsecutiveFailuresGate() {
        XCTAssertTrue(RenewalPolicy.shouldAttempt(consecutiveFailures: 0))
        XCTAssertTrue(RenewalPolicy.shouldAttempt(consecutiveFailures: 1))
        XCTAssertFalse(RenewalPolicy.shouldAttempt(consecutiveFailures: 2))
        XCTAssertFalse(RenewalPolicy.shouldAttempt(consecutiveFailures: 5))
    }

    func testRenewalPolicyCooldown() {
        let now = Date()
        XCTAssertTrue(RenewalPolicy.cooldownElapsed(since: nil, now: now))
        XCTAssertTrue(RenewalPolicy.cooldownElapsed(since: now.addingTimeInterval(-301), now: now))
        XCTAssertFalse(RenewalPolicy.cooldownElapsed(since: now.addingTimeInterval(-60), now: now))
    }

    func testInconclusiveOutcomesNeverSpendTheBudget() {
        var n = 0
        for _ in 0..<1000 { n = RenewalPolicy.nextFailureCount(n, after: .inconclusive) }
        XCTAssertEqual(n, 0)
        XCTAssertTrue(RenewalPolicy.shouldAttempt(consecutiveFailures: n))
    }

    func testAuthoritativeDeadSessionStopsAfterMax() {
        var d = 0
        d = RenewalPolicy.nextFailureCount(d, after: .sessionDead)
        XCTAssertTrue(RenewalPolicy.shouldAttempt(consecutiveFailures: d))
        d = RenewalPolicy.nextFailureCount(d, after: .sessionDead)
        XCTAssertEqual(d, RenewalPolicy.maxConsecutiveFailures)
        XCTAssertFalse(RenewalPolicy.shouldAttempt(consecutiveFailures: d))
    }

    func testNoiseAroundRealVerdictDoesNotAccelerateLockout() {
        var m = 0
        for o in [RenewalOutcome.inconclusive, .sessionDead, .inconclusive, .inconclusive] {
            m = RenewalPolicy.nextFailureCount(m, after: o)
        }
        XCTAssertEqual(m, 1)
        XCTAssertTrue(RenewalPolicy.shouldAttempt(consecutiveFailures: m))
    }

    func testRenewedResetsFailureCount() {
        XCTAssertEqual(RenewalPolicy.nextFailureCount(1, after: .renewed), 0)
    }

    // MARK: - Balance merge

    func testBalanceMergeWritesWhenCurrencyPresent() {
        let merged = previousSnapshot().applying(usage: nil, cost: nil, balance: (amount: 9.99, currency: "CNY"))
        XCTAssertEqual(merged.balanceAmount, 9.99, accuracy: 0.0001)
        XCTAssertEqual(merged.balanceCurrency, "CNY")
    }

    func testBalanceMergeEmptyCurrencyKeepsPrevious() {
        var prev = previousSnapshot()
        prev.balanceAmount = 5
        prev.balanceCurrency = "USD"
        let merged = prev.applying(usage: nil, cost: nil, balance: (amount: 0, currency: ""))
        XCTAssertEqual(merged.balanceAmount, 5, accuracy: 0.0001)
        XCTAssertEqual(merged.balanceCurrency, "USD")
    }
}
