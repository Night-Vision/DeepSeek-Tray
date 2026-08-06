import Foundation

enum URLErrorPresenter {
    private static let mapping: [Int: String] = [
        -1001: "Network timeout",
        -1002: "Invalid URL",
        -1003: "Can't find server (DNS)",
        -1004: "Can't connect to host",
        -1005: "Network connection lost",
        -1006: "DNS lookup failed",
        -1009: "No internet",
        -1013: "Auth required (401)",
        -1200: "Secure connection failed",
        -1202: "Server cert not trusted",
        -1203: "Server cert not honored"
    ]

    static func shortSummary(for description: String) -> String {
        guard let code = extractURLErrorCode(from: description) else {
            return description
        }
        return mapping[code] ?? "Network error (NSURLError \(code))"
    }

    private static func extractURLErrorCode(from s: String) -> Int? {
        guard s.contains("NSURLError") else { return nil }
        let pattern = #"-\d{3,4}\)?$"#
        guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = s[r].trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        return Int(raw)
    }
}
