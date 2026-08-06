import Foundation

enum TrayDisplayStyle: String, CaseIterable, Identifiable {
    case hourly, monthly, cost
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hourly: return "Hourly Tokens"
        case .monthly: return "Monthly Tokens"
        case .cost: return "Est. Cost"
        }
    }
}

enum RefreshInterval: String, CaseIterable, Identifiable {
    case five = "5"
    case fifteen = "15"
    case sixty = "60"
    var id: String { rawValue }
    var minutes: Int { Int(rawValue) ?? 15 }
}

final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var refreshInterval: RefreshInterval = .fifteen {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }

    @Published var trayDisplayStyle: TrayDisplayStyle = .hourly {
        didSet { UserDefaults.standard.set(trayDisplayStyle.rawValue, forKey: "trayDisplayStyle") }
    }

    @Published var launchAtLogin: Bool = false {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    @Published var compactMiniDefault: Bool = false {
        didSet { UserDefaults.standard.set(compactMiniDefault, forKey: "compactMiniDefault") }
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
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        compactMiniDefault = UserDefaults.standard.bool(forKey: "compactMiniDefault")
    }
}
