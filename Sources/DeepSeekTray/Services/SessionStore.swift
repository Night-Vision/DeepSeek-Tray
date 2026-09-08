import Foundation
import WebKit

/// Mirrors the platform session into the Keychain so it survives a change of
/// bundle identity.
///
/// `WKWebsiteDataStore.default()` and `UserDefaults` are both keyed by bundle
/// identity, so the packaged .app (`com.deepseek.tray`) and the bare SPM binary
/// (`DeepSeekTray`) each get their own cookie jar and their own defaults. The
/// Keychain is the exception — `KeychainManager.service` is a fixed string — so
/// anything stored here is shared by every build of the app, and a session
/// captured by one is usable by the other.
enum SessionStore {
    static let account = "sessionCookies"
    private static let domainSuffix = "deepseek.com"

    /// Cookie values are credentials: log counts and domains, never contents.
    static func capture(from store: WKHTTPCookieStore, lastSuccessfulAuth: Date = Date()) async {
        let cookies = await store.allCookies()
            .filter { $0.domain.hasSuffix(domainSuffix) }
        guard !cookies.isEmpty,
              let blob = CookieCodec.encode(cookies: cookies, lastSuccessfulAuth: lastSuccessfulAuth)
        else {
            print("[SessionStore] capture: no \(domainSuffix) cookies to mirror")
            return
        }
        let ok = KeychainManager.save(account: account, value: blob)
        print("[SessionStore] mirrored \(cookies.count) cookie(s) to Keychain: \(ok ? "ok" : "FAILED")")
    }

    /// Puts the mirrored session back before the web view loads, so a silent
    /// renewal on a fresh identity starts already carrying the session.
    static func restore(into store: WKHTTPCookieStore) async {
        guard let blob = KeychainManager.get(account: account) else { return }
        let payload = CookieCodec.decode(blob)
        guard !payload.cookies.isEmpty else { return }
        await store.restoreAll(payload.cookies)
        print("[SessionStore] restored \(payload.cookies.count) cookie(s) from Keychain")
    }

    /// Drives proactive renewal: the token is opaque, so this timestamp is the
    /// only expiry signal available.
    static var lastSuccessfulAuth: Date? {
        guard let blob = KeychainManager.get(account: account) else { return nil }
        return CookieCodec.decode(blob).lastSuccessfulAuth
    }

    static func clear() {
        KeychainManager.delete(account: account)
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { c in
            getAllCookies { c.resume(returning: $0) }
        }
    }
    /// Sequential `setCookie`, not the batch `setCookies(_:)`: the batch form is
    /// macOS 26+ and this package deploys to macOS 14.
    func restoreAll(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await withCheckedContinuation { c in
                setCookie(cookie) { c.resume() }
            }
        }
    }
}
