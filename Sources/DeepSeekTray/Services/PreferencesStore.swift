import Foundation

enum TrayDisplayStyle: String, CaseIterable, Identifiable {
    case hourly, monthly, cost, todayCost
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hourly: return "Today's Tokens"
        case .monthly: return "Window Tokens"
        case .cost: return "Est. Cost"
        case .todayCost: return "Today's Cost"
        }
    }
}

enum RefreshInterval: String, CaseIterable, Identifiable {
    case one = "1"
    case five = "5"
    case fifteen = "15"
    case sixty = "60"
    var id: String { rawValue }
    var minutes: Int { Int(rawValue) ?? 15 }
}

enum ExtendedViewStyle: String, CaseIterable, Identifiable {
    case sevenDays = "7"
    case thirtyDays = "30"
    var id: String { rawValue }
    var days: Int { Int(rawValue) ?? 7 }
    var label: String {
        switch self {
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        }
    }
}

final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var refreshInterval: RefreshInterval = .fifteen {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }

    @Published var trayDisplayStyle: TrayDisplayStyle = .hourly {
        didSet { UserDefaults.standard.set(trayDisplayStyle.rawValue, forKey: "trayDisplayStyle") }
    }

    @Published var extendedViewStyle: ExtendedViewStyle = .sevenDays {
        didSet { UserDefaults.standard.set(extendedViewStyle.rawValue, forKey: "extendedViewStyle") }
    }

    @Published var launchAtLogin: Bool = false {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    @Published var compactMiniDefault: Bool = false {
        didSet { UserDefaults.standard.set(compactMiniDefault, forKey: "compactMiniDefault") }
    }

    @Published var monthlyBudget: Double = 0 {
        didSet { UserDefaults.standard.set(monthlyBudget, forKey: "monthlyBudget") }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "refreshInterval"),
           let value = RefreshInterval(rawValue: raw) {
            refreshInterval = value
        }
        if let raw = UserDefaults.standard.string(forKey: "trayDisplayStyle"),
           let value = TrayDisplayStyle(rawValue: raw) {
            trayDisplayStyle = value
        }
        if let raw = UserDefaults.standard.string(forKey: "extendedViewStyle"),
           let value = ExtendedViewStyle(rawValue: raw) {
            extendedViewStyle = value
        }
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        compactMiniDefault = UserDefaults.standard.bool(forKey: "compactMiniDefault")
        monthlyBudget = UserDefaults.standard.double(forKey: "monthlyBudget")
    }
}
