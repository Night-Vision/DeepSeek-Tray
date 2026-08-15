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
        let host = NSHostingController(
            rootView: PopoverRootView().environmentObject(tracker)
        )
        // Let SwiftUI drive the popover size: preferredContentSize stays in sync with the
        // root view's ideal size (correct width 220/320 AND natural height) instead of going
        // stale at the mini layout.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        // Keep the button title live with the tray label and keep popover arrow centered
        tracker.$trayLabelText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self, let button = self.statusItem.button else { return }
                button.title = text
                DispatchQueue.main.async { [weak self] in
                    guard let self, let button = self.statusItem.button else { return }
                    button.superview?.layoutSubtreeIfNeeded()
                    button.window?.layoutIfNeeded()
                    if self.popover.isShown {
                        self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    }
                }
            }
            .store(in: &cancellables)

        // Resize the popover when switching between mini (220) and full (320) views.
        // preferredContentSize only refreshes after the new root view re-renders, so read
        // it on the next runloop turn — no stale fitting sizes, no blank strip.
        tracker.$currentView
            .receive(on: RunLoop.main)
            .sink { [weak self] view in
                guard let self, let host = self.popover.contentViewController else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let size = host.preferredContentSize
                    if size.width > 0 {
                        host.preferredContentSize = size
                        self.popover.contentSize = size
                        if let button = self.statusItem.button, self.popover.isShown {
                            button.superview?.layoutSubtreeIfNeeded()
                            button.window?.layoutIfNeeded()
                            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                        }
                    }
                }
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
