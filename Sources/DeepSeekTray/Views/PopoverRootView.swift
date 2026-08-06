import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject var tracker: UsageTracker

    var body: some View {
        Group {
            switch tracker.currentView {
            case .dashboard:
                DashboardView()
            case .auth:
                AuthView()
            case .preferences:
                PreferencesView()
            case .mini:
                MiniWidgetView()
            }
        }
        .frame(width: tracker.currentView == .mini ? Metrics.miniWidth : Metrics.popoverWidth)
    }
}
