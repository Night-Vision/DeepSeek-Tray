import AppKit
import WebKit

@MainActor
final class WebSSOSheet: NSWindow, WKNavigationDelegate {
    private let webView: WKWebView
    private let siteURL: URL
    private var pendingCompletion: ((Bool) -> Void)?
    private var saved = false

    init(siteURL: URL) {
        self.siteURL = siteURL

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let frame = NSRect(x: 0, y: 0, width: 480, height: 640)
        let webView = WKWebView(frame: frame, configuration: config)
        self.webView = webView

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Sign in to DeepSeek"
        self.contentView = webView
        self.isReleasedWhenClosed = false
        self.webView.navigationDelegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(completion: @escaping (Bool) -> Void) {
        self.pendingCompletion = completion
        let request = URLRequest(url: siteURL)
        webView.load(request)

        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        parent.beginSheet(self) { _ in }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluateCookies()
    }

    private func evaluateCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async { self?.captureAndStore(cookies) }
        }
    }

    private func captureAndStore(_ cookies: [HTTPCookie]) {
        guard !saved else { return }
        let header = cookies
            .filter { $0.domain == "deepseek.com" || $0.domain.hasSuffix(".deepseek.com") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        guard !header.isEmpty else { return }
        let ok = KeychainManager.save(account: "sessionCookie", value: header)
        if ok { handleDismiss(success: true) }
    }

    @objc private func windowWillClose(_ note: Notification) {
        handleDismiss(success: false)
    }

    private func handleDismiss(success: Bool) {
        guard !saved else { return }
        saved = true
        let completion = pendingCompletion
        pendingCompletion = nil

        // Break NSWindow -> contentView -> webView -> navigationDelegate -> self cycle
        // before tearing the window down so the sheet actually deallocates.
        webView.navigationDelegate = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))

        if let parent = self.sheetParent {
            parent.endSheet(self, returnCode: success ? .OK : .cancel)
        } else {
            self.close()
        }
        completion?(success)
    }
}
