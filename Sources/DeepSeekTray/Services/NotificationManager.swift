import Foundation
import UserNotifications

enum NotificationManager {
    /// Percent of monthly budget at which to alert.
    static let thresholds = [80, 100]

    /// Year-month key scoping the de-dupe; re-arms automatically on rollover.
    static func monthKey(date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    /// Pure logic: thresholds crossed by `cost`, minus those already fired this month.
    static func pendingThresholds(cost: Double, budget: Double, alreadyFired: [String]) -> [Int] {
        guard budget > 0, cost > 0 else { return [] }
        return thresholds.filter { cost >= budget * Double($0) / 100 && !alreadyFired.contains("\($0)") }
    }

    /// Prompts once, only while .notDetermined (Apple's "prompt once" behavior).
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Fires a banner per newly-crossed threshold; returns true if anything was scheduled.
    @discardableResult
    static func checkBudget(cost: Double, budget: Double, currencySymbol: String) -> Bool {
        let key = "ds_notified_thresholds_\(monthKey())"
        // ponytail: raising the budget mid-month after firing won't re-alert until
        // rollover (already-fired guard) — acceptable for v1.
        var fired = UserDefaults.standard.stringArray(forKey: key) ?? []
        let pending = pendingThresholds(cost: cost, budget: budget, alreadyFired: fired)
        guard !pending.isEmpty else { return false }
        requestAuthorizationIfNeeded()
        for t in pending {
            let content = UNMutableNotificationContent()
            content.title = "DeepSeek Budget Alert"
            content.body = String(format: "You've used %.0f%% of your %@%.2f monthly budget.",
                                  (cost / budget) * 100, currencySymbol, budget)
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
            fired.append("\(t)")
        }
        UserDefaults.standard.set(fired, forKey: key)
        return true
    }
}
