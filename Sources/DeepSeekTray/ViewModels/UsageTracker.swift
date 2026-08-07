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
    private let sessionTracker = SessionUsageTracker.shared

    private init() {
        snapshot = .empty
        updateTrayLabelText(style: preferences.trayDisplayStyle)

        if auth.state.apiKeyLinked || auth.state.googleSessionLinked {
            currentView = preferences.compactMiniDefault ? .mini : .dashboard
        }

        preferences.$refreshInterval
            .sink { [weak self] interval in self?.startPolling(interval: interval) }
            .store(in: &cancellables)

        preferences.$trayDisplayStyle
            .sink { [weak self] style in self?.updateTrayLabelText(style: style) }
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
        let key = KeychainManager.get(account: "apiKey")

        var balanceError: String?
        let balance: BalanceInfo?
        if let key = key, !key.isEmpty {
            do {
                balance = try await OfficialBalanceClient(apiKey: key).fetchBalance()
            } catch {
                balance = nil
                balanceError = error.localizedDescription
            }
        } else {
            balance = nil
        }

        // Best-effort dashboard usage via the discovered endpoint (if any).
        // Failure keeps .empty usage defaults and never clobbers balanceError.
        var usage: UsageSnapshot?
        var cost: (cost: Double, currency: String)?
        if let endpoint = DiscoveredDashboardUsageClient.loadEndpoint() {
            let cookie = KeychainManager.get(account: "sessionCookie")
            let client = DiscoveredDashboardUsageClient(endpoint: endpoint, cookie: cookie)
            usage = try? await client.fetchUsage()
            cost = try? await client.fetchCost()
        }

        await MainActor.run { [balance, balanceError, usage, cost] in
            var merged = UsageSnapshot.empty
            merged.balance = balance
            sessionTracker.currentModel = preferences.activeModelProfile
            merged.liveSession = sessionTracker.currentSession
            merged.currentModelProfile = preferences.activeModelProfile

            if let usage {
                merged.totalCost = usage.totalCost
                merged.totalRequests = usage.totalRequests
                merged.totalTokens = usage.totalTokens
                merged.dailyTotals = usage.dailyTotals
                merged.hourlyTotalsToday = usage.hourlyTotalsToday
                merged.keyBreakdown = usage.keyBreakdown
            }
            if let cost, cost.cost > 0 {
                merged.totalCost = cost.cost
                merged.usageCurrency = cost.currency
            }

            snapshot = merged
            lastError = balanceError
            updateTrayLabelText(style: preferences.trayDisplayStyle)
            snapshot.lastUpdated = Date()
        }
    }

    // Make a chat completion call and track its usage in real time (Reasonix-style)
    func sendChat(messages: [ChatMessage], model: String? = nil) async throws -> ChatCompletionResponse {
        guard let apiKey = KeychainManager.get(account: "apiKey"), !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let service = ChatCompletionService(apiKey: apiKey)
        let selectedModel = model ?? preferences.activeModelProfile.modelId
        let response = try await service.send(messages: messages, model: selectedModel)

        sessionTracker.recordTurn(from: response)
        sessionTracker.currentModel = preferences.activeModelProfile
        var updated = snapshot
        updated.liveSession = sessionTracker.currentSession
        updated.currentModelProfile = preferences.activeModelProfile
        updated.lastUpdated = Date()
        snapshot = updated
        return response
    }

    func updateTrayLabelText(style: TrayDisplayStyle) {
        let prefix = "DS:"
        switch style {
        case .hourly:
            let tokens = snapshot.dailyTotals.last?.totalTokens ?? 0
            trayLabelText = "\(prefix) \(TokenFormatter.short(tokens))/day"
        case .monthly:
            trayLabelText = "\(prefix) \(TokenFormatter.short(snapshot.totalTokens))"
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
