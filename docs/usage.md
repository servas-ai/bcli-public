# Usage guide

This guide assumes bcli is [installed](installation.md) and you are [signed in](configuration.md):

```bash
bcli env use cloud && bcli whoami
```

All examples use the current environment. Add `--env NAME` (or set `BCLI_ENV`) to target another one.

- [Sessions](#sessions)
- [Connecting with Playwright, Puppeteer and others](#connecting-with-playwright-puppeteer-and-others)
- [Live view and human hand-over](#live-view-and-human-hand-over)
- [Session lifetime and timers](#session-lifetime-and-timers)
- [Profiles: persistent logins](#profiles-persistent-logins)
- [Exit nodes: which IP the web sees](#exit-nodes-which-ip-the-web-sees)
- [Tunnels: your localhost inside the cloud browser](#tunnels-your-localhost-inside-the-cloud-browser)
- [GPU sessions](#gpu-sessions)
- [Audio](#audio)
- [Local mode](#local-mode)
- [Credential vault](#credential-vault)
- [Output and scripting](#output-and-scripting)
- [Exit codes](#exit-codes)
- [Command reference](#command-reference)

## Sessions

A session is one browser. Create it, connect to it, stop it.

```bash
bcli session create --wait
```

`session create` always prints one JSON object:

```json
{
  "id": "01a1ee5e-0000-7000-8000-000000000000",
  "state": "ready",
  "cdp_url": "https://edge.baas.servas.ai/s/01a1ee5e-…?token=…",
  "cdp_ws_url": "wss://edge.baas.servas.ai/s/01a1ee5e-…/cdp?token=…",
  "view_url": "https://edge.baas.servas.ai/s/01a1ee5e-…/view?token=…",
  "expires_at": "2026-11-18T13:30:00Z",
  "profile": "",
  "provision_path": "k8s"
}
```

| Field | Meaning |
|---|---|
| `id` | Session id, used by all other commands |
| `state` | `provisioning` → `ready` → `active` (a CDP client is connected) → `idle` → `terminated`; `failed` if it could not start |
| `cdp_url` | HTTPS CDP discovery URL — use this with Playwright `connectOverCDP` |
| `cdp_ws_url` | Raw CDP WebSocket — for libraries that want a `ws://`/`wss://` endpoint |
| `view_url` | Live view in your own browser |
| `expires_at` | When the TTL ends the session |
| `provision_path` | Where the session runs: the cloud runtime, or `local` for sessions of the local daemon |
| `failure_code`, `failure_reason` | Only on failed sessions, see [Exit codes](#exit-codes) |

> [!IMPORTANT]
> The three URLs contain a session access token (`token=…`). Treat them like passwords: keep them in memory or
> environment variables, never in logs, tickets or chat. `bcli session url <id>` prints `cdp_url` again when you need it.

### Create options

```bash
bcli session create --wait \
  --locale de-DE --timezone Europe/Berlin --viewport 1920x1080 \
  --ttl 90m --idle-timeout 30m
```

| Flag | Default | Meaning |
|---|---|---|
| `--wait` | `true` | Wait until the session is ready. `--wait=false` returns immediately in state `provisioning`. |
| `--ready-timeout` | `5m` | How long `--wait` waits; exit code 6 on timeout |
| `--profile NAME` | – | Start from a [persistent profile](#profiles-persistent-logins) |
| `--gpu` | `false` | Run on a [GPU target](#gpu-sessions) |
| `--locale` | `de-DE` | Browser locale, e.g. `en-US` |
| `--timezone` | `Europe/Berlin` | IANA time zone, e.g. `America/New_York` |
| `--viewport` | `1920x1080` | Window size `WxH` |
| `--seed` | random | Fingerprint seed — the same seed gives the same browser fingerprint |
| `--ttl` | `60m` | Maximum lifetime (capped by your tenant's maximum session duration) |
| `--idle-timeout` | `10m` | End the session this long after the last CDP client disconnected (max `1h`) |
| `--proxy` | – | Proxy URL, or `none`. On the servas.ai cloud your sessions always use your tenant's exit node; proxy overrides are rejected there. Mainly for local mode and self-hosted installations. |

Durations use Go syntax: `90s`, `45m`, `2h`.

### Inspect and stop

```bash
bcli session list --json      # your running sessions
bcli session get <id> --json  # one session, including state and failure details
bcli session url <id>         # print cdp_url again (same token, not a new one)
bcli session stop <id>        # end it now
```

You only see your own sessions; another account's session id answers `404`.

## Connecting with Playwright, Puppeteer and others

You attach to the browser in the cloud. Your automation library must **not** download or launch a browser of its own.

### Playwright (Node.js)

```bash
npm i playwright            # set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 to skip the browser download
```

```javascript
import { chromium } from 'playwright';

const browser = await chromium.connectOverCDP(process.env.CDP_URL, { timeout: 30_000 });
const context = browser.contexts()[0] ?? await browser.newContext();
const page = context.pages()[0] ?? await context.newPage();

await page.goto('https://example.com', { waitUntil: 'domcontentloaded', timeout: 60_000 });
console.log(await page.title());

await browser.close();   // disconnects only; the session keeps running until stop/idle/TTL
```

Use the **existing** context (`browser.contexts()[0]`): it carries the session's fingerprint, locale and — with a
profile — its cookies.

**Screenshots:** take them through CDP. This is faster and more reliable on a remote headed browser than
`page.screenshot()`, which can wait a long time for web fonts:

```javascript
const cdp = await context.newCDPSession(page);
const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
await fs.promises.writeFile('shot.png', Buffer.from(data, 'base64'));
```

### Playwright (Python)

```python
import os
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp(os.environ["CDP_URL"])
    context = browser.contexts[0] if browser.contexts else browser.new_context()
    page = context.pages[0] if context.pages else context.new_page()
    page.goto("https://example.com")
    print(page.title())
    browser.close()
```

### Puppeteer

```javascript
import puppeteer from 'puppeteer-core';

const browser = await puppeteer.connect({ browserWSEndpoint: process.env.CDP_WS_URL });
const [page] = await browser.pages();
await page.goto('https://example.com');
console.log(await page.title());
await browser.disconnect();
```

### Anything else

`cdp_ws_url` is a plain CDP WebSocket. chromedp, `chrome-remote-interface`, Selenium's CDP bridge and hand-written
clients work the same way.

Ready-to-run scripts: [`examples/`](../examples/).

## Live view and human hand-over

Open `view_url` in any desktop or mobile browser. You see the session's screen live and can use mouse and keyboard —
for example to solve a captcha, approve a second factor or just watch your agent. The view ends with the session.

The [web console](https://console.baas.servas.ai) shows all your sessions as live thumbnails after signing in.

On a desktop, `bcli assist --session <id>` opens a small native window with a region of the session's screen
(`--mode captcha --rect x,y,w,h`) or the whole screen (`--mode window`); the human's clicks and keys go into the
session. Exit code 12 means the human closed the window, 3 means no window can be shown on this machine.

## Session lifetime and timers

| Timer | Default | What happens |
|---|---|---|
| Ready without connect | 5 min | A session nobody ever connects to ends 5 minutes after it became ready |
| Idle | 10 min (`--idle-timeout`, max 1 h) | After the last CDP client disconnects, the session ends when the idle timer runs out |
| TTL | 60 min (`--ttl`) | Hard end, capped by your tenant's maximum session duration |

So: connect within 5 minutes, and **always** `bcli session stop <id>` when you are done — running sessions count
against your tenant's concurrency limit. `terminate_reason` tells you why a session ended (`client_stop`,
`idle_timeout`, `ttl_expired`).

## Profiles: persistent logins

A profile stores the browser's user data (cookies, local storage, logins) between sessions.

```bash
bcli profile create shop-1 --locale de-DE --timezone Europe/Berlin --viewport 1920x1080
bcli session create --profile shop-1 --wait
# … sign in once, inside the session …
bcli session stop <id>                 # the profile keeps the login
bcli session create --profile shop-1 --wait   # still signed in

bcli profile list
bcli profile delete shop-1
```

- A profile can be open in **one** session at a time. A second `session create --profile shop-1` fails with
  `profile_locked` (exit code 4) — reuse the running session instead.
- Profile sessions start cold, so they take longer than throwaway sessions.
- Profiles count against your tenant's profile limit (`bcli tenant`).
- Share a profile you own with another user (they can use it, not change or delete it):
  `bcli profile share shop-1 --user someone@example.com`; undo with `--revoke`.
- Pin a profile to a specific exit node: `bcli profile update shop-1 --egress-node NODE`.

## Exit nodes: which IP the web sees

Every cloud session reaches the internet through an exit node of your tenant. Websites see the public IP of that node.

```bash
bcli exit-node list          # names of the exit nodes available to you
bcli tenant                  # shows your tenant's default exit node
```

Run your own exit node — in your office, on a server, anywhere with Docker — with
**[servas-ai/baas-exit-docker](https://github.com/servas-ai/baas-exit-docker)**:

```bash
git clone https://github.com/servas-ai/baas-exit-docker.git
cd baas-exit-docker
./up.sh        # asks for a one-time exit key from the console (Tenant & exit keys)
```

Once it is online and set as your tenant's default exit, `bcli session create` uses it automatically. While a
tenant's exit node is down, new sessions fail instead of silently using another route.

## Tunnels: your localhost inside the cloud browser

Make a port on your machine reachable as `http://localhost:<port>` **inside** the remote browser — ideal for testing a
local dev server with a real cloud browser.

```bash
npm run dev                                         # e.g. your app on :3000
bcli tunnel start --session <id> --ports 3000       # keep this running; Ctrl-C closes the tunnel
# in the remote browser: http://localhost:3000
```

- Up to 16 ports, comma-separated (`--ports 3000,5173`), each ≥ 1024.
- Some ports are reserved and refused: `3128, 5432, 7000, 7070, 8080, 9100, 9222, 9223`.
- The tunnel ends with the session or with Ctrl-C.
- The tunnel endpoint's key is pinned to the fingerprint from the authenticated API response; there is no unpinned
  fallback.
- In local mode the command is a no-op: the browser already runs on your machine.

If a service hands you a ready-made tunnel (`ws_url` + token + fingerprint), connect without any bcli configuration:

```bash
bcli tunnel connect --ws-url "$WS_URL" --token-file token.txt --fingerprint "$FP" --ports 3000
# --token-file - reads the token from stdin
```

## GPU sessions

```bash
bcli session create --gpu --wait
```

GPU sessions render WebGL, canvas-heavy pages and video on a real GPU — in our measurements up to 24× more frames per
second on heavy WebGL content. GPU capacity is limited per tenant (`bcli tenant`); when no GPU is free, the command
fails with `no_gpu` (exit code 5). Retry later or run without `--gpu`.

## Audio

Each session has its own virtual speaker and microphone. `bcli audio attach` streams them as raw PCM
(s16le, 48 kHz, 20 ms frames) — for voice agents, call bots or recordings.

```bash
# record what the page plays (speaker only), stereo
bcli audio attach --session <id> --dir out --channels 2 > speaker.pcm

# full duplex over stdin/stdout (default: both directions, mono)
your-voice-agent | bcli audio attach --session <id> | your-voice-agent-input

# or over a unix socket / two named pipes
bcli audio attach --session <id> --socket /tmp/sess.sock
bcli audio attach --session <id> --fifo ./audio      # ./audio/speaker.pcm and ./audio/mic.pcm
```

`--dir` is `both`, `out` (speaker only) or `in` (microphone only); `--channels` is `1` or `2`.

## Local mode

The local daemon runs the same session API on your own machine and launches the browser locally. Commands, JSON and
exit codes are the same as in the cloud.

```bash
bcli daemon start                     # or: bcli daemon run (foreground)
bcli daemon status
bcli env add local --kind local       # once
bcli --env local session create --wait
bcli --env local session stop <id>
bcli daemon stop
```

**Browser.** Local sessions need a Chromium-based browser executable:

- **Windows:** Microsoft Edge or Google Chrome in their standard install locations are used automatically.
- **Linux and macOS:** set `browser_path` in [`config.yaml`](configuration.md#configyaml-reference) or the
  `BAAS_BROWSER_PATH` environment variable to the browser executable, e.g.
  `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`.

Local sessions open a real browser window on your desktop. Persistent profiles work locally too; tunnels are not
needed. Daemon state lives in `~/.bcli/` (`BCLI_HOME`).

## Credential vault

bcli has a local, encrypted credential vault. A browser extension that bcli installs into its local sessions fills
usernames, passwords and TOTP codes **into the page** — the agent references an entry by id and never sees the secret.

```bash
# unlock (the first unlock creates the vault); the passphrase comes from BCLI_VAULT_PASSPHRASE
read -rs BCLI_VAULT_PASSPHRASE && export BCLI_VAULT_PASSPHRASE
bcli vault unlock
bcli vault status

# add a credential – secrets are passed by environment variable name, never as arguments
read -rs SHOP_PW && export SHOP_PW
bcli vault create --name shop --url https://shop.example.com/login --user me@example.com --password-env SHOP_PW
# optional 2FA: --totp-env VAR where VAR holds an otpauth:// URI

bcli vault list --url https://shop.example.com/login    # entries for this page (no secrets)
bcli vault get <id>                                     # metadata only
bcli vault tabs                                         # tab ids and URLs of the local session
bcli vault autofill <id> --tab active --submit          # fill (and submit) the login form
bcli vault totp <id>                                    # current TOTP code
```

The vault only fills a credential into a page whose origin matches the stored URL.

**Cloud sessions.** To fill credentials from your local vault into a cloud session, keep an attach running, then use
the same `vault` commands:

```bash
bcli vault attach --session <id>     # keep running in a second terminal
bcli vault tabs
bcli vault autofill <id> --tab active --submit
```

**Passkeys.** `bcli vault passkey list` lists stored passkeys; `bcli vault passkey allow-create --rp example.com`
allows one passkey registration for a relying party within a short window (`--ttl`, default 5 minutes).

Vault exit codes: `7` vault locked or missing · `8` no vault attached to the session · `9` page origin does not match the
credential · `10` no login form found or fill incomplete.

## Output and scripting

- `session create`, `session list` and `session get` always print JSON. Add `--json` to other commands
  (`env list`, `whoami`, `tenant`, `exit-node list`, …) for JSON output.
- Errors go to stderr, usually as `code=<error_code>: <message>`; stdout stays clean for parsing.
- Every failure has a stable [exit code](#exit-codes).

```bash
SID=$(bcli session create --wait | jq -r .id)
export CDP_URL=$(bcli session url "$SID")
trap 'bcli session stop "$SID" >/dev/null' EXIT
node my-script.mjs
```

PowerShell:

```powershell
$s = bcli session create --wait | ConvertFrom-Json
$env:CDP_URL = $s.cdp_url
try { node my-script.mjs } finally { bcli session stop $s.id | Out-Null }
```

## Exit codes

| Code | Meaning | What to do |
|---:|---|---|
| 0 | Success | |
| 1 | Generic error; for a failed session see `failure_reason` | Read the message |
| 2 | `unauthorized` | Sign in again; check that your account has access |
| 3 | `quota_exceeded` | Stop sessions or profiles you no longer need (`bcli tenant`) |
| 4 | `profile_locked` — the profile is open in another session | Reuse or stop that session |
| 5 | No capacity (`capacity_unavailable`, `no_capacity`, `no_gpu`) or the local daemon is not running (`daemon_unavailable`) | Retry later, drop `--gpu`, or `bcli daemon start` |
| 6 | `--wait` timed out | Check `bcli session get <id>`; raise `--ready-timeout` |
| 7 | Vault locked or missing | `bcli vault unlock` |
| 8 | No vault attached to the cloud session | `bcli vault attach --session <id>` |
| 9 | Page origin does not match the credential | Check the URL of the entry |
| 10 | Autofill incomplete or no login form found | Check the tab and page |
| 11 | `profile_host_offline` — the host that stores the profile is offline | Retry later; the profile itself is fine |
| 12 | Sign-in denied (`login_denied`); for `assist`: the human closed the window | |
| 13 | The device code expired (`device_code_expired`) | Run `bcli login` again and finish within the time shown |
| 15 | Not signed in (`auth_required`) | `bcli login` |

Failed sessions carry a stable `failure_code`: `no_capacity`, `no_gpu`, `profile_host_offline`, `ready_timeout`,
`provision_error`, `gpu_profile_home`.

## Command reference

Run `bcli <command> --help` for the authoritative list of flags of your installed version.

```text
bcli version
bcli update [--check] [--force]

bcli env add NAME --kind cloud|local [--endpoint URL] [--socket PATH]
bcli env list [--offline] | current | use NAME | remove NAME
bcli login | logout | whoami
bcli tenant [--json]

bcli session create [--wait] [--ready-timeout D] [--profile NAME] [--gpu] [--locale L] [--timezone TZ]
                    [--viewport WxH] [--seed S] [--ttl D] [--idle-timeout D] [--proxy URL|none]
bcli session list | get ID | url ID | stop ID

bcli profile create NAME [--locale L] [--timezone TZ] [--viewport WxH]
bcli profile list | delete NAME
bcli profile update NAME --egress-node NODE
bcli profile share NAME --user USER [--revoke]

bcli exit-node list
bcli tunnel start --session ID --ports P1,P2
bcli tunnel connect --ws-url URL --token-file FILE|- --fingerprint FP --ports P1,P2
bcli audio attach --session ID [--dir both|out|in] [--channels 1|2] [--socket PATH | --fifo DIR]
bcli assist --session ID [--mode captcha|window] [--rect x,y,w,h] [--heading TEXT] [--hint TEXT]

bcli daemon start [--detach] | run | status | stop
bcli vault status | unlock | list [--url URL] | get ID | create … | totp ID | tabs
bcli vault autofill ID [--tab ID|active] [--url URL] [--fields a,b] [--submit]
bcli vault attach --session ID
bcli vault passkey list | allow-create --rp RP [--ttl D]

Global flags: --env NAME, --json
```
