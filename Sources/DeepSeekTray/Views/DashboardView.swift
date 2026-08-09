import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var tracker: UsageTracker
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var copiedToastVisible = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    statCards
                    WeeklyUsageChartView(daily: tracker.snapshot.dailyTotals, days: prefs.extendedViewStyle.days)
                    KeyBreakdownListView(keys: tracker.snapshot.keyBreakdown)
                }
                .padding(.top, 14)
            }
            footer
        }
        .padding(Metrics.padding)
        .background(Color.dsPopover)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.dsAccentBlue)
                Text("DeepSeek Monitor")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dsTextPrimary)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusBadge(text: "Active", warning: false)
            }
        }
        .padding(.bottom, 14)
        .overlay(Divider().background(Color.dsBorder), alignment: .bottom)
    }

    private var statCards: some View {
        let snapshot = tracker.snapshot
        let days = prefs.extendedViewStyle.days
        return VStack(spacing: 16) {
            StatCard(title: "COST", value: "\(currencySymbol(snapshot.usageCurrency))\(String(format: "%.2f", snapshot.totalCost))", sub: "\(snapshot.usageCurrency) (this month)")
            StatCard(title: "API REQUESTS", value: Formatter.comma(snapshot.totalRequests), sub: "requests (\(days)d)")
            StatCard(title: "TOKENS", value: Formatter.comma(snapshot.totalTokens), sub: "tokens (\(days)d)")
        }
    }

    private func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default: return ""
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.dsBorder)
            HStack {
                Text("Updated \(timeAgo(tracker.snapshot.lastUpdated))")
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextTertiary)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { tracker.show(.mini) }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(IconButtonStyle())

                    Button(action: { Task { await tracker.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(IconButtonStyle())

                    Button(action: { tracker.show(.preferences) }) {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(IconButtonStyle())
                }
            }
            if let err = tracker.lastError {
                Button(action: copyError) {
                    Text(URLErrorPresenter.shortSummary(for: err))
                        .font(.system(size: 10))
                        .foregroundColor(.dsAccentAmber)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            if copiedToastVisible {
                                Text("Copied")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.dsTextTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.dsPopoverSubtle)
                                    .cornerRadius(4)
                                    .transition(.opacity)
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(.top, 10)
    }

    private func copyError() {
        guard let err = tracker.lastError else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(err, forType: .string)
        withAnimation { copiedToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copiedToastVisible = false }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff)/60) mins ago" }
        return "\(Int(diff)/3600) hrs ago"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let sub: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextSecondary)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.dsTextTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.dsTextPrimary)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(.dsAccentGreen)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsPopoverSubtle)
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .cornerRadius(Metrics.radiusInner)
    }
}

enum Formatter {
    static func comma(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.dsTextSecondary)
            .frame(width: 22, height: 22)
            .background(configuration.isPressed ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(4)
    }
}
