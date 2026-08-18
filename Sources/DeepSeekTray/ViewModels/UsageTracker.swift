import SwiftUI
import Combine

@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published var snapshot: UsageSnapshot = .empty
    @Published var currentView: PopoverView = .auth
    @Published var lastError: String?
    @Published var trayLabelText: String = "DS: --"

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let preferences = PreferencesStore.shared
    private let auth = AuthManager.shared

    private init() {
        snapshot = .empty
        updateTrayLabelText(style: preferences.trayDisplayStyle)

        if auth.state.googleSessionLinked {
            currentView = preferences.compactMiniDefault ? .mini : .dashboard
        } else {
            currentView = .auth
        }

        preferences.$refreshInterval
            .sink { [weak self] interval in self?.startPolling(interval: interval) }
            .store(in: &cancellables)

        preferences.$trayDisplayStyle
            .sink { [weak self] style in self?.updateTrayLabelText(style: style) }
            .store(in: &cancellables)

        preferences.$extendedViewStyle
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)

        startPolling(interval: preferences.refreshInterval)
        // Fetch immediately at launch — the poll timer only fires after the
        // first refreshInterval elapses, leaving the dashboard blank until then.
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    func show(_ view: PopoverView) {
        currentView = view
    }

    func refresh() async {
        // Best-effort dashboard usage via the discovered endpoint (if any).
        var usage: UsageSnapshot?
        var cost: (cost: Double, currency: String)?
        var isUnauthorized = false
        var fetchError: String?

        if let endpoint = DiscoveredDashboardUsageClient.loadEndpoint() {
            let client = DiscoveredDashboardUsageClient(endpoint: endpoint)

            do {
                usage = try await client.fetchUsage(days: preferences.extendedViewStyle.days)
            } catch DashboardFetchError.unauthorized {
                isUnauthorized = true
            } catch {
                fetchError = error.localizedDescription
            }

            do {
                cost = try await client.fetchCost()
            } catch DashboardFetchError.unauthorized {
                isUnauthorized = true
            } catch {
                if fetchError == nil { fetchError = error.localizedDescription }
            }
        }

        await MainActor.run { [usage, cost, isUnauthorized, fetchError] in
            if isUnauthorized {
                auth.signOut()
                if !auth.state.googleSessionLinked {
                    currentView = .auth
                }
                return
            }

            if usage != nil || cost != nil {
                var merged = snapshot
                if let usage {
                    // totalCost is deliberately NOT copied from usage: parseUsage
                    // never sets it (usage payload is token-only), so it would
                    // always write 0 and clobber the previous valid cost when the
                    // cost endpoint fails. Cost comes only from fetchCost() below.
                    merged.totalRequests = usage.totalRequests
                    merged.totalTokens = usage.totalTokens
                    merged.dailyTotals = usage.dailyTotals
                    merged.keyBreakdown = usage.keyBreakdown
                }
                // Note: `cost.cost > 0` also skips a legitimate $0 month — the
                // previous value stays visible until a non-zero bill arrives.
                if let cost, cost.cost > 0 {
                    merged.totalCost = cost.cost
                    merged.usageCurrency = cost.currency
                }
                snapshot = merged
                lastError = nil
                snapshot.lastUpdated = Date()
            } else if let fetchError {
                lastError = fetchError
            }

            if !auth.state.googleSessionLinked {
                currentView = .auth
            }
            updateTrayLabelText(style: preferences.trayDisplayStyle)
        }
    }

    func updateTrayLabelText(style: TrayDisplayStyle) {
        let prefix = "DS:"
        switch style {
        case .hourly:
            let tokens = snapshot.dailyTotals.last?.totalTokens ?? 0
            trayLabelText = "\(prefix) \(TokenFormatter.short(tokens))/day"
        case .monthly:
            let monthlyTokens = snapshot.dailyTotals.reduce(0) { $0 + $1.totalTokens }
            trayLabelText = "\(prefix) \(TokenFormatter.short(monthlyTokens))"
        case .cost:
            let symbol = currencySymbol(snapshot.usageCurrency)
            trayLabelText = "\(prefix) \(symbol)\(String(format: "%.2f", snapshot.totalCost))"
        }
    }

    private func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default: return ""
        }
    }

    func startPolling(interval: RefreshInterval) {
        timer?.invalidate()
        let seconds = Double(interval.minutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    deinit { timer?.invalidate() }
}
