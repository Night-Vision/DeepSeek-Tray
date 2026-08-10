import SwiftUI

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
