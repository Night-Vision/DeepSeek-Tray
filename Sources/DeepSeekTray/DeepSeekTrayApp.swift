import SwiftUI
import AppKit

@main
struct DeepSeekTrayApp: App {
    private let statusItemController = TrayStatusItemController()

    init() {
        NSApp.setActivationPolicy(.accessory)
        // One-shot: clear response bodies cached by builds that used URLSession.shared.
        HTTPCachePurger.purgeIfNeeded()
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
