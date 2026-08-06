import SwiftUI

struct MiniWidgetView: View {
    @EnvironmentObject var tracker: UsageTracker

    var body: some View {
        VStack(spacing: 8) {
            header
            Text(TokenFormatter.short(todayTotal()))
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.dsTextPrimary)
            Text("Peak: \(TokenFormatter.short(peak())) @ \(peakHour())")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.dsAccentGreen)

            hourlyChart

            Button(action: { tracker.show(.dashboard) }) {
                HStack(spacing: 5) {
                    Text("Expand Dashboard")
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
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
                Text("TODAY HOURLY")
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

    private var hourlyChart: some View {
        let hours = tracker.snapshot.hourlyTotalsToday
        let bounds = ChartAxis.niceBounds(for: hours.map { $0.tokens })
        let maxValue = bounds[0]
        return HStack(alignment: .bottom, spacing: 6) {
            yAxis
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(hours) { hour in
                        Rectangle()
                            .fill(hour.hour == currentHour()
                                  ? LinearGradient(colors: [Color(hex: "64D2FF"), .dsAccentBlue], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [.dsGradientStart, .dsGradientEnd], startPoint: .top, endPoint: .bottom))
                            .frame(height: barHeight(tokens: hour.tokens, max: maxValue))
                            .cornerRadius(2)
                    }
                }
                .frame(height: 42)
                .overlay(Divider().background(Color.white.opacity(0.1)), alignment: .bottom)

                HStack {
                    ForEach(timeMarks, id: \.self) { mark in
                        Text(mark)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.dsTextTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var yAxis: some View {
        let bounds = ChartAxis.niceBounds(for: tracker.snapshot.hourlyTotalsToday.map { $0.tokens })
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

    private var timeMarks: [String] {
        let hours = tracker.snapshot.hourlyTotalsToday
        guard let first = hours.first?.hour, let last = hours.last?.hour else { return [] }
        let span = last - first
        let step = max(span / 3, 1)
        return (0...3).compactMap { idx -> String? in
            let hour = first + idx * step
            guard hour <= last else { return nil }
            return formatHour(hour)
        }
    }

    private func todayTotal() -> Int {
        let hourly = tracker.snapshot.hourlyTotalsToday.map { $0.tokens }.reduce(0, +)
        return hourly > 0 ? hourly : tracker.snapshot.totalTokens
    }

    private func peak() -> Int {
        tracker.snapshot.hourlyTotalsToday.map { $0.tokens }.max() ?? 0
    }

    private func peakHour() -> String {
        guard let hour = tracker.snapshot.hourlyTotalsToday.max(by: { $0.tokens < $1.tokens })?.hour else { return "-" }
        return formatHour(hour)
    }

    private func currentHour() -> Int {
        Calendar.current.component(.hour, from: Date())
    }

    private func barHeight(tokens: Int, max: Double) -> CGFloat {
        guard max > 0 else { return 2 }
        let h = CGFloat(Double(tokens) / max) * 42
        return Swift.max(h, 2)
    }

    private func formatK(_ value: Int) -> String {
        return TokenFormatter.short(value)
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        let suffix = h < 12 ? "AM" : "PM"
        let display = h % 12 == 0 ? 12 : h % 12
        return "\(display) \(suffix)"
    }
}


