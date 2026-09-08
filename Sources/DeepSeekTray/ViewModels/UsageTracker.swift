import SwiftUI
import Combine
import Network

/// Best-effort JWT `exp` read (no signature verification — diagnostics only).
enum JWT {
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (obj["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published var snapshot: UsageSnapshot = .empty
    @Published var currentView: PopoverView = .auth
    @Published var lastError: String?
    @Published var trayLabelText: String = "DS: --"

    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var retryTask: Task<Void, Never>?
    private var retryDelay: Double = Backoff.initial
    private var wasOffline = false
    private var renewalInFlight = false
    private var lastRenewalAttempt: Date?
    private var consecutiveRenewalFailures = 0
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

        // Launch diagnostics: the half-a-session state (token without endpoint)
        // is the "Linked but data never updates" bug; log it if present.
        if let jwt = KeychainManager.get(account: "googleToken") {
            let hasEndpoint = DiscoveredDashboardUsageClient.loadEndpoint() != nil
            print("[UsageTracker] launch state: token present, endpoint \(hasEndpoint ? "present" : "MISSING")")
            if let exp = JWT.expiry(of: jwt) {
                let left = exp.timeIntervalSinceNow
                let text = left > 0 ? "expires in \(max(1, Int(left / 3600)))h" : "expired \(max(1, Int(-left / 3600)))h ago"
                print("[UsageTracker] googleToken \(text) (\(exp))")
            }
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
        startPathMonitor()
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
        await refreshOnce(allowRenewalRetry: true)
    }

    /// Self-heals a lost session before fetching: a token with no discovered
    /// endpoint silently re-captures both; a 401/403 (expired token) silently
    /// re-captures once and retries the fetch. Interactive sign-out is the
    /// fallback only when silent renewal fails.
    private func refreshOnce(allowRenewalRetry: Bool) async {
        if DiscoveredDashboardUsageClient.loadEndpoint() == nil,
           KeychainManager.get(account: "googleToken") != nil {
            print("[UsageTracker] token present but endpoint missing — attempting silent session renewal")
            _ = await attemptSilentRenewal(respectCooldown: true)
        }

        // Best-effort dashboard usage via the discovered endpoint (if any).
        var usage: UsageSnapshot?
        var cost: (cost: Double, currency: String)?
        var balance: (amount: Double, currency: String)?
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

        if let balanceEndpoint = DiscoveredDashboardUsageClient.loadBalanceEndpoint() {
            let client = DiscoveredDashboardUsageClient(endpoint: balanceEndpoint)
            do {
                balance = try await client.fetchBalance()
            } catch DashboardFetchError.unauthorized {
                isUnauthorized = true
            } catch {
                if fetchError == nil { fetchError = error.localizedDescription }
            }
        }

        // Expired/invalid token: attempt one silent re-capture before the
        // existing sign-out path nukes the session.
        // A 401 alone is not grounds for sign-out: the token may be expired while
        // the cookie session behind it is still perfectly good.
        var signOutOnUnauthorized = isUnauthorized
        if isUnauthorized, allowRenewalRetry {
            switch await attemptSilentRenewal(respectCooldown: false) {
            case .renewed:
                print("[UsageTracker] session renewed after 401 — refreshing once more")
                await refreshOnce(allowRenewalRetry: false)
                return
            case .inconclusive:
                // Couldn't tell (offline/timeout). Keep the token and let the
                // existing backoff + NWPathMonitor retry rather than burning it.
                print("[UsageTracker] renewal inconclusive after 401 — keeping session, will retry")
                signOutOnUnauthorized = false
            case .sessionDead:
                break
            }
        }

        await MainActor.run { [usage, cost, balance, signOutOnUnauthorized, isUnauthorized, fetchError] in
            if signOutOnUnauthorized {
                clearRetry()
                auth.signOut()
                if !auth.state.googleSessionLinked {
                    currentView = .auth
                }
                return
            }

            if usage != nil || cost != nil || balance != nil {
                // A real fetch succeeded — the session is healthy again.
                consecutiveRenewalFailures = 0
                snapshot = snapshot.applying(usage: usage, cost: cost, balance: balance)
                snapshot.lastUpdated = Date()
                if let cost, cost.cost > 0 {
                    NotificationManager.checkBudget(cost: cost.cost, budget: preferences.monthlyBudget, currencySymbol: currencySymbol(cost.currency))
                }
            }

            // Assigned unconditionally: keying this off "did anything succeed"
            // swallowed the error whenever one of the two calls failed and the
            // other did not, leaving stale data looking fresh.
            // A held 401 (renewal inconclusive) sets no fetchError, so without
            // this the UI would show stale numbers behind a healthy green dot.
            let heldUnauthorized = isUnauthorized && !signOutOnUnauthorized
            lastError = fetchError ?? (heldUnauthorized ? "Session needs renewing — retrying in the background." : nil)
            if let fetchError { print("[UsageTracker] fetch failed: \(fetchError)") }

            if fetchError == nil && !heldUnauthorized { clearRetry() } else { scheduleRetry() }

            if !auth.state.googleSessionLinked {
                currentView = .auth
            }
            updateTrayLabelText(style: preferences.trayDisplayStyle)
        }
    }

    // MARK: - Retry

    /// Retries after the current backoff delay, then widens it.
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = Backoff.next(retryDelay)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Retries at once — the network just came back, no reason to wait.
    private func retryNow() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    private func clearRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryDelay = Backoff.initial
    }

    // MARK: - Session renewal

    /// One silent WebKit re-capture of a fresh token + endpoint.
    /// `respectCooldown: true` throttles the proactive (endpoint-lost) path so it
    /// cannot spawn a webview on every poll; 401-driven attempts bypass the
    /// cooldown but are still capped by `RenewalPolicy.maxConsecutiveFailures`.
    private func attemptSilentRenewal(respectCooldown: Bool) async -> RenewalOutcome {
        // Budget exhausted by authoritative verdicts: the session really is gone.
        guard RenewalPolicy.shouldAttempt(consecutiveFailures: consecutiveRenewalFailures) else {
            return .sessionDead
        }
        // No network: a renewal here can only time out and would tell us nothing.
        guard !wasOffline else { return .inconclusive }
        guard !renewalInFlight,
              !respectCooldown || RenewalPolicy.cooldownElapsed(since: lastRenewalAttempt),
              KeychainManager.get(account: "googleToken") != nil else { return .inconclusive }
        renewalInFlight = true
        lastRenewalAttempt = Date()
        defer { renewalInFlight = false }
        let outcome = await auth.renewSession()
        consecutiveRenewalFailures = RenewalPolicy.nextFailureCount(consecutiveRenewalFailures, after: outcome)
        print("[UsageTracker] silent session renewal: \(outcome) (consecutive dead-session verdicts: \(consecutiveRenewalFailures))")
        return outcome
    }

    /// Refreshes on the offline → online edge only. Without the `wasOffline`
    /// guard every path change (Wi-Fi ⇄ Ethernet, VPN up/down) would fetch, and
    /// the handler's immediate first callback would duplicate the launch fetch.
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !satisfied {
                    self.wasOffline = true
                } else if self.wasOffline {
                    self.wasOffline = false
                    self.retryNow()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.deepseek.tray.pathmonitor"))
        pathMonitor = monitor
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
        case .todayCost:
            let symbol = currencySymbol(snapshot.usageCurrency)
            let today = snapshot.costForWindow(days: 1).amount
            trayLabelText = "\(prefix) \(symbol)\(String(format: "%.2f", today))/day"
        case .balance:
            guard !snapshot.balanceCurrency.isEmpty else {
                trayLabelText = "\(prefix) --"
                return
            }
            let symbol = currencySymbol(snapshot.balanceCurrency)
            trayLabelText = "\(prefix) \(symbol)\(String(format: "%.2f", snapshot.balanceAmount))"
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

    deinit {
        timer?.invalidate()
        pathMonitor?.cancel()
        retryTask?.cancel()
    }
}
