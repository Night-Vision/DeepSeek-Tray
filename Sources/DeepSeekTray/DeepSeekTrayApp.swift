import SwiftUI
import AppKit

@main
struct DeepSeekTrayApp: App {
    private let statusItemController = TrayStatusItemController()

    init() {
        NSApp.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
