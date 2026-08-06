import Foundation

// Replays the usage API call captured by WebSSOSheet's JS interceptor.
// Schema-agnostic on purpose: the real dashboard shape is only known after
// discovery, so extraction walks keys instead of assuming a fixed DTO.
struct DiscoveredDashboardUsageClient {
    struct DiscoveredEndpoint: Codable {
        let url: String
        let method: String
        let headers: [String: String]
        let discoveredAt: Date
    }

    static let storageKey = "ds_discovered_usage_endpoint"

    let endpoint: DiscoveredEndpoint
    let cookie: String

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
        guard let url = URL(string: endpoint.url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.resourceUnavailable)
        }
        return try parseUsage(data)
    }

    // ponytail: heuristic key walker. The dashboard's exact schema is unknown
    // until discovery captures it; this extracts whatever matches. Tighten the
    // parser to the captured sample once one exists.
    private func parseUsage(_ data: Data) throws -> UsageSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        var snapshot = UsageSnapshot.empty
        extractTotals(json, into: &snapshot)
        snapshot.dailyTotals = extractDaily(json)
        snapshot.hourlyTotalsToday = extractHourly(json)
        snapshot.keyBreakdown = extractKeys(json)
        return snapshot
    }

    private func extractTotals(_ value: Any, into snapshot: inout UsageSnapshot) {
        guard let dict = value as? [String: Any] else { return }
        for (key, val) in dict {
            let k = key.lowercased()
            if let num = val as? NSNumber {
                switch k {
                case "total_cost", "totalcost": snapshot.totalCost = num.doubleValue
                case "total_tokens", "totaltokens": snapshot.totalTokens = num.intValue
                case "total_requests", "totalrequests": snapshot.totalRequests = num.intValue
                default: break
                }
            } else if let sub = val as? [String: Any] {
                extractTotals(sub, into: &snapshot)
            } else if let arr = val as? [Any] {
                for item in arr { extractTotals(item, into: &snapshot) }
            }
        }
    }

    private func extractDaily(_ value: Any) -> [DailyUsage] {
        guard let dict = value as? [String: Any] else { return [] }
        for (key, val) in dict {
            if key.lowercased().contains("daily") || key.lowercased().contains("chart") {
                if let arr = val as? [[String: Any]], let first = arr.first,
                   dateKey(first) != nil {
                    return arr.compactMap { item -> DailyUsage? in
                        guard let date = parseDate(dateKey(item)), let tokens = numberKey(item, ["tokens", "total_tokens", "token_usage"]) else { return nil }
                        return DailyUsage(
                            date: date,
                            totalTokens: tokens.intValue,
                            totalCost: numberKey(item, ["cost", "total_cost"])?.doubleValue ?? 0,
                            totalRequests: numberKey(item, ["requests", "total_requests"])?.intValue ?? 0,
                            breakdown: []
                        )
                    }
                }
            }
        }
        return []
    }

    private func extractHourly(_ value: Any) -> [HourlyUsage] {
        guard let dict = value as? [String: Any] else { return [] }
        for (key, val) in dict {
            if key.lowercased().contains("hourly") || key.lowercased().contains("today") {
                if let arr = val as? [[String: Any]] {
                    return arr.compactMap { item -> HourlyUsage? in
                        guard let hour = numberKey(item, ["hour", "timestamp", "time"])?.intValue,
                              let tokens = numberKey(item, ["tokens", "total_tokens"]) else { return nil }
                        return HourlyUsage(hour: hour, tokens: tokens.intValue)
                    }
                }
            }
        }
        return []
    }

    private func extractKeys(_ value: Any) -> [KeyUsage] {
        guard let dict = value as? [String: Any] else { return [] }
        for (key, val) in dict {
            if key.lowercased().contains("key") {
                if let arr = val as? [[String: Any]], arr.contains(where: { numberKey($0, ["tokens", "total_tokens"]) != nil }) {
                    return arr.compactMap { item -> KeyUsage? in
                        guard let tokens = numberKey(item, ["tokens", "total_tokens"]) else { return nil }
                        return KeyUsage(
                            name: stringKey(item, ["name", "key_name", "label"]) ?? "Key",
                            maskedKeyId: stringKey(item, ["masked_key", "key_id", "api_key"]) ?? "—",
                            tokens: tokens.intValue,
                            percentage: numberKey(item, ["percentage", "percent"])?.doubleValue ?? 0
                        )
                    }
                }
            }
        }
        return []
    }

    // MARK: - Key helpers

    private func dateKey(_ dict: [String: Any]) -> String? {
        for key in ["date", "day", "time", "timestamp"] {
            if let v = dict[key] as? String { return v }
            if let v = dict[key] as? NSNumber { return v.stringValue }
        }
        return nil
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(string.prefix(10)))
    }

    private func numberKey(_ dict: [String: Any], _ keys: [String]) -> NSNumber? {
        for key in keys {
            if let v = dict[key] as? NSNumber { return v }
            if let s = dict[key] as? String, let v = Double(s) { return NSNumber(value: v) }
        }
        return nil
    }

    private func stringKey(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let v = dict[key] as? String { return v }
        }
        return nil
    }
}
