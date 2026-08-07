import SwiftUI

struct AuthView: View {
    @EnvironmentObject var tracker: UsageTracker
    @ObservedObject private var auth = AuthManager.shared
    @State private var apiKey = ""
    @State private var label = ""
    @State private var cookie = ""
    @State private var message: String?

    private var isLinked: Bool {
        auth.state.apiKeyLinked || auth.state.googleSessionLinked
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            VStack(spacing: 14) {
                apiKeySection

                Divider()
                    .background(Color.dsBorder)

                googleSection
            }

            SecurityBadge()

            if let message = message ?? tracker.lastError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.dsAccentAmber)
                    .multilineTextAlignment(.center)
            }

            PopoverFooter(left: "API Endpoint: api.deepseek.com", right: "v1.0.0")
        }
        .padding(Metrics.padding)
        .background(Color.dsPopover)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.dsAccentBlue)
                Text("Connect DeepSeek")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dsTextPrimary)
            }
            Spacer()
            StatusBadge(text: isLinked ? "Linked" : "Unlinked", warning: !isLinked)
        }
        .padding(.bottom, 14)
        .overlay(Divider().background(Color.dsBorder), alignment: .bottom)
    }

    private var apiKeySection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DeepSeek API Key")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                SecureField("sk-...", text: $apiKey)
                    .darkTextField()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Key Label / Friendly Name")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                TextField("e.g. My Mac", text: $label)
                    .darkTextField()
            }

            Button(action: saveAPIKey) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                    Text("Save Key to Keychain")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(Color.dsAccentBlue)
                .foregroundColor(.white)
                .cornerRadius(Metrics.radiusInner)
            }
            .buttonStyle(.plain)
        }
    }

    private var googleSection: some View {
        VStack(spacing: 10) {
            Button(action: startWebSSO) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Sign in with Google")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(Color.white)
                .foregroundColor(Color(hex: "1F1F1F"))
                .cornerRadius(Metrics.radiusInner)
            }
            .buttonStyle(.plain)

            Text("Or paste the Cookie header (DevTools → Network → any request) below:")
                .font(.system(size: 10))
                .foregroundColor(.dsTextTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Button(action: openBrowser) {
                Text("Open platform.deepseek.com in browser →")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text("Paste Cookie header from DevTools (reliable)")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                TextField("session=...; token=...", text: $cookie)
                    .darkTextField()
            }

            Button(action: saveCookie) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                    Text("Store Session Cookie")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(Color.dsPopoverSubtle)
                .foregroundColor(.dsTextPrimary)
                .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.dsBorder, lineWidth: 1))
                .cornerRadius(Metrics.radiusInner)
            }
            .buttonStyle(.plain)
        }
    }

    private func saveAPIKey() {
        Task {
            let ok = await AuthManager.shared.signInWithAPIKey(apiKey, label: label.isEmpty ? "Unnamed" : label)
            message = ok ? "API key saved." : "Invalid API key — DeepSeek rejected it."
            if ok { tracker.currentView = .dashboard }
        }
    }

    private func saveCookie() {
        let ok = AuthManager.shared.saveSessionCookie(cookie)
        message = ok ? "Session cookie saved." : "Failed to save cookie."
        if ok { tracker.currentView = .dashboard }
    }

    private func openBrowser() {
        AuthManager.shared.openDeepSeekLoginInBrowser()
    }

    private func startWebSSO() {
        AuthManager.shared.beginWebSSO { ok in
            if ok {
                tracker.currentView = .dashboard
                message = "Signed in to DeepSeek."
                Task { await tracker.refresh() }
            } else {
                message = "Sign-in was cancelled. Paste your Cookie header below instead."
            }
        }
    }
}

extension View {
    func darkTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(8)
            .background(Color.dsPopoverSubtle)
            .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.dsBorder, lineWidth: 1))
            .cornerRadius(Metrics.radiusInner)
            .foregroundColor(.dsTextPrimary)
    }
}
