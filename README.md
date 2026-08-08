# DeepSeek Tray

A lightweight macOS menu-bar app that keeps an eye on your [DeepSeek](https://platform.deepseek.com) API balance and token usage — right from the menu bar.

![Platform](https://img.shields.io/badge/macOS-14%2B-black) ![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- **Balance monitoring** — live API-key balance via the official `GET /user/balance` endpoint
- **Live session tracking** — real-time token/cost stats from chat-completion responses (`sendChat`), with a context-window usage bar
- **Tray display modes** — today's tokens, monthly total, or estimated cost right in the menu bar label
- **Right-click tray menu** — Refresh Now, Open Dashboard, Open Mini Widget, Preferences…, Quit
- **Flexible sign-in** — API key or Google SSO (standalone WKWebView window), secrets stored in macOS Keychain
- **Automatic usage discovery** — the SSO sheet captures the platform's usage API (endpoint, headers); cost/tokens/charts populate from the replay, including monthly spend via the billing API (`/api/v0/usage/cost`)
- **Mini widget & charts** — compact popover widget and a 7-day stacked usage chart (per-model bars), both driven by the platform's daily-granularity data (last 7 days)
- **Dashboard ⇄ mini toggle** — sideways-arrow buttons in both corners: collapse the full dashboard to the mini widget (`→←`) and expand back (`←→`)
- **Sizes itself to content** — the popover resizes to each view's natural height (no blank space); Preferences/Dashboard open full-width even from the mini widget
- **Dark theme** — designed around a custom DS design system

## Requirements

- macOS 14.0+
- Swift 5.10 (Swift Package Manager)
- A DeepSeek platform account (API key or dashboard session)

## Build & Run

```bash
swift build
swift run DeepSeekTray
```

Release build:

```bash
swift build -c release
```

## Install (no build required)

Grab the latest `DeepSeekTray-<version>.zip` from [Releases](https://github.com/plugin87/deepseek-tray/releases), unzip, and drag `DeepSeekTray.app` to Applications.

> **Note (Gatekeeper):** the release build is ad-hoc signed (no Apple Developer ID, no sandbox), so macOS will block it the first time. Either:
> - Right-click `DeepSeekTray.app` → **Open** → **Open**, or
> - run `xattr -dr com.apple.quarantine "DeepSeekTray.app"` in the folder
>
> Then it launches normally from then on. Fully notarized builds need a $99/yr Apple Developer account.

## Screenshots

![App Screenshot](assets/screenshots/screenshot-tray.jpg)
![Dashboard Screenshot](assets/screenshots/screenshot-expanded-view.jpg)
![Mini Screenshot](assets/screenshots/screenshot-mimi-view.jpg)
![SSO Screenshot](assets/screenshots/screenshot-login.jpg)


## Sign-in

Two ways to connect your account:

1. **API key** — paste a key from [platform.deepseek.com](https://platform.deepseek.com/api_keys); balance is fetched from the official API. This is the primary data source.
2. **Google SSO** — sign in through a standalone WKWebView window; the window intercepts the platform's usage API traffic and captures it (endpoint + auth headers) so cost/tokens/charts populate automatically.

### How SSO works (exact flow)

1. "Sign in with Google" opens a **standalone** WKWebView window (never a sheet on the tray popover, which would close on resign-key).
2. A JS interceptor is injected at `documentStart` (all frames) that shadows `fetch`/`XMLHttpRequest` and forwards `url, method, status, body (≤30KB), headers` to Swift.
3. You complete Google OAuth; the platform's `/authorized` callback loads.
4. **Auth is header-based, not cookie-based**: the platform SPA keeps a Bearer JWT client-side and sends it per-request (`authorization` + `x-client-*` headers). No session cookie ever exists — this is why cookie-based capture could never work.
5. The SPA navigates to the Usage page and fires the usage API; the interceptor catches it and Swift validates the response is usage-shaped JSON.
6. The sheet stores `ds_discovered_usage_endpoint` (`url`, `method`, `headers`, `discoveredAt` — never bodies) in UserDefaults, then **auto-closes**.
7. `UsageTracker.refresh()` replays that endpoint (relative URLs resolved against `https://platform.deepseek.com`, captured headers as auth) alongside the balance fetch; failures fall back to empty defaults without touching the balance error.

Credentials live in the macOS Keychain under service `com.deepseek.tray` — never in plain files: the API key under account `apiKey`, the SSO Bearer JWT under `googleToken` (restored at launch, so the session survives restarts), and the legacy manual-paste session cookie under `sessionCookie`. The captured usage endpoint config (URL + headers, never bodies) is stored in UserDefaults as `ds_discovered_usage_endpoint`.

## Security

- API keys and session cookies are stored in the macOS Keychain (`kSecClassGenericPassword`, accessible after first unlock)
- No telemetry, no network calls beyond DeepSeek's own endpoints

## License

[MIT](LICENSE)

---

> **Note:** dashboard usage totals (requests/tokens per day + key breakdown) populate automatically once the SSO sheet captures the platform's usage endpoint; monthly cost comes from the billing API `/api/v0/usage/cost` (the usage endpoint itself carries no dollar figures). Until then the stat cards reflect balance + live session data.
