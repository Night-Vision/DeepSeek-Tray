import Foundation

/// Result of one silent session-renewal attempt.
enum RenewalOutcome {
    case renewed
    /// Authoritative: the platform redirected to /sign_in, so the cookie session
    /// really is gone and only an interactive sign-in can recover it.
    case sessionDead
    /// Could not determine — timeout, no network, bad URL. Says nothing at all
    /// about whether the session is still good.
    case inconclusive
}

/// When to attempt a silent session renewal and how often (webview churn guard).
enum RenewalPolicy {
    /// Minimum gap between *proactive* (endpoint-lost) renewal attempts.
    static let cooldown: TimeInterval = 300
    /// Consecutive *authoritative* dead-session verdicts before falling back to
    /// an interactive sign-in.
    static let maxConsecutiveFailures = 2

    static func shouldAttempt(consecutiveFailures: Int) -> Bool {
        consecutiveFailures < maxConsecutiveFailures
    }

    static func cooldownElapsed(since lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= cooldown
    }

    /// Only an authoritative verdict spends the budget. A timeout or an offline
    /// attempt must leave it untouched: otherwise two bad minutes disable renewal
    /// for good, since the counter only resets on a success that can no longer
    /// happen once renewal is blocked.
    static func nextFailureCount(_ current: Int, after outcome: RenewalOutcome) -> Int {
        switch outcome {
        case .renewed:      return 0
        case .sessionDead:  return current + 1
        case .inconclusive: return current
        }
    }
}
