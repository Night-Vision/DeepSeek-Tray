import Foundation
import OSLog

protocol UsageClient {
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageClientError: Error {
    case authenticationExpired
}

struct WebDashboardUsageClient: UsageClient {
    private static let log = Logger(subsystem: "com.deepseek.tray", category: "WebDashboardUsageClient")
    private static let defaultEndpoint = URL(string: "https://platform.deepseek.com/api/v0/users/usage")!
    private let sessionCookie: String

    init(sessionCookie: String) {
        self.sessionCookie = sessionCookie
    }

    var endpointURL: URL {
        UserDefaults.standard.string(forKey: "ds_usage_endpoint")
            .flatMap(URL.init(string:))
            ?? Self.defaultEndpoint
    }

    func fetchUsage() async throws -> UsageSnapshot {
        var request = URLRequest(url: endpointURL)
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        Self.log.debug("Usage response status: \(http.statusCode)")
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
        Self.log.debug("Usage response body: \(preview, privacy: .private)")

        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageClientError.authenticationExpired
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(RawUsageResponse.self, from: data)
        return map(raw)
    }

    private func map(_ raw: RawUsageResponse) -> UsageSnapshot {
        let data = raw.data ?? RawUsageData(total_cost: 0, total_requests: 0, total_tokens: 0, daily_stats: [])
        let daily = (data.daily_stats ?? []).map { day in
            DailyUsage(
                date: Date(timeIntervalSince1970: Double(day.timestamp ?? 0)),
                totalTokens: day.tokens ?? 0,
                totalCost: day.cost ?? 0,
                totalRequests: day.requests ?? 0,
                breakdown: (day.breakdown ?? []).map { UsageBreakdown(category: $0.category, tokens: $0.tokens, cost: $0.cost) }
            )
        }
        return UsageSnapshot(
            balance: nil,
            totalCost: data.total_cost ?? 0,
            totalRequests: data.total_requests ?? 0,
            totalTokens: data.total_tokens ?? 0,
            usageCurrency: "USD",
            dailyTotals: daily,
            hourlyTotalsToday: [],
            keyBreakdown: [],
            lastUpdated: Date()
        )
    }
}

private struct RawUsageResponse: Decodable {
    let code: Int?
    let data: RawUsageData?
}

private struct RawUsageData: Decodable {
    let total_cost: Double?
    let total_requests: Int?
    let total_tokens: Int?
    let daily_stats: [RawDailyStat]?
}

private struct RawDailyStat: Decodable {
    let timestamp: Int?
    let cost: Double?
    let requests: Int?
    let tokens: Int?
    let breakdown: [RawBreakdown]?
}

private struct RawBreakdown: Decodable {
    let category: String
    let tokens: Int
    let cost: Double
}
