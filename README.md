<div align="center">
  <h3>🎛️ CodexGauge</h3>
  <p><em>Your Codex API usage, visualized as a beautiful dashboard gauge.</em></p>

  <img src="https://your-screenshot-url.png" alt="CodexGauge Screenshot" width="340" />
  <br /><br />

  <a href="https://github.com/wujin4991747/CodexGauge/stargazers"><img src="https://img.shields.io/github/stars/wujin4991747/CodexGauge?color=ffcb47&labelColor=black&style=flat-square&logo=github&label=Stars" /></a>
  <a href="https://github.com/wujin4991747/CodexGauge/releases"><img src="https://img.shields.io/github/downloads/wujin4991747/CodexGauge/total?color=369eff&labelColor=black&logo=github&style=flat-square&label=Downloads" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?color=34C759&labelColor=black&style=flat-square" /></a>
  <a><img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?color=7F77DD&labelColor=black&style=flat-square&logo=apple" /></a>
  <br /><br />
</div>

> Track how much of your Codex quota remains — with a dashboard-style gauge that looks as good as it works. Red, yellow, green. One glance is all it takes.

## 📦 Installation

| Platform | Method | Link |
| :--- | :--- | :--- |
| macOS 14+ | **Direct Download** | [Releases](https://github.com/wujin4991747/CodexGauge/releases) |
| macOS 14+ | **Build from Source** | `git clone` → `xcodegen generate` → Run |

### Direct Download

1. Download `CodexGauge.zip` from [Releases](https://github.com/wujin4991747/CodexGauge/releases)
2. Unzip and drag `CodexGauge.app` to `/Applications`
3. First launch: see [Gatekeeper workaround](#-first-launch-gatekeeper) below

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/wujin4991747/CodexGauge.git
cd CodexGauge
xcodegen generate
open CodexGauge.xcodeproj   # then hit ▶️
```

> [!IMPORTANT]
> ### ⚠️ First Launch — Gatekeeper
> Since CodexGauge is not yet notarized, macOS will block it on first launch.
>
> **Right-click** `CodexGauge.app` in Finder → **Open** → click **Open** in the dialog.
>
> That's it. You only need to do this once.

## 🔧 Prerequisites

CodexGauge reads data from your local **Codex CLI**. Make sure it's installed and logged in:

```bash
npm install -g @anthropic-ai/codex
codex login
```

## ✨ Features

### At-a-Glance Dashboard

A 270-degree arc gauge with a needle that swings to your current usage. Red when critical, yellow when warming, green when full. Rendered on the GPU via SwiftUI Canvas.

![Dashboard](https://your-screenshot-url.png)

### Smart Proxy Detection

Auto-detects your macOS system proxy (Clash, Surge, etc.). Falls back to manual configuration when needed. Works out of the box for users in mainland China and other restricted networks.

### Refresh & Pin

Tap **Refresh** to pull the latest numbers. Pin the window on top with one click so your quota is always visible while coding.

### Intelligent Alerts

- **Under 10%** → gauge glows yellow
- **At 0%** → gauge glows red
- Shows exact **reset time** so you know when fresh quota arrives

## 🌐 Proxy Setup (China / Restricted Networks)

| Method | How |
| :--- | :--- |
| **Auto (recommended)** | Ensure ClashX / Surge has "System Proxy" enabled. App detects it automatically. |
| **Manual** | Expand the proxy section, uncheck "Use system proxy", enter host & port. |

> [!TIP]
> Default proxy ports: Clash → `7890` / Surge → `6152` / V2Ray → `1087`

## 🐛 Troubleshooting

| Problem | Solution |
| :--- | :--- |
| No data shown | Run `codex login` to make sure you're authenticated |
| Proxy not working | Check the port number. Test with `curl -x http://127.0.0.1:PORT https://chatgpt.com` |
| Stuck loading | In terminal: `codex app-server --listen stdio://` to see if the CLI responds |
| Permission error after update | Re-run the right-click → Open Gatekeeper step |

## 🛠 Tech Stack

- **SwiftUI** + **Canvas** — native macOS, GPU-accelerated gauge
- **XcodeGen** — declarative `.xcodeproj` generation
- **Python 3** — lightweight JSON-RPC bridge to Codex CLI
- **SystemConfiguration** — system proxy auto-detection

## 📄 License

[MIT](LICENSE) © 2026

---

<p align="center">Made with ❤️ for the Codex community</p>
