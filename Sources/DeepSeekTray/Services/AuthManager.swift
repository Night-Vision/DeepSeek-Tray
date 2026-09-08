import Foundation
import Combine
import AppKit
import WebKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var state = AuthState()

    private init() {
        // Single-pass legacy purge: clear obsolete Keychain items from older versions
        KeychainManager.delete(account: "apiKey")
        KeychainManager.delete(account: "sessionCookie")

        state.googleSessionLinked = KeychainManager.get(account: "googleToken") != nil
    }

    func beginWebSSO(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://platform.deepseek.com/sign_in") else {
            completion(false)
            return
        }
        let sheet = WebSSOSheet(siteURL: url)
        sheet.start { [weak self] ok in
            if ok {
                self?.state.googleSessionLinked = true
            }
            completion(ok)
        }
    }

    func beginDirectSSO(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://platform.deepseek.com/sign_in") else {
            completion(false)
            return
        }
        let sheet = WebSSOSheet(siteURL: url, initialEmail: email, initialPassword: password, isHeadless: true)
        sheet.start { [weak self] ok in
            if ok {
                self?.state.googleSessionLinked = true
            }
            completion(ok)
        }
    }

    /// Opens an invisible WebKit session on the last dashboard page and waits for
    /// the SPA to re-issue a usage request, re-capturing a fresh token + endpoint.
    /// Only succeeds while DeepSeek's own session (cookies/localStorage in the
    /// persistent WKWebsiteDataStore) is still alive; otherwise returns false.
    func renewSession() async -> RenewalOutcome {
        let page = UserDefaults.standard.string(forKey: "ds_dashboard_page_url")
        guard let url = URL(string: page ?? "https://platform.deepseek.com/") else { return .inconclusive }
        let sheet = WebSSOSheet(siteURL: url, silent: true)
        return await withCheckedContinuation { continuation in
            sheet.start { [weak self] ok in
                if ok { self?.state.googleSessionLinked = true }
                // A bare `false` conflates "cookie is gone" with "we timed out".
                // Only the /sign_in redirect is authoritative.
                let outcome: RenewalOutcome = ok ? .renewed
                    : (sheet.didDetectDeadSession ? .sessionDead : .inconclusive)
                continuation.resume(returning: outcome)
            }
        }
    }

    func signOut() {
        let deleted = KeychainManager.delete(account: "googleToken")
        // All three discovered keys, not just the usage endpoint: a surviving
        // balance endpoint gets fetched without a token, 401s, and drives this
        // same sign-out path again.
        for key in ["ds_discovered_usage_endpoint", "ds_discovered_balance_endpoint", "ds_dashboard_page_url"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // The persistent cookie store is what keeps the login alive everywhere
        // else, so this is the one place it must actually be destroyed —
        // otherwise "Sign Out & Clear Session Data" silently resumes the account.
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                         modifiedSince: Date(timeIntervalSince1970: 0)) {
            print("[AuthManager] signOut: WebKit session data cleared")
        }
        state.googleSessionLinked = false
        if !deleted {
            print("[AuthManager] signOut: Keychain delete of googleToken FAILED — token survives (half-signed-out state)")
        }
    }
}
