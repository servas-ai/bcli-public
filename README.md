<p align="center">
  <img src="assets/cover.png" alt="bcli – Browser as a Service" width="100%">
</p>

<h1 align="center">bcli</h1>

<p align="center">
  <strong>Real, headed cloud browsers for your agents and tests — one command away.</strong><br>
  The command-line client for <a href="https://servas.ai">servas.ai</a> Browser as a Service (BaaS).
</p>

<p align="center">
  <a href="https://github.com/servas-ai/bcli-public/releases"><img alt="Release" src="https://img.shields.io/github/v/release/servas-ai/bcli-public?sort=semver&label=release&color=6f42c1"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows-0aa2c0">
  <img alt="Architectures" src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-0aa2c0">
  <img alt="License" src="https://img.shields.io/badge/license-proprietary%20%E2%80%93%20free%20with%20a%20servas.ai%20account-555">
  <a href="docs/agents.md"><img alt="Agent ready" src="https://img.shields.io/badge/agents-Claude%20Code%20%7C%20Codex%20%7C%20any%20CDP%20client-111"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="docs/installation.md">Install</a> ·
  <a href="docs/usage.md">Usage guide</a> ·
  <a href="docs/agents.md">Agents</a> ·
  <a href="docs/configuration.md">Configuration</a> ·
  <a href="docs/security.md">Security</a> ·
  <a href="docs/troubleshooting.md">Troubleshooting</a>
</p>

---

`bcli` starts a real Chromium browser in the servas.ai cloud — rendered on a real display, not headless — and hands you a
standard **Chrome DevTools Protocol (CDP)** endpoint. Point Playwright, Puppeteer or your AI agent at it, watch it live in
your own browser, and stop it when you are done. The same CLI also runs browsers **locally** on your machine, with a
built-in credential vault that fills logins without the agent ever seeing the password.

```text
your laptop / agent                      servas.ai cloud
┌──────────────────────┐   HTTPS (OIDC)  ┌───────────────────────────┐
│ bcli session create  │ ──────────────▶ │ api.baas.servas.ai        │
│                      │                 │   ▼                       │
│ Playwright / agent   │   WSS (CDP)     │ headed Chromium session   │ ──▶ the web, through
│ connectOverCDP(...)  │ ──────────────▶ │ edge.baas.servas.ai/s/<id>│     your tenant's exit node
│                      │                 │                           │
│ your browser         │   HTTPS (view)  │ live view, take over      │
│ view_url             │ ──────────────▶ │ mouse & keyboard          │
└──────────────────────┘                 └───────────────────────────┘
```

## Quick start

