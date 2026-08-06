import SwiftUI

@main
struct DeepSeekTrayApp: App {
    @StateObject private var tracker = UsageTracker.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environmentObject(tracker)
        } label: {
            Label(tracker.trayLabelText, systemImage: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
