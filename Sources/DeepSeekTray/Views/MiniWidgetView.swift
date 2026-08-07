import SwiftUI

struct MiniWidgetView: View {
    @EnvironmentObject var tracker: UsageTracker

    /// The platform API is daily-granularity; show the last 7 days.
    private var shownDays: [DailyUsage] {
        Array(tracker.snapshot.dailyTotals.suffix(7))
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            Text(TokenFormatter.short(todayTotal()))
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.dsTextPrimary)
            Text("Avg: \(TokenFormatter.short(average()))/day")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.dsAccentGreen)

            weeklyChart

            Button(action: { tracker.show(.dashboard) }) {
                HStack(spacing: 5) {
                    Text("Expand Dashboard")
                    Image(systemName: "arrow.right.and.left")
                        .font(.system(size: 10))
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.dsAccentBlue.opacity(0.15))
                .foregroundColor(.dsAccentBlueHover)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dsAccentBlue.opacity(0.3), lineWidth: 1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(Metrics.smallPadding)
        .background(
            LinearGradient(colors: [Color.dsPopover.opacity(0.95), Color.dsCard.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dsAccentBlue.opacity(0.35), lineWidth: 1))
        .cornerRadius(12)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.dsAccentBlue)
                Text("7-DAY TREND")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.dsTextSecondary)
                    .tracking(0.5)
            }
            Spacer()
            Circle()
                .fill(Color.dsAccentGreen)
                .frame(width: 6, height: 6)
        }
    }

    private var weeklyChart: some View {
        let days = shownDays
        let bounds = ChartAxis.niceBounds(for: days.map { $0.totalTokens })
        let maxValue = bounds[0]
        return HStack(alignment: .bottom, spacing: 6) {
            yAxis
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(days) { day in
                        Rectangle()
                            .fill(LinearGradient(colors: [.dsGradientStart, .dsGradientEnd], startPoint: .top, endPoint: .bottom))
                            .frame(width: 14, height: barHeight(tokens: day.totalTokens, max: maxValue))
                            .cornerRadius(2)
                    }
                }
                .frame(height: 42, alignment: .bottom)
                .overlay(Divider().background(Color.white.opacity(0.1)), alignment: .bottom)

                HStack {
                    ForEach(days) { day in
                        Text(dayLabel(day.date))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(isToday(day.date) ? .dsAccentBlue : .dsTextTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var yAxis: some View {
        let bounds = ChartAxis.niceBounds(for: shownDays.map { $0.totalTokens })
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach([bounds[0], bounds[1], bounds[2]], id: \.self) { value in
                Text(formatK(Int(value)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.dsTextTertiary)
                    .frame(height: 20, alignment: .center)
            }
        }
        .frame(height: 60)
    }

    private func todayTotal() -> Int {
        tracker.snapshot.dailyTotals.last?.totalTokens ?? 0
    }

    private func average() -> Int {
        let days = shownDays
        guard !days.isEmpty else { return 0 }
        return days.map { $0.totalTokens }.reduce(0, +) / days.count
    }

    private func barHeight(tokens: Int, max: Double) -> CGFloat {
        guard max > 0 else { return 2 }
        let h = CGFloat(Double(tokens) / max) * 42
        return Swift.max(h, 2)
    }

    private func formatK(_ value: Int) -> String {
        return TokenFormatter.short(value)
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}
