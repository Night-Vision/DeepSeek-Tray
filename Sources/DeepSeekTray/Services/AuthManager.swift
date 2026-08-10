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

    func signOut() {
        KeychainManager.delete(account: "googleToken")
        UserDefaults.standard.removeObject(forKey: "ds_discovered_usage_endpoint")
        state.googleSessionLinked = false
    }
}
