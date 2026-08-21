import Foundation

/// Exponential backoff between retries of a failed usage fetch.
/// 30s → 60s → 120s → 240s → 300s, then flat. The poll timer covers the long
/// tail, so there is no reason to back off past a few minutes.
enum Backoff {
    static let initial: Double = 30
    static let cap: Double = 300

    static func next(_ current: Double) -> Double { min(current * 2, cap) }
}
