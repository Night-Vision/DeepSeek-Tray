import Foundation
import Combine
import AppKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var state = AuthState()

    private init() {
        state.apiKeyLinked = KeychainManager.get(account: "apiKey") != nil
        state.googleSessionLinked = KeychainManager.get(account: "sessionCookie") != nil
    }

    func signInWithAPIKey(_ key: String, label: String) async -> Bool {
        guard !key.isEmpty,
              (try? await OfficialBalanceClient(apiKey: key).fetchBalance()) != nil else {
            return false
        }
        guard KeychainManager.save(account: "apiKey", value: key) else { return false }
        state.apiKeyLinked = true
        return true
    }

    func saveSessionCookie(_ cookie: String) -> Bool {
        guard !cookie.isEmpty else { return false }
        let ok = KeychainManager.save(account: "sessionCookie", value: cookie)
        if ok { state.googleSessionLinked = true }
        return ok
    }

    func openDeepSeekLoginInBrowser() {
        let url = URL(string: "https://platform.deepseek.com/sign_in")!
        NSWorkspace.shared.open(url)
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

    func signOut(method: String) {
        switch method {
        case "apiKey":
            KeychainManager.delete(account: "apiKey")
            state.apiKeyLinked = false
        case "sessionCookie":
            KeychainManager.delete(account: "sessionCookie")
            state.googleSessionLinked = false
        default:
            KeychainManager.delete(account: "apiKey")
            KeychainManager.delete(account: "sessionCookie")
            state = AuthState()
        }
    }
}
