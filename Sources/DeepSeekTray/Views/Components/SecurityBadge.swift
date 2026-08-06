import SwiftUI

struct SecurityBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundColor(.dsAccentBlue)
            Text("Credentials stored securely in macOS Hardware Keychain.")
                .font(.system(size: 10))
                .foregroundColor(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.dsAccentBlue.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.dsAccentBlue.opacity(0.2), lineWidth: 1))
        .cornerRadius(Metrics.radiusInner)
    }
}
