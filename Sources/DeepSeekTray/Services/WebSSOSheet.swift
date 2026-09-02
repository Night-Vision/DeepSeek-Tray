import AppKit
import WebKit

@MainActor
final class WebSSOSheet: NSWindow, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: WKWebView
    private var contentController: WKUserContentController?
    private let siteURL: URL
    private let initialEmail: String?
    private let initialPassword: String?
    private var isHeadless: Bool
    private var hasPrefilled = false
    private var pendingCompletion: ((Bool) -> Void)?
    private var saved = false
    /// Silent renewal mode: invisible, no prefill; aborts quietly on sign-in or
    /// timeout. Used to re-capture a fresh token via the persisted WebKit session.
    private let silent: Bool

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
                // Headers only — never read bodies: auth is a Bearer JWT in the
                // request headers, and we don't want prompt/response content in JS memory.
                SEND({ type: 'fetch', url, method, status: response.status, headers });
                return response;
            } catch (err) {
                SEND({ type: 'fetch', url, method, status: 0, headers });
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
                       status: this.status, headers: this._dsHeaders || {} });
            });
            return origSend.apply(this, arguments);
        };
    })();
    """

    init(siteURL: URL, initialEmail: String? = nil, initialPassword: String? = nil, isHeadless: Bool = false, silent: Bool = false) {
        self.siteURL = siteURL
        self.initialEmail = initialEmail
        self.initialPassword = initialPassword
        self.silent = silent
        // Silent renewal must never surface a window.
        self.isHeadless = silent ? true : isHeadless

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
        // Some platforms gate features on the user agent; present as Safari.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
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

        if isHeadless {
            self.alphaValue = 0
        }

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
        if !isHeadless {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let timeout: TimeInterval = silent ? 25 : 15
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, !self.saved else { return }
                print("[WebSSOSheet] \(self.silent ? "Silent renewal timed out after 25s" : "Headless sign-in timed out after 15s")")
                self.handleDismiss(success: false)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[WebSSOSheet] didFinish: \(webView.url?.absoluteString ?? "?") title: \(webView.title ?? "?")")

        // Silent renewal: landing on the sign-in page means the platform session
        // is truly dead — give up quietly so the caller falls back to re-login.
        if silent, let url = webView.url?.absoluteString, url.contains("/sign_in") {
            print("[WebSSOSheet] silent renewal: redirected to /sign_in — session dead")
            handleDismiss(success: false)
            return
        }

        if let url = webView.url?.absoluteString, url.contains("/sign_in"),
           let email = initialEmail, let password = initialPassword,
           !email.isEmpty, !password.isEmpty, !hasPrefilled {
            hasPrefilled = true
            let escapedEmail = (try? String(data: JSONEncoder().encode(email), encoding: .utf8)) ?? "\"\""
            let escapedPassword = (try? String(data: JSONEncoder().encode(password), encoding: .utf8)) ?? "\"\""
            let script = """
            (function() {
                const e = document.querySelector('input[type="email"], input[name="email"], input[type="text"], input[autocomplete="username"]');
                const p = document.querySelector('input[type="password"], input[name="password"], input[autocomplete="current-password"]');
                if (e && p) {
                    e.value = \(escapedEmail);
                    p.value = \(escapedPassword);
                    e.dispatchEvent(new Event('input', { bubbles: true }));
                    p.dispatchEvent(new Event('input', { bubbles: true }));
                    e.dispatchEvent(new Event('change', { bubbles: true }));
                    p.dispatchEvent(new Event('change', { bubbles: true }));
                    setTimeout(() => {
                        const btn = document.querySelector('button[type="submit"], button.ds-button--primary, form button');
                        if (btn) btn.click();
                    }, 200);
                }
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] _, _ in
                if self?.isHeadless == true {
                    self?.scheduleCaptchaCheck()
                }
            }
        }

        // Diagnostics only: on any post-login platform page, dump the SPA state
        // 10s later so stuck spinner/error screens are visible in the log.
        guard let host = webView.url?.host,
              host == "platform.deepseek.com" || host.hasSuffix(".deepseek.com"),
              let url = webView.url?.absoluteString,
              !url.contains("/sign_in") else { return }
        schedulePageStateProbe()
    }

    private func scheduleCaptchaCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isHeadless, !self.saved else { return }
            self.webView.evaluateJavaScript("""
                !!document.querySelector('iframe[src*="captcha"], iframe[src*="cloudflare"], div[class*="captcha"]')
            """) { [weak self] result, _ in
                if let hasCaptcha = result as? Bool, hasCaptcha {
                    print("[WebSSOSheet] CAPTCHA challenge detected — revealing login window for user completion")
                    self?.isHeadless = false
                    self?.alphaValue = 1.0
                    self?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // 10s after the OAuth callback: dump the page state so we can see whether
    // the SPA is stuck on a spinner, an error, or actually reached the dashboard.
    private func schedulePageStateProbe() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.saved else { return }
            self.webView.evaluateJavaScript("""
                JSON.stringify({ ready: document.readyState, href: location.href,
                                 title: document.title,
                                 body: (document.body ? document.body.innerText : '').slice(0, 200) })
            """) { result, error in
                if let error {
                    print("[WebSSOSheet] probe error: \(error.localizedDescription)")
                } else if let json = result as? String {
                    print("[WebSSOSheet] probe: \(json)")
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate failures

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebSSOSheet] didFail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[WebSSOSheet] didFailProvisional: \(error.localizedDescription)")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "networkInterceptor",
              let dict = message.body as? [String: Any],
              let url = dict["url"] as? String else { return }

        // Header-only detection: auth is a Bearer JWT, and the usage endpoint is
        // the /api/v0/usage/* schema. The interceptor never reads bodies, so the
        // gate is the URL pattern + an Authorization header present.
        let lower = url.lowercased()
        let headers = (dict["headers"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        guard headers.keys.contains(where: { $0.lowercased() == "authorization" }) else { return }

        // Balance-shaped traffic: record the endpoint so the tray can show the
        // wallet balance — never a dismissal trigger (login ends on the usage
        // capture below).
        if lower.contains("balance") {
            DiscoveredDashboardUsageClient.saveBalanceEndpoint(
                DiscoveredDashboardUsageClient.DiscoveredEndpoint(
                    url: url,
                    method: (dict["method"] as? String) ?? "GET",
                    headers: headers,
                    discoveredAt: Date()
                )
            )
            print("[WebSSOSheet] balance endpoint captured: \(url)")
            return
        }

        guard lower.contains("/api/v0/usage/"),
              !lower.contains("cost"), !lower.contains("billing") else { return }

        // Persist the fresh Bearer JWT NOW, from the raw capture — the sanitized
        // endpoint saved below no longer carries it (security fix).
        for (name, value) in headers where name.lowercased() == "authorization" {
            _ = KeychainManager.save(account: "googleToken", value: value)
        }

        DiscoveredDashboardUsageClient.saveEndpoint(
            DiscoveredDashboardUsageClient.DiscoveredEndpoint(
                url: url,
                method: (dict["method"] as? String) ?? "GET",
                headers: headers,
                discoveredAt: Date()
            )
        )
        // Remember the page that fired usage traffic so silent renewal can reload
        // exactly this page and re-trigger the SPA without user interaction.
        if let page = webView.url?.absoluteString, !page.isEmpty {
            UserDefaults.standard.set(page, forKey: "ds_dashboard_page_url")
        }
        // Endpoint captured = auth succeeded (auth rides in the captured request
        // headers, not a cookie). Close the sheet and let the app poll it.
        handleDismiss(success: true)
    }

    @objc private func windowWillClose(_ note: Notification) {
        handleDismiss(success: false)
    }

    private func handleDismiss(success: Bool) {
        guard !saved else { return }
        saved = true
        let completion = pendingCompletion
        pendingCompletion = nil

        // Break script message handler & retain cycle before window teardown on @MainActor
        contentController?.removeScriptMessageHandler(forName: "networkInterceptor")
        contentController = nil

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
