import SwiftUI

struct StatusBadge: View {
    let text: String
    var warning: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.vertical, 2)
        .padding(.horizontal, 7)
        .background(warning ? Color.dsAccentAmber.opacity(0.15) : Color.dsAccentGreen.opacity(0.15))
        .foregroundColor(warning ? Color.dsAccentAmber : Color.dsAccentGreen)
        .cornerRadius(10)
    }
}