After [installing](#install) `bcli`:

```bash
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai && bcli env use cloud
bcli login                      # OIDC device-code sign-in via auth.servas.ai
bcli session create --wait      # prints JSON with id, cdp_url, cdp_ws_url, view_url
```

Then connect any CDP client and stop the session when you are done:

```javascript
import { chromium } from 'playwright';

const browser = await chromium.connectOverCDP(process.env.CDP_URL); // the session's cdp_url
const context = browser.contexts()[0] ?? await browser.newContext();
const page = context.pages()[0] ?? await context.newPage();
await page.goto('https://example.com');
console.log(await page.title());
await browser.close();          // disconnects only – the session keeps running
```

```bash
bcli session stop <id>
```

No VPN, no Kubernetes, no proxy contracts and no browser updates on your side. All you need is a servas.ai account.

## Highlights

| | |
|---|---|
| **Real, headed browsers** | Every session is a full Chromium rendered on a real display, with a consistent fingerprint (`--seed`, `--locale`, `--timezone`, `--viewport`). |
| **Standard CDP** | `cdp_url` works with Playwright `connectOverCDP`, Puppeteer `connect` and any CDP library. No SDK lock-in. |
| **Live view and hand-over** | `view_url` opens the session in your own browser. Watch the agent work and take over mouse and keyboard when a human is needed. |
| **Persistent profiles** | `bcli profile create` keeps cookies and logins across sessions, with an exclusive lock so two runs never corrupt one profile. |
| **Your own exit IP** | Sessions leave the internet through your tenant's exit node. Run one in your office or data center with a single Docker command: [`servas-ai/baas-exit-docker`](https://github.com/servas-ai/baas-exit-docker). |
| **localhost in the cloud** | `bcli tunnel start --ports 3000` makes your dev server reachable as `http://localhost:3000` inside the remote browser. |
| **Credentials without exposure** | The local vault and the bundled credential extension fill usernames, passwords, TOTP codes and passkeys into the page. The agent only references an entry id; it never reads the secret. |
| **Bitwarden with human approval** | `bcli vault bw` fills logins from your Bitwarden vault (bitwarden.com, bitwarden.eu, self-hosted) into local and cloud sessions after a person approves each one in a native window. Linux, macOS, Windows. |
| **GPU sessions** | `--gpu` for WebGL, canvas-heavy apps and video. |
| **Audio** | `bcli audio attach` streams the session's speaker and microphone as PCM, e.g. for voice agents (Linux, macOS). |
| **Local mode** | `bcli daemon` runs the same session API on your own machine. Same commands, same JSON. |
| **Agent-first CLI** | Stable JSON on stdout, stable exit codes, ready-made [agent skills](skills/bcli/SKILL.md). |
| **Signed self-update** | `bcli update` verifies the Ed25519-signed release checksums before replacing itself (Linux, macOS and Windows). |
| **Operated in the EU** | The servas.ai cloud runs in Austria on its own hardware. Sign-in uses OIDC (`auth.servas.ai`); API keys are deprecated. |

## Install

From a terminal — the installers check the Ed25519 signature of the release and the SHA-256 of the binary before
they install anything.

**Linux and macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh
```

**Windows** (PowerShell, normal window, no administrator rights)

```powershell
irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
```

**Package managers**

| | Install |
|---|---|
| Homebrew (macOS, Linux) | `brew install servas-ai/tap/bcli` |
| Scoop (Windows) | `scoop bucket add servas https://github.com/servas-ai/scoop-bucket` then `scoop install servas/bcli` (needs `scoop install git` once) |
| winget (Windows) | `winget install servas.bcli` (submitted as [winget-pkgs#486222](https://github.com/microsoft/winget-pkgs/pull/486222); available once Microsoft merges it) |

A specific release: `... | sh -s -- --version v0.14.4`, or `$env:BCLI_VERSION = "v0.14.4"` before `irm ... | iex`.
Options, manual install, upgrade and uninstall: **[docs/installation.md](docs/installation.md)**.

| Platform | Asset | Cloud sessions | Local daemon + vault |
|---|---|:---:|:---:|
| Linux x86-64 | `bcli-linux-amd64` | ✅ | ✅ |
| Linux ARM64 | `bcli-linux-arm64` | ✅ | ✅ |
| macOS Apple silicon | `bcli-darwin-arm64` | ✅ | ✅ |
| macOS Intel | `bcli-darwin-amd64` | ✅ | ¹ |
| Windows x86-64 | `bcli-windows-amd64.exe` | ✅ | ✅ |

Windows 11 on ARM runs the x64 build through emulation. Local mode needs a Chromium-based browser on the machine; see
[Local mode](docs/usage.md#local-mode). On Windows, `bcli assist` and `bcli audio` are not available; use the live
view for human hand-over. ¹ The macOS background-service helper for local mode supports Apple silicon only in this
release.

bcli is not code-signed (no Authenticode, no Apple Developer ID); the Ed25519 signature of `SHA256SUMS` with the
servas.ai release key in [`keys/`](keys/) is what proves a file is ours. Installed from the terminal, bcli starts
without a Windows or macOS prompt. **Not supported:** machines that only allow signed programs (AppLocker, App Control
for Business / WDAC, Smart App Control). See [Verify signatures](docs/installation.md#verify-the-signature-of-sha256sums)
to check a release by hand.

## Configuration in one minute

```bash
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai
bcli env use cloud
bcli login            # opens nothing by itself: follow the printed URL and code
bcli whoami           # env, owner, role, auth=oidc
bcli tenant           # your limits, usage, access expiry and default exit node
```

Configuration lives in `~/.config/bcli/config.yaml`, state and login tokens in `~/.bcli/`. Select an environment per
command with `--env NAME` or `BCLI_ENV=NAME`. All options: **[docs/configuration.md](docs/configuration.md)**.

## Usage

```bash
bcli session create --wait --json                       # new throwaway session
bcli session create --profile shop-1 --ttl 90m --wait   # with persistent logins
bcli session create --gpu --wait                        # on a GPU target
bcli session list --json
bcli session get <id> --json
bcli session url <id>                                   # reprint cdp_url
bcli session stop <id>

bcli profile create shop-1 --locale de-DE --timezone Europe/Berlin
bcli profile list
bcli exit-node list
bcli tunnel start --session <id> --ports 3000           # your localhost inside the remote browser
bcli update --check
```

The complete guide — sessions, timers, profiles, exit nodes, tunnels, live view, audio, GPU, local mode, the vault and
exit codes — is in **[docs/usage.md](docs/usage.md)**.

## Bitwarden

bcli fills logins from your Bitwarden vault after **a person approves each one** in a native window; the agent never
sees the password. The Bitwarden bridge is part of every `bcli` and runs as your user's background service (Linux:
systemd user unit, macOS: LaunchAgent, Windows: background process). On Linux and macOS the installer sets it up when
you run it in a desktop terminal; otherwise:

```bash
bcli bwbridge start                    # once; starts again at every login (Windows: see the guide)
bcli vault bw setup                    # window: API key, master password, approval password; EU accounts choose bitwarden.eu
bcli vault bw autofill --wait --submit                          # local session, active tab
bcli vault unlock --session <id> && bcli vault bw autofill --session <id> --wait --submit   # cloud session
```

**Ubuntu/Kubuntu 23.10–25.10** need an AppArmor profile for the approval window once (the installer does it when
`sudo` needs no password, otherwise it prints this):
`bcli bwbridge apparmor | sudo tee /etc/apparmor.d/bcli-prompt >/dev/null && sudo apparmor_parser -r /etc/apparmor.d/bcli-prompt`.
Complete guide: **[docs/bitwarden.md](docs/bitwarden.md)**.

## Use it from coding agents

bcli is built to be driven by agents: JSON on stdout, documented exit codes, no interactive prompts after login.

**`agent-web`** is the fastest way for an agent to browse: a small helper script (bash for Linux/macOS,
PowerShell for Windows) that combines bcli with the open-source
[agent-browser](https://www.npmjs.com/package/agent-browser) CLI. The agent works with page snapshots and element refs —
no Playwright code needed:

```bash
SID=$(agent-web start) || exit 1               # prints only the session id
agent-web ab "$SID" open https://example.com
agent-web ab "$SID" snapshot -i                # accessibility tree with refs (@e1, @e2, …)
agent-web ab "$SID" click @e3
agent-web captcha "$SID"                       # a human solves a captcha in a small window (Linux/macOS)
agent-web stop "$SID"
```

Install it next to bcli: [docs/installation.md](docs/installation.md#agent-web-helper).

- **Claude Code / Agent Skills:** copy [`skills/bcli/`](skills/bcli/) into `~/.claude/skills/` (or your project's
  `.claude/skills/`). The skill teaches the agent to create, drive and always stop sessions, and to keep tokens out of logs.
- **Codex, Cursor, Aider and other agents:** paste [`skills/AGENTS.snippet.md`](skills/AGENTS.snippet.md) into your
  repository's `AGENTS.md`.
- **Your own code:** `bcli session create` + Playwright/Puppeteer `connectOverCDP` — see [`examples/`](examples/).

Details and safety rules: **[docs/agents.md](docs/agents.md)**.

## Security

- **Sign-in:** OIDC device flow against `auth.servas.ai`. Each person and each agent host signs in with its own identity;
  sessions and profiles belong to that identity. API keys are deprecated.
- **Session URLs are secrets.** `cdp_url`, `cdp_ws_url` and `view_url` contain a session access token (`token=…`).
  Anyone holding them controls the browser until the session ends. Never paste them into tickets, chats or logs.
- **Isolation:** every session is a separate browser; tenant traffic only leaves through that tenant's exit nodes.
- **Tunnels are pinned:** `bcli tunnel` verifies the remote endpoint's key fingerprint from the authenticated API response.
- **Signed updates:** `bcli update` refuses any build whose checksum list is not signed by the servas.ai release key.
- **Secrets stay out of the agent:** vault entries are filled into the page by the bundled browser extension; the CLI never prints stored passwords.

Read **[docs/security.md](docs/security.md)** for the threat model and how to report a vulnerability.

## FAQ

<details>
<summary><strong>Do I need a VPN or Tailscale?</strong></summary>

No. `api.baas.servas.ai`, `edge.baas.servas.ai`, `console.baas.servas.ai` and `auth.servas.ai` are public HTTPS endpoints.
</details>

<details>
<summary><strong>Which automation libraries work?</strong></summary>

Anything that speaks CDP: Playwright (`chromium.connectOverCDP`), Puppeteer (`puppeteer.connect`), chromedp, raw CDP
over WebSocket. Do not let your library download or launch its own browser — you attach to ours.
</details>

<details>
<summary><strong>Is the browser headless?</strong></summary>

No. Sessions are headed browsers on a virtual display. That is why the live view works and why pages behave like they
do for real users.
</details>

<details>
<summary><strong>What happens when my script ends?</strong></summary>

`browser.close()` after `connectOverCDP` only disconnects. The session ends when you run `bcli session stop`, after
10 minutes without a CDP connection, 5 minutes after start if nobody ever connects, or when its TTL expires. In the
cloud the default TTL is your tenant's maximum session duration (for example 24 hours, see `bcli tenant`); local
daemon sessions default to 60 minutes. Stop what you start.
</details>

<details>
<summary><strong>How fast does a session start?</strong></summary>

From `bcli session create` to the first loaded page took a median of about 4.5 s in our own measurement
(30 runs, 12 Nov 2026: create 3.5 s, CDP connect 0.6 s, page load 0.4 s). Sessions from a persistent profile start cold
and take longer.
</details>

<details>
<summary><strong>Can I choose the public IP the sites see?</strong></summary>

Yes — that is what exit nodes are for. Your tenant has a default exit node; you can run your own with
[`servas-ai/baas-exit-docker`](https://github.com/servas-ai/baas-exit-docker) so sessions leave the internet from your
own network. `bcli exit-node list` shows the nodes available to you.
</details>

<details>
<summary><strong>Can I run browsers on my own machine instead?</strong></summary>

Yes. `bcli daemon start` runs the session API locally; register it with `bcli env add local --kind local` and use the
same commands. See [Local mode](docs/usage.md#local-mode).
</details>

<details>
<summary><strong>Where is the source code?</strong></summary>

This repository contains releases, documentation and agent skills only. bcli itself is proprietary software.
</details>

## Support

- Product, accounts and access: [servas.ai](https://servas.ai)
- Web console: [console.baas.servas.ai](https://console.baas.servas.ai)
- Bugs and questions about this documentation: [GitHub Issues](https://github.com/servas-ai/bcli-public/issues)
- Security issues: see [SECURITY.md](SECURITY.md) — please do not open a public issue.

## License

bcli is proprietary software by servas.ai — free to use with a servas.ai account. See [LICENSE](LICENSE).
