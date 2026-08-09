import SwiftUI

struct WeeklyUsageChartView: View {
    let daily: [DailyUsage]
    var days: Int = 7

    @State private var hoveredIndex: Int? = nil

    private var barWidth: CGFloat { days > 7 ? 6 : 16 }
    private var barSpacing: CGFloat { days > 7 ? 2 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(days)-Day Usage Trend")
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
            xAxisLabels
        }
        .onChange(of: days) { _, _ in
            hoveredIndex = nil
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
        return HStack(alignment: .bottom, spacing: days > 7 ? barSpacing : 0) {
            ForEach(Array(shownDays.enumerated()), id: \.offset) { index, day in
                ZStack(alignment: .bottom) {
                    stackedBar(day: day, maxValue: maxValue)

                    if days > 7 && hoveredIndex == index {
                        Path { path in
                            path.move(to: CGPoint(x: barWidth / 2, y: 0))
                            path.addLine(to: CGPoint(x: barWidth / 2, y: 90))
                        }
                        .stroke(Color.dsTextTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(width: barWidth, height: 90, alignment: .bottom)
                .contentShape(Rectangle().inset(by: -3))
                .onHover { isHovered in
                    if days > 7 {
                        hoveredIndex = isHovered ? index : nil
                    }
                }

                if days <= 7 && index < shownDays.count - 1 {
                    Spacer(minLength: 4)
                }
            }
        }
    }

    private var xAxisLabels: some View {
        HStack(spacing: days > 7 ? barSpacing : 0) {
            ForEach(Array(shownDays.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    if days <= 7 {
                        Rectangle()
                            .fill(Color.dsTextTertiary.opacity(0.4))
                            .frame(width: 1, height: 4)

                        Text(dayLabel(day.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isToday(day.date) ? .dsAccentBlue : .dsTextTertiary)
                    } else if isStaticDate(index: index) {
                        Rectangle()
                            .fill(hoveredIndex == index ? Color.dsAccentBlue : Color.dsTextTertiary.opacity(0.4))
                            .frame(width: 1, height: 4)

                        Text(shortDateLabel(day.date))
                            .font(.system(size: 10, weight: hoveredIndex == index ? .bold : .medium, design: .monospaced))
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .foregroundColor(hoveredIndex == index ? .dsAccentBlue : (isToday(day.date) ? .dsAccentBlue : .dsTextTertiary))
                    } else if hoveredIndex == index {
                        Rectangle()
                            .fill(Color.dsAccentBlue)
                            .frame(width: 1, height: 4)

                        Text(shortDateLabel(day.date))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .foregroundColor(.dsAccentBlue)
                    } else {
                        Color.clear.frame(height: 4)
                        Spacer()
                    }
                }
                .frame(width: barWidth, height: 42, alignment: .top)

                if days <= 7 && index < shownDays.count - 1 {
                    Spacer(minLength: 4)
                }
            }
        }
        .padding(.leading, 44)
    }

    private func isStaticDate(index: Int) -> Bool {
        days <= 7 || index == 0 || index == shownDays.count - 1 || index % 7 == 0
    }

    private var shownDays: [DailyUsage] {
        Array(daily.suffix(days))
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
        .frame(width: barWidth)
        .cornerRadius(days > 7 ? 2 : 4)
    }

    private func barHeight(tokens: Int, max: Double, total: Int) -> CGFloat {
        guard max > 0, total > 0 else { return 0 }
        return CGFloat(Double(tokens) / max) * 90
    }

    private func average() -> Int {
        let daysList = shownDays
        guard !daysList.isEmpty else { return 0 }
        return daysList.map { $0.totalTokens }.reduce(0, +) / daysList.count
    }

    private func formatK(_ value: Int) -> String {
        return TokenFormatter.short(value)
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
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
