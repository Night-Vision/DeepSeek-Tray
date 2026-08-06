import SwiftUI

struct SessionStatsView: View {
    @ObservedObject var sessionTracker: SessionUsageTracker
    let model: ModelProfile

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Live Session")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.dsTextSecondary)
                Spacer()
                Text("\(sessionTracker.currentSession.turnCount) turns")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary)
            }

            HStack(spacing: 8) {
                StatCard(title: "SESSION TOKENS", value: TokenFormatter.short(sessionTracker.currentSession.totalTokens), sub: "tokens")
                StatCard(title: "TURN COST", value: String(format: "%.4f", sessionTracker.currentSession.totalCost), sub: model.pricing.currency)
            }

            HStack(spacing: 8) {
                StatCard(title: "PROMPT", value: TokenFormatter.short(sessionTracker.currentSession.totalPromptTokens), sub: "tokens")
                StatCard(title: "COMPLETION", value: TokenFormatter.short(sessionTracker.currentSession.totalCompletionTokens), sub: "tokens")
            }

            contextBar
        }
    }

    private var contextBar: some View {
        let ratio = sessionTracker.contextRatio()
        let percentage = Int(ratio * 100)
        let color: Color = ratio >= 0.85 ? .dsAccentRed : ratio >= 0.75 ? .dsAccentAmber : .dsAccentGreen

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context Window")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextSecondary)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.dsBorder)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(ratio, 1.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(Color.dsPopoverSubtle)
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .cornerRadius(Metrics.radiusInner)
    }
}
