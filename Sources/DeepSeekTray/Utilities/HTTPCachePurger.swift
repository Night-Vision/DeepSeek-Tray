import Foundation

/// Removes the app's on-disk HTTP response cache.
///
/// The usage and billing payloads carry token totals and API-key names, and an
/// earlier build fetched them through `URLSession.shared`, whose default cache
/// wrote every response to `~/Library/Caches/<bundle-id>/Cache.db` plus a
/// `fsCachedData/` body store. `DiscoveredDashboardUsageClient` now uses a
/// non-caching session, so this exists to clear what is already on disk and to
/// keep sign-out honest.
enum HTTPCachePurger {
    /// One-shot flag: the sweep runs once per install rather than on every launch.
    private static let flagKey = "ds_http_cache_purged_v1"

    /// Clears entries left behind by earlier builds. Safe to call repeatedly.
    static func purgeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        purge()
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    static func purge() {
        URLCache.shared.removeAllCachedResponses()
        guard let dir = cacheDirectory() else { return }
        let fm = FileManager.default
        for name in ["Cache.db", "Cache.db-shm", "Cache.db-wal"] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
        try? fm.removeItem(at: dir.appendingPathComponent("fsCachedData", isDirectory: true))
        print("[HTTPCachePurger] cleared on-disk HTTP cache")
    }

    /// Mirrors where Foundation puts it: the caches directory plus the bundle
    /// identifier, falling back to the executable name for a bare `swift run`.
    private static func cacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let id = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return caches.appendingPathComponent(id, isDirectory: true)
    }
}
