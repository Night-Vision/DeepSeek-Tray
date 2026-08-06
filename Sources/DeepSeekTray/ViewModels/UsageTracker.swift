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
        updateTrayLabelText()

        if auth.state.apiKeyLinked || auth.state.googleSessionLinked {
            currentView = preferences.compactMiniDefault ? .mini : .dashboard
        }

        preferences.$refreshInterval
            .sink { [weak self] _ in self?.startPolling() }
            .store(in: &cancellables)

        preferences.$trayDisplayStyle
            .sink { [weak self] _ in self?.updateTrayLabelText() }
            .store(in: &cancellables)

        startPolling()
    }

    func show(_ view: PopoverView) {
        currentView = view
    }

    func refresh() async {
        let key = KeychainManager.get(account: "apiKey")
        let cookie = KeychainManager.get(account: "sessionCookie")

        async let balanceTask: BalanceInfo? = {
            if let key = key, !key.isEmpty {
                try? await OfficialBalanceClient(apiKey: key).fetchBalance()
            } else { nil }
        }()

        async let usageTask: UsageSnapshot? = {
            if let cookie = cookie, !cookie.isEmpty {
                try await WebDashboardUsageClient(sessionCookie: cookie).fetchUsage()
            } else { nil }
        }()

        do {
            let balance = await balanceTask
            let usage = try await usageTask

            await MainActor.run { [balance, usage] in
                var merged = usage ?? .empty
                if let balance = balance {
                    merged.balance = balance
                }
                snapshot = merged
                lastError = nil
                updateTrayLabelText()
                snapshot.lastUpdated = Date()
            }
        } catch UsageClientError.authenticationExpired {
            await MainActor.run {
                auth.signOut(method: "sessionCookie")
                lastError = "Session expired. Please sign in again."
                appendToLastErrorLog(lastError ?? "")
                snapshot.lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                appendToLastErrorLog(lastError ?? "")
                snapshot.lastUpdated = Date()
            }
        }
    }

    private static var lastErrorLogURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeepSeekTray", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-error.txt")
    }

    private func appendToLastErrorLog(_ message: String) {
        let line = "\(Date())\t\(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: Self.lastErrorLogURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: Self.lastErrorLogURL, options: .atomic)
            }
        }
    }

    func updateTrayLabelText() {
        let style = preferences.trayDisplayStyle
        let prefix = "DS:"
        switch style {
        case .hourly:
            let tokens = snapshot.hourlyTotalsToday.last?.tokens ?? 0
            trayLabelText = "\(prefix) \(TokenFormatter.short(tokens))/h"
        case .monthly:
            trayLabelText = "\(prefix) \(TokenFormatter.short(snapshot.totalTokens))"
        case .cost:
            trayLabelText = "\(prefix) $\(String(format: "%.2f", snapshot.totalCost))"
        }
    }

    func startPolling() {
        timer?.invalidate()
        let interval = Double(preferences.refreshInterval.minutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    deinit { timer?.invalidate() }
}
