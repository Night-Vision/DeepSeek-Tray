import AppKit
import SwiftUI
import Combine

@MainActor
final class TrayStatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let tracker = UsageTracker.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "DeepSeek Tray")
            button.imagePosition = .imageLeading
            button.title = tracker.trayLabelText
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView().environmentObject(tracker)
        )

        // Keep the button title live with the tray label
        tracker.$trayLabelText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.statusItem.button?.title = text
            }
            .store(in: &cancellables)

        // Resize the popover when switching between mini (220) and full (320) views
        tracker.$currentView
            .receive(on: RunLoop.main)
            .sink { [weak self] view in
                self?.popover.contentSize = view == .mini ? NSSize(width: 220, height: 300) : NSSize(width: 320, height: 520)
            }
            .store(in: &cancellables)
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            contextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "")
        menu.addItem(withTitle: "Open Mini Widget", action: #selector(openMini), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit DeepSeek Tray", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func refresh() {
        Task { await tracker.refresh() }
    }

    @objc private func openDashboard() {
        open(view: .dashboard)
    }

    @objc private func openMini() {
        open(view: .mini)
    }

    @objc private func openPreferences() {
        open(view: .preferences)
    }

    private func open(view: PopoverView) {
        tracker.show(view)
        if let button = statusItem.button {
            showPopover(from: button)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
