import Foundation

// Replays the usage API call captured by WebSSOSheet's JS interceptor.
// The current platform schema is data.biz_data.series[].buckets[] with
// {time, usage: {REQUEST, RESPONSE_TOKEN, PROMPT_CACHE_HIT_TOKEN,
// PROMPT_CACHE_MISS_TOKEN}} — see parseUsage.
struct DiscoveredDashboardUsageClient {
    struct DiscoveredEndpoint: Codable {
        let url: String
        let method: String
        let headers: [String: String]
        let discoveredAt: Date
    }

    static let storageKey = "ds_discovered_usage_endpoint"

    let endpoint: DiscoveredEndpoint
    let cookie: String?

    // MARK: - Storage

    static func saveEndpoint(_ endpoint: DiscoveredEndpoint) {
        // Security: never persist the live credential — the authorization
        // (Bearer JWT) / cookie headers are re-injected from Keychain at fetch
        // time. Keep only non-secret x-client-* headers.
        let sanitized = DiscoveredEndpoint(
            url: endpoint.url,
            method: endpoint.method,
            headers: endpoint.headers.filter { (name, _) in
                let lower = name.lowercased()
                return lower != "authorization" && lower != "cookie" && lower != "set-cookie"
            },
            discoveredAt: endpoint.discoveredAt
        )
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func loadEndpoint() -> DiscoveredEndpoint? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let endpoint = try? JSONDecoder().decode(DiscoveredEndpoint.self, from: data) else {
            return nil
        }
        return endpoint
    }

    // MARK: - Auth header injection

    /// The credential is never stored with the endpoint: the Bearer JWT lives in
    /// Keychain (googleToken). Inject it at fetch time, falling back to any
    /// non-secret captured headers (x-client-*) that the platform still requires.
    private func authHeaders() -> [String: String] {
        var headers = endpoint.headers
        if !headers.keys.contains(where: { $0.lowercased() == "authorization" }),
           let jwt = KeychainManager.get(account: "googleToken") {
            headers["Authorization"] = jwt
        }
        return headers
    }

    // MARK: - Fetch

    func fetchUsage() async throws -> UsageSnapshot {
        // The interceptor captures relative URLs (e.g. /api/v0/usage/...);
        // resolve them against the platform host.
        let resolved = endpoint.url.hasPrefix("http") ? endpoint.url : "https://platform.deepseek.com" + endpoint.url
        guard let url = URL(string: resolved) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 10
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        for (name, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.resourceUnavailable)
        }
        return try parseUsage(data)
    }

    /// Monthly spend in dollars from the platform's billing API:
    /// /api/v0/usage/cost?month=M&year=Y — returns biz_data[].total[].usage[]
    /// with {type, amount} strings + a currency field.
    func fetchCost() async throws -> (cost: Double, currency: String) {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let year = calendar.component(.year, from: Date())
        guard let url = URL(string: "https://platform.deepseek.com/api/v0/usage/cost?month=\(month)&year=\(year)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (name, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let bizData = dataObj["biz_data"] as? [[String: Any]] else {
            throw URLError(.cannotDecodeContentData)
        }
        var total = 0.0
        var currency = ""
        for entry in bizData {
            if currency.isEmpty, let c = entry["currency"] as? String { currency = c }
            for model in (entry["total"] as? [[String: Any]] ?? []) {
                for usage in (model["usage"] as? [[String: Any]] ?? []) {
                    if let amount = usage["amount"] as? String, let value = Double(amount) {
                        total += value
                    }
                }
            }
        }
        return (total, currency)
    }

    // MARK: - Parsing (platform schema: data.biz_data.series[].buckets[])

    private func parseUsage(_ data: Data) throws -> UsageSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let bizData = dataObj["biz_data"] as? [String: Any],
              let series = bizData["series"] as? [[String: Any]] else {
            throw URLError(.cannotDecodeContentData)
        }

        var snapshot = UsageSnapshot.empty

        // Raw buckets across every series.
        var rawBuckets: [(time: Int, tokens: Int, requests: Int, model: String)] = []
        for item in series {
            let model = (item["model"] as? String) ?? "model"
            for bucket in (item["buckets"] as? [[String: Any]] ?? []) {
                guard let time = (bucket["time"] as? NSNumber)?.intValue,
                      let usage = bucket["usage"] as? [String: Any] else { continue }
                let requests = intVal(usage["REQUEST"])
                let tokens = intVal(usage["RESPONSE_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_HIT_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_MISS_TOKEN"])
                rawBuckets.append((time, tokens, requests, model))
            }
        }

        // Daily totals — buckets are day-granularity (epoch steps of 86400).
        let calendar = Calendar(identifier: .gregorian)
        var byDay: [Date: (tokens: Int, requests: Int)] = [:]
        var byDayModel: [Date: [String: Int]] = [:]
        for bucket in rawBuckets {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(bucket.time)))
            let prev = byDay[day, default: (0, 0)]
            byDay[day] = (prev.tokens + bucket.tokens, prev.requests + bucket.requests)
            byDayModel[day, default: [:]][bucket.model, default: 0] += bucket.tokens
        }
        snapshot.dailyTotals = byDay
            .sorted { $0.key < $1.key }
            .map { day in
                let breakdown = (byDayModel[day.key] ?? [:])
                    .sorted { $0.value > $1.value }
                    .map { UsageBreakdown(category: $0.key, tokens: $0.value, cost: 0) }
                return DailyUsage(date: day.key, totalTokens: day.value.tokens, totalCost: 0, totalRequests: day.value.requests, breakdown: breakdown)
            }

        // 7-day rolling window totals for StatCards and key breakdown.
        let last7 = Array(snapshot.dailyTotals.suffix(7))
        let window7Dates = Set(last7.map { $0.date })
        snapshot.totalTokens = last7.reduce(0) { $0 + $1.totalTokens }
        snapshot.totalRequests = last7.reduce(0) { $0 + $1.totalRequests }

        // Per-key breakdown filtered strictly to the 7-day window.
        var byKey: [String: (name: String, tokens: Int)] = [:]
        for item in series {
            guard let apiKey = item["api_key"] as? [String: Any] else { continue }
            let masked = (apiKey["sensitive_id"] as? String) ?? "—"
            let name = (apiKey["name"] as? String) ?? "Key"
            var tokens7d = 0
            for bucket in (item["buckets"] as? [[String: Any]] ?? []) {
                guard let time = (bucket["time"] as? NSNumber)?.intValue,
                      let usage = bucket["usage"] as? [String: Any] else { continue }
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(time)))
                guard window7Dates.contains(day) else { continue }

                tokens7d += intVal(usage["RESPONSE_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_HIT_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_MISS_TOKEN"])
            }
            let prev = byKey[masked, default: (name, 0)]
            byKey[masked] = (prev.name, prev.tokens + tokens7d)
        }
        let windowTotal = max(snapshot.totalTokens, 1)
        snapshot.keyBreakdown = byKey
            .filter { $0.value.tokens > 0 }
            .sorted { $0.value.tokens > $1.value.tokens }
            .map { KeyUsage(name: $0.value.name, maskedKeyId: $0.key, tokens: $0.value.tokens, percentage: Double($0.value.tokens) / Double(windowTotal) * 100) }

        return snapshot
    }

    private func intVal(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
