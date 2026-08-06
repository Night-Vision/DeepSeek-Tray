import SwiftUI

struct KeyBreakdownListView: View {
    let keys: [KeyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown by API Key")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.dsTextSecondary)

            ForEach(keys) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.dsTextPrimary)
                        Text(key.maskedKeyId)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.dsTextTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(TokenFormatter.short(key.tokens))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.dsTextSecondary)
                        Text("\(String(format: "%.1f", key.percentage))%")
                            .font(.system(size: 9))
                            .foregroundColor(.dsAccentBlue)
                    }
                }
                .padding(8)
                .background(Color.dsPopoverSubtle)
                .cornerRadius(Metrics.radiusInner)
            }
        }
    }
}
