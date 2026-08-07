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
        if let data = try? JSONEncoder().encode(endpoint) {
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
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.resourceUnavailable)
        }
        return try parseUsage(data)
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

        // Totals + raw buckets across every series.
        var totalRequests = 0
        var totalTokens = 0
        var rawBuckets: [(time: Int, tokens: Int, requests: Int)] = []
        for item in series {
            for bucket in (item["buckets"] as? [[String: Any]] ?? []) {
                guard let time = (bucket["time"] as? NSNumber)?.intValue,
                      let usage = bucket["usage"] as? [String: Any] else { continue }
                let requests = intVal(usage["REQUEST"])
                let tokens = intVal(usage["RESPONSE_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_HIT_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_MISS_TOKEN"])
                totalRequests += requests
                totalTokens += tokens
                rawBuckets.append((time, tokens, requests))
            }
        }
        snapshot.totalRequests = totalRequests
        snapshot.totalTokens = totalTokens
        // totalCost stays 0: the payload carries no dollar figures.

        // Daily totals — buckets are day-granularity (epoch steps of 86400).
        let calendar = Calendar(identifier: .gregorian)
        var byDay: [Date: (tokens: Int, requests: Int)] = [:]
        for bucket in rawBuckets {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(bucket.time)))
            let prev = byDay[day, default: (0, 0)]
            byDay[day] = (prev.tokens + bucket.tokens, prev.requests + bucket.requests)
        }
        snapshot.dailyTotals = byDay
            .sorted { $0.key < $1.key }
            .map { DailyUsage(date: $0.key, totalTokens: $0.value.tokens, totalCost: 0, totalRequests: $0.value.requests, breakdown: []) }

        // Per-key breakdown, aggregated over all models.
        var byKey: [String: (name: String, tokens: Int)] = [:]
        for item in series {
            guard let apiKey = item["api_key"] as? [String: Any] else { continue }
            let masked = (apiKey["sensitive_id"] as? String) ?? "—"
            let name = (apiKey["name"] as? String) ?? "Key"
            var tokens = 0
            for bucket in (item["buckets"] as? [[String: Any]] ?? []) {
                guard let usage = bucket["usage"] as? [String: Any] else { continue }
                tokens += intVal(usage["RESPONSE_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_HIT_TOKEN"])
                    + intVal(usage["PROMPT_CACHE_MISS_TOKEN"])
            }
            let prev = byKey[masked, default: (name, 0)]
            byKey[masked] = (prev.name, prev.tokens + tokens)
        }
        let total = max(byKey.values.reduce(0) { $0 + $1.tokens }, 1)
        snapshot.keyBreakdown = byKey
            .sorted { $0.value.tokens > $1.value.tokens }
            .map { KeyUsage(name: $0.value.name, maskedKeyId: $0.key, tokens: $0.value.tokens, percentage: Double($0.value.tokens) / Double(total) * 100) }

        return snapshot
    }

    private func intVal(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
