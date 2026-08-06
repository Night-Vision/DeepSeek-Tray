import AppKit
import WebKit

@MainActor
final class WebSSOSheet: NSWindow, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: WKWebView
    private var contentController: WKUserContentController?
    private let siteURL: URL
    private var pendingCompletion: ((Bool) -> Void)?
    private var saved = false
    private var pendingDiscovery = false

    // Intercepts fetch/XHR on the platform site and forwards usage-shaped traffic to Swift.
    private static let interceptorScript = """
    (function() {
        if (window.__dsInterceptorInstalled) return;
        window.__dsInterceptorInstalled = true;
        const SEND = (payload) => {
            if (window.webkit?.messageHandlers?.networkInterceptor) {
                window.webkit.messageHandlers.networkInterceptor.postMessage(payload);
            }
        };
        const cap = (s) => (s || '').slice(0, 30000);

        const origFetch = window.fetch;
        window.fetch = async function(resource, init) {
            const url = typeof resource === 'string' ? resource : resource.url;
            const method = (init && init.method) || 'GET';
            let headers = {};
            try {
                if (init && init.headers) headers = Object.fromEntries(new Headers(init.headers).entries());
            } catch (e) {}
            try {
                const response = await origFetch.apply(this, arguments);
                try {
                    const clone = response.clone();
                    SEND({ type: 'fetch', url, method, status: response.status,
                           headers, body: cap(await clone.text()) });
                } catch (e) {}
                return response;
            } catch (err) {
                SEND({ type: 'fetch', url, method, status: 0, headers, body: '' });
                throw err;
            }
        };

        const origOpen = XMLHttpRequest.prototype.open;
        const origSend = XMLHttpRequest.prototype.send;
        const origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.open = function(method, url) {
            this._dsUrl = url;
            this._dsMethod = method;
            this._dsHeaders = {};
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            try { this._dsHeaders[name] = value; } catch (e) {}
            return origSetHeader.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function(body) {
            this.addEventListener('load', function() {
                SEND({ type: 'xhr', url: this._dsUrl || '', method: this._dsMethod || 'GET',
                       status: this.status, headers: this._dsHeaders || {},
                       body: cap(this.responseText) });
            });
            return origSend.apply(this, arguments);
        };
    })();
    """

    init(siteURL: URL) {
        self.siteURL = siteURL

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(source: Self.interceptorScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )
        config.userContentController = userContentController

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
        self.contentController = userContentController
        userContentController.add(self, contentWorld: .page, name: "networkInterceptor")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        contentController?.removeScriptMessageHandler(forName: "networkInterceptor")
    }

    func start(completion: @escaping (Bool) -> Void) {
        self.pendingCompletion = completion
        let request = URLRequest(url: siteURL)
        webView.load(request)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only evaluate cookies on the DeepSeek platform itself, never on Google
        // sign-in intermediates. Skip the pre-login /sign_in page.
        guard let host = webView.url?.host,
              host == "platform.deepseek.com" || host.hasSuffix(".deepseek.com"),
              let url = webView.url?.absoluteString,
              !url.contains("/sign_in") else { return }
        evaluateCookies()
    }

    private func evaluateCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async { self?.captureAndStore(cookies) }
        }
    }

    private func captureAndStore(_ cookies: [HTTPCookie]) {
        guard !saved else { return }

        // Evidence log: which cookies exist on which page (names only, no values).
        print("[WebSSOSheet] page: \(webView.url?.absoluteString ?? "?")")
        print("[WebSSOSheet] cookies: \(cookies.map(\.name).sorted())")

        // Gate on a real auth cookie — pre-login/stale cookies (csrftoken, CF,
        // leftover session) must not trigger capture or dismissal.
        guard hasAuthCookie(cookies) else { return }

        let header = cookies
            .filter { $0.domain == "deepseek.com" || $0.domain.hasSuffix(".deepseek.com") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        guard !header.isEmpty else { return }
        let ok = KeychainManager.save(account: "sessionCookie", value: header)
        if ok && !pendingDiscovery {
            // Already have a working endpoint from a previous discovery? Done.
            if DiscoveredDashboardUsageClient.loadEndpoint() != nil {
                handleDismiss(success: true)
            } else {
                // Otherwise drive the dashboard so the usage API fires under the interceptor.
                pendingDiscovery = true
                webView.load(URLRequest(url: URL(string: "https://platform.deepseek.com/dashboard")!))
            }
        }
    }

    // ponytail: heuristic seed for DeepSeek's session cookie name — refine from
    // the evidence log after one real login.
    private static let authCookieNames: Set<String> = ["session", "jwt", "token", "access_token", "auth", "user"]

    private func hasAuthCookie(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { Self.authCookieNames.contains($0.name.lowercased()) }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "networkInterceptor",
              let dict = message.body as? [String: Any],
              let url = dict["url"] as? String else { return }

        let patterns = ["usage", "stat", "daily", "tokens", "billing", "cost"]
        guard patterns.contains(where: { url.lowercased().contains($0) }),
              let body = dict["body"] as? String,
              hasUsageShape(body) else { return }

        let headers = (dict["headers"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        DiscoveredDashboardUsageClient.saveEndpoint(
            DiscoveredDashboardUsageClient.DiscoveredEndpoint(
                url: url,
                method: (dict["method"] as? String) ?? "GET",
                headers: headers,
                discoveredAt: Date()
            )
        )
        finishDiscovery()
    }

    private func hasUsageShape(_ body: String) -> Bool {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return containsUsageKey(json)
    }

    private func containsUsageKey(_ value: Any) -> Bool {
        let usageKeys = ["date", "tokens", "cost", "requests", "usage", "daily", "hourly"]
        if let dict = value as? [String: Any] {
            if dict.keys.contains(where: { usageKeys.contains($0.lowercased()) }) { return true }
            return dict.values.contains { containsUsageKey($0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsUsageKey($0) }
        }
        return false
    }

    private func finishDiscovery() {
        guard pendingDiscovery else { return }
        pendingDiscovery = false
        // Close only on success — on failure keep the window open so the user can
        // navigate the dashboard manually; they close it themselves.
        if DiscoveredDashboardUsageClient.loadEndpoint() != nil {
            handleDismiss(success: true)
        }
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
