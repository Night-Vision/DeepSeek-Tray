import SwiftUI

struct WeeklyUsageChartView: View {
    let daily: [DailyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("7-Day Usage Trend")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                Spacer()
                Text("Avg: \(TokenFormatter.short(average()))/day")
                    .font(.system(size: 10))
                    .foregroundColor(.dsAccentBlue)
            }

            // Axis and bars are the same 90pt height and bottom-aligned, so the max
            // tick lands exactly on a full-height bar's top; weekday labels sit below.
            HStack(alignment: .bottom, spacing: 6) {
                yAxis
                bars
            }
            HStack(spacing: 4) {
                ForEach(shownDays) { day in
                    Text(dayLabel(day.date))
                        .font(.system(size: 10))
                        .foregroundColor(isToday(day.date) ? .dsAccentBlue : .dsTextTertiary)
                        .frame(width: 16)
                }
            }
            .padding(.leading, 44)
        }
    }

    private var yAxis: some View {
        let bounds = ChartAxis.niceBounds(for: shownDays.map { $0.totalTokens })
        return ZStack(alignment: .top) {
            Text(formatK(Int(bounds[0])))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.dsTextTertiary)
                .frame(maxHeight: .infinity, alignment: .top)
            Text(formatK(Int(bounds[1])))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.dsTextTertiary)
                .frame(maxHeight: .infinity, alignment: .center)
            Text(formatK(Int(bounds[2])))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.dsTextTertiary)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 38, height: 90)
    }

    private var bars: some View {
        let bounds = ChartAxis.niceBounds(for: shownDays.map { $0.totalTokens })
        let maxValue = bounds[0]
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(shownDays) { day in
                stackedBar(day: day, maxValue: maxValue)
            }
        }
    }

    /// The chart is "7-Day" — only ever render the most recent 7 entries so a
    /// longer history (e.g. 30 days) can't overflow the fixed-width popover.
    private var shownDays: [DailyUsage] {
        Array(daily.suffix(7))
    }

    private func stackedBar(day: DailyUsage, maxValue: Double) -> some View {
        let total = max(day.totalTokens, 1)
        return VStack(spacing: 0) {
            if day.breakdown.isEmpty {
                // Fallback: never render an invisible bar — draw the full total.
                Rectangle()
                    .fill(Color.dsGradientStart)
                    .frame(height: barHeight(tokens: day.totalTokens, max: maxValue, total: total))
            } else {
                ForEach(day.breakdown) { item in
                    Rectangle()
                        .fill(colorFor(item.category))
                        .frame(height: barHeight(tokens: item.tokens, max: maxValue, total: total))
                }
            }
        }
        .frame(height: barHeight(tokens: day.totalTokens, max: maxValue, total: total))
        .frame(width: 16)
        .cornerRadius(4)
    }

    private func barHeight(tokens: Int, max: Double, total: Int) -> CGFloat {
        guard max > 0, total > 0 else { return 0 }
        return CGFloat(Double(tokens) / max) * 90
    }

    private func average() -> Int {
        let days = shownDays
        guard !days.isEmpty else { return 0 }
        return days.map { $0.totalTokens }.reduce(0, +) / days.count
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

    private func colorFor(_ category: String) -> Color {
        switch category.lowercased() {
        case "deepseek-chat": return .dsAccentBlue
        case "deepseek-coder": return .dsAccentGreen
        default: return .dsGradientStart
        }
    }
}
