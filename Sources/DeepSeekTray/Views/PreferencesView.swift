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
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Usage Data")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dsTextPrimary)
                Text("Save the current \(prefs.extendedViewStyle.days)-day window; cost is estimated")
                    .font(.system(size: 9))
                    .foregroundColor(.dsTextTertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("CSV") { exportCSV() }
                    .buttonStyle(SmallPillButtonStyle())
                Button("JSON") { exportJSON() }
                    .buttonStyle(SmallPillButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }

    private func exportCSV() {
        let data = Data(UsageExporter.csv(tracker.snapshot).utf8)
        save(data, name: UsageExporter.suggestedFilename(ext: "csv"), type: .commaSeparatedText)
    }

    private func exportJSON() {
        guard let data = try? UsageExporter.json(tracker.snapshot, windowDays: prefs.extendedViewStyle.days) else { return }
        save(data, name: UsageExporter.suggestedFilename(ext: "json"), type: .json)
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
