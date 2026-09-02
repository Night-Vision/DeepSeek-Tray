import Foundation
import Combine
import AppKit

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
    func renewSession() async -> Bool {
        let page = UserDefaults.standard.string(forKey: "ds_dashboard_page_url")
        guard let url = URL(string: page ?? "https://platform.deepseek.com/") else { return false }
        let sheet = WebSSOSheet(siteURL: url, silent: true)
        return await withCheckedContinuation { continuation in
            sheet.start { [weak self] ok in
                if ok { self?.state.googleSessionLinked = true }
                continuation.resume(returning: ok)
            }
        }
    }

    func signOut() {
        let deleted = KeychainManager.delete(account: "googleToken")
        UserDefaults.standard.removeObject(forKey: "ds_discovered_usage_endpoint")
        state.googleSessionLinked = false
        if !deleted {
            print("[AuthManager] signOut: Keychain delete of googleToken FAILED — token survives (half-signed-out state)")
        }
    }
}
