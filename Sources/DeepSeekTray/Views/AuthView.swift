import SwiftUI

struct AuthView: View {
    @EnvironmentObject var tracker: UsageTracker
    @ObservedObject private var auth = AuthManager.shared
    @State private var portalEmail = ""
    @State private var portalPassword = ""
    @State private var isAuthenticating = false
    @State private var message: String?

    private var isLinked: Bool {
        auth.state.googleSessionLinked
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            VStack(spacing: 14) {
                portalSection

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

            PopoverFooter(left: "API Endpoint: platform.deepseek.com", right: "v\(appVersion)")
        }
        .padding(Metrics.padding)
        .background(Color.dsPopover)
    }

    /// Version from the packaged Info.plist (release zip), falling back for `swift run`.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
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

    private var portalSection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Portal Email Address")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                TextField("name@example.com", text: $portalEmail)
                    .darkTextField()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Portal Password")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                SecureField("••••••••", text: $portalPassword)
                    .darkTextField()
            }

            Button(action: startDirectPortalSSO) {
                HStack(spacing: 8) {
                    if isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                    }
                    Text(isAuthenticating ? "Authenticating..." : "Sign in to Portal")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(Color.dsAccentBlue)
                .foregroundColor(.white)
                .cornerRadius(Metrics.radiusInner)
            }
            .disabled(portalEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || portalPassword.isEmpty || isAuthenticating)
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
        }
    }

    private func startWebSSO() {
        AuthManager.shared.beginWebSSO { ok in
            if ok {
                tracker.currentView = .dashboard
                message = "Signed in to DeepSeek."
                Task { await tracker.refresh() }
            } else {
                message = "Sign-in was cancelled."
            }
        }
    }

    private func startDirectPortalSSO() {
        let cleanEmail = portalEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = portalPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !cleanPassword.isEmpty else {
            message = "Please enter both email and password."
            return
        }

        isAuthenticating = true
        message = nil
        AuthManager.shared.beginDirectSSO(email: cleanEmail, password: cleanPassword) { ok in
            isAuthenticating = false
            if ok {
                tracker.currentView = .dashboard
                message = "Signed in to DeepSeek."
                Task { await tracker.refresh() }
            } else {
                message = "Sign-in failed or was cancelled."
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
