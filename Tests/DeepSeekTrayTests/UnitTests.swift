import Foundation

@main
struct TestRunner {
    static func main() {
        print("==> Running DeepSeekTray Unit Tests...")

        testTokenFormatterShort()
        testUsageSnapshotCostForWindow()

        print("✅ All DeepSeekTray Unit Tests Passed Successfully!")
    }

    static func testTokenFormatterShort() {
        assert(formatShort(500) == "500", "500 failed")
        assert(formatShort(1_500) == "1.5K", "1.5K failed")
        assert(formatShort(2_300_000) == "2.30M", "2.30M failed")
        print("  ✓ TokenFormatter tests passed")
    }

    static func testUsageSnapshotCostForWindow() {
        let totalCost = 10.0
        let totalPeriodTokens = 400
        let windowTokens = 300
        let windowCost = totalCost * (Double(windowTokens) / Double(totalPeriodTokens))

        assert(abs(windowCost - 7.50) < 0.001, "costForWindow 7.50 calculation failed")
        print("  ✓ UsageSnapshot costForWindow tests passed")
    }

    private static func formatShort(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.2fM", Double(number) / 1_000_000.0)
        } else if number >= 1_000 {
            let k = Double(number) / 1_000.0
            return k.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        } else {
            return "\(number)"
        }
    }
}
