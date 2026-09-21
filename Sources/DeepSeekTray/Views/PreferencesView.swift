import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject var tracker: UsageTracker
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                ToggleRow(title: "Compact Mini Mode", desc: "Open the mini widget by default", isOn: $prefs.compactMiniDefault)
                RefreshIntervalRow()
                TrayStyleRow()
                ExtendedViewStyleRow()
                BudgetRow()
                ExportRow()
                ToggleRow(title: "Start at Login", desc: "Launch background daemon on boot", isOn: $prefs.launchAtLogin)
            }

            Button(action: purge) {
                Text("Sign Out & Clear Session Data")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(9)
                    .background(Color.dsAccentRed.opacity(0.15))
                    .foregroundColor(.dsAccentRed)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.radiusInner).stroke(Color.dsAccentRed.opacity(0.3), lineWidth: 1))
                    .cornerRadius(Metrics.radiusInner)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            PopoverFooter(left: "DeepSeek Tray Spec", right: "macOS Sequoia Ready")
        }
        .padding(Metrics.padding)
        .background(Color.dsPopover)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.dsAccentBlue)
                Text("Preferences")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dsTextPrimary)
            }
            Spacer()
            Button(action: { tracker.show(prefs.compactMiniDefault ? .mini : .dashboard) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.bottom, 10)
    }

    private func purge() {
        AuthManager.shared.signOut()
        tracker.currentView = .auth
    }
}

struct ToggleRow: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .tint(.dsAccentBlue)
        }
        .padding(.vertical, 8)
    }
}

struct RefreshIntervalRow: View {
    @ObservedObject var prefs = PreferencesStore.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Background Refresh")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text("Polling interval for token checks")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            Picker("", selection: $prefs.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text("Every \(interval.rawValue) mins").tag(interval)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.vertical, 8)
    }
}

struct TrayStyleRow: View {
    @ObservedObject var prefs = PreferencesStore.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tray Display Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text("Information in upper macOS tray")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            Picker("", selection: $prefs.trayDisplayStyle) {
                ForEach(TrayDisplayStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.vertical, 8)
    }
}

struct ExtendedViewStyleRow: View {
    @ObservedObject var prefs = PreferencesStore.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extended View Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text("Timeframe for dashboard usage totals & charts")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            Picker("", selection: $prefs.extendedViewStyle) {
                ForEach(ExtendedViewStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.vertical, 8)
    }
}

struct BudgetRow: View {
    @ObservedObject var prefs = PreferencesStore.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly Budget")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text("Alerts at 80% / 100% of budget; 0 = off")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            TextField("", value: $prefs.monthlyBudget, format: .number)
                .darkTextField()
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

struct ExportRow: View {
    @EnvironmentObject var tracker: UsageTracker

    @State private var preset: ExportPreset = .last30
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Usage Data")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.dsTextPrimary)
                    Text(rangeHint)
                        .font(.system(size: 9))
                        .foregroundColor(.dsTextTertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("CSV") { export(ext: "csv") }
                        .buttonStyle(SmallPillButtonStyle())
                    Button("JSON") { export(ext: "json") }
                        .buttonStyle(SmallPillButtonStyle())
                }
                .disabled(isExporting)
            }

            HStack(spacing: 6) {
                Text("Export range")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $preset) {
                    ForEach(ExportPreset.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 160)

                if isExporting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
                Spacer()
            }

            Text(rangeSummary)
                .font(.system(size: 9))
                .foregroundColor(.dsTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 70)

            if preset == .custom {
                HStack(spacing: 6) {
                    // .field, not a pop-up calendar: the popover is transient, so a
                    // calendar in its own window would dismiss this panel.
                    DatePicker("", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                    Text("to")
                        .font(.system(size: 9))
                        .foregroundColor(.dsTextTertiary)
                    DatePicker("", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                    Spacer()
                }
            }

            if let exportError {
                Text(exportError)
                    .font(.system(size: 9))
                    .foregroundColor(.dsAccentAmber)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    /// What the current choice resolves to, on the platform's own UTC day grid —
    /// shown so the user can see the window before writing a file.
    private var resolvedRange: DateRange {
        preset.resolve(customStart: customStart, customEnd: customEnd)
    }

    private var rangeSummary: String {
        let range = resolvedRange
        let lastDay = ExportCalendar.utc.date(byAdding: .day, value: -1, to: range.end) ?? range.start
        let days = range.dayCount
        return "\(Self.dayStamp.string(from: range.start)) → \(Self.dayStamp.string(from: lastDay)) · \(days) day\(days == 1 ? "" : "s")"
    }

    /// Whether the choice falls outside the 30-day window already loaded — said up
    /// front, so a fetch and its spinner are expected rather than mysterious.
    private var needsFetch: Bool {
        let loaded = DateRange.trailing(days: UsageExportService.loadedWindowDays,
                                        now: tracker.snapshot.lastUpdated,
                                        calendar: .current)
        if case .fetch = ExportSource.plan(range: resolvedRange, loadedWindow: loaded, calendar: ExportCalendar.utc) {
            return true
        }
        return false
    }

    private var rangeHint: String {
        needsFetch
            ? "Fetches this range from DeepSeek; cost is estimated"
            : "Served from the loaded window; cost is estimated"
    }

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Fetches (if the range is outside the loaded window), encodes, then opens the
    /// save panel. Everything is prepared before the panel opens: the popover is
    /// `.transient` and drops the moment focus leaves.
    private func export(ext: String) {
        exportError = nil
        isExporting = true
        Task { @MainActor in
            do {
                let bundle = try await UsageExportService.shared.bundle(
                    for: preset,
                    customStart: customStart,
                    customEnd: customEnd,
                    loaded: tracker.snapshot
                )
                let data: Data
                let type: UTType
                if ext == "csv" {
                    data = Data(UsageExporter.csv(bundle).utf8)
                    type = .commaSeparatedText
                } else {
                    data = try UsageExporter.json(bundle)
                    type = .json
                }
                isExporting = false
                save(data, name: UsageExporter.suggestedFilename(bundle, ext: ext), type: type)
            } catch {
                isExporting = false
                exportError = URLErrorPresenter.shortSummary(for: error.localizedDescription)
            }
        }
    }

    /// Data is encoded before the panel opens: the popover is `.transient` and
    /// dismisses the moment focus leaves, so nothing here may depend on this view
    /// still being alive. `.accessory` apps also need an explicit activate or the
    /// panel can open behind the frontmost app without focus.
    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}


struct SmallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.dsAccentBlueHover)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.dsAccentBlue.opacity(configuration.isPressed ? 0.30 : 0.15))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dsAccentBlue.opacity(0.3), lineWidth: 1))
            .cornerRadius(6)
            .contentShape(Rectangle())
    }
}
