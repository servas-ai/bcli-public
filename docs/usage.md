# Usage guide

This guide assumes bcli is [installed](installation.md) and you are [signed in](configuration.md):

```bash
bcli env use cloud
bcli whoami
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
  "cdp_url": "https://edge.baas.servas.ai/s/01a1ee5e-…?token=…",
  "cdp_ws_url": "wss://edge.baas.servas.ai/s/01a1ee5e-…/cdp?token=…",
  "chrome_pid": 0,
  "expires_at": "2026-11-18T13:30:00Z",
  "id": "01a1ee5e-0000-7000-8000-000000000000",
  "profile": null,
  "provision_path": "pve",
  "state": "ready",
  "target": "pve",
  "terminate_reason": null,
  "view_url": "https://edge.baas.servas.ai/s/01a1ee5e-…/view?token=…"
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
| `profile` | The [profile](#profiles-persistent-logins) the session started from, `null` without one |
| `provision_path` | Where the session runs: the cloud runtime (for example `pve` or `k8s`), or `local` for sessions of the local daemon |
| `target` | The runtime target the installation picked for the session (cloud only) |
| `chrome_pid` | Process id of the browser for local sessions; `0` in the cloud |
| `terminate_reason` | Why the session ended (`client_stop`, `ttl`, `idle`, …); `null` while it runs |
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
| `--ttl` | cloud: tenant maximum · local: `60m` | Maximum lifetime. In the cloud it defaults to — and is capped by — your tenant's maximum session duration (e.g. 24 h, see `bcli tenant`). |
| `--idle-timeout` | `10m` | End the session this long after the last CDP client disconnected (max `1h`) |
| `--proxy` | – | Proxy URL, or `none`. On the servas.ai cloud your sessions always use your tenant's exit node; proxy overrides are rejected there. Mainly for local mode and self-hosted installations. |

Durations use Go syntax: `90s`, `45m`, `2h`.

### Inspect and stop

```bash
bcli session list --json      # your running sessions (JSON with the URLs, including their tokens)
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

On a Linux or macOS desktop (not on Windows), `bcli assist --session <id>` opens a small native window with a region of the session's screen
(`--mode captcha --rect x,y,w,h`) or the whole screen (`--mode window`); the human's clicks and keys go into the
session. Exit code 12 means the human closed the window, 3 means no window can be shown on this machine.

## Session lifetime and timers

| Timer | Default | What happens |
|---|---|---|
| Ready without connect | 5 min | A session nobody ever connects to ends 5 minutes after it became ready |
| Idle | 10 min (`--idle-timeout`, max 1 h) | After the last CDP client disconnects, the session ends when the idle timer runs out |
| TTL | cloud: your tenant's maximum session duration (e.g. 24 h) · local daemon: 60 min (`--ttl`) | Hard end; in the cloud `--ttl` can only shorten it |

So: connect within 5 minutes, and **always** `bcli session stop <id>` when you are done — running sessions count
against your tenant's concurrency limit. `terminate_reason` tells you why a session ended (`client_stop`,
`idle_timeout`, `ttl_expired`, or `provision_failed` for a session that never became ready — see its `failure_code`).

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

You run your tenant's exit node yourself — in your office, on a server, anywhere with Docker. Step by step (image,
one-time key, `docker run` / Compose, checks, what it can see, stop and rotate): **[Start an exit node](exit-node.md)**.

Once it is online and set as your tenant's default exit, `bcli session create` uses it automatically. While a
tenant's exit node is down, new sessions fail with `code=exit_node_unavailable` (exit code 1) instead of silently
using another route; see [Troubleshooting](exit-node.md#troubleshooting).

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

> [!NOTE]
> `bcli audio` is available on Linux and macOS, not on Windows.

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
bcli --env local session create --wait
bcli --env local session stop <id>
bcli daemon stop
```

`--env local` works without any configuration. To make local the default, `bcli env add local --kind local` and
`bcli env use local`. If the daemon is not running, local commands fail with `daemon_unavailable` (exit code 5).

**Browser.** Local sessions need a Chromium-based browser. bcli picks one itself, in this order:
`BAAS_BROWSER_PATH`, `browser_path` in [`config.yaml`](configuration.md#configyaml-reference), CloakBrowser
(`~/.cloakbrowser`), then an installed browser:

- **Windows:** Microsoft Edge, then Google Chrome, in their standard install locations.
- **Linux:** Chromium (`/usr/bin/chromium`, `chromium-browser`), Google Chrome (`google-chrome`,
  `google-chrome-stable`), Microsoft Edge (`microsoft-edge`, `microsoft-edge-stable`).
- **macOS** (preview, not yet acceptance-tested): Chromium, Google Chrome, Microsoft Edge in `/Applications` or
  `~/Applications`. On macOS the browser runs headless. `bcli daemon start` installs the daemon's LaunchAgent itself
  (run it once in Terminal of your desktop login, not over SSH; over SSH use `bcli daemon run`).

`bcli daemon status` shows the browser it uses, or warns when none is found. Google Chrome 137 and newer ignore the
`--load-extension` switch; bcli loads its credential extension into Chrome over a private DevTools pipe instead, so
Chrome works like the others. Brave is not supported: it looks for bcli's native-messaging registration in Google
Chrome's folder, so the vault cannot reach it.

On Linux and Windows, local sessions open a real browser window on your desktop. Persistent profiles work locally
too; tunnels are not needed. Daemon state lives in `~/.bcli/` (`BCLI_HOME`); the daemon log is `~/.bcli/daemon.log`.

### Windows notes

- **Same logon session, not elevated.** The daemon and the vault talk over named pipes that belong to your Windows
  logon session. Run `bcli daemon start`, `bcli vault unlock` and your agent from normal, **non-elevated** terminals
  in the same desktop session. A "Run as administrator" shell, a different user, or an SSH login into the machine
  cannot reach them (bcli refuses elevated tokens on purpose). In such a shell `bcli daemon status` reports the daemon
  as not running even though it runs in your desktop session — check from a normal terminal on that desktop.
- **Start bcli from a normal terminal, not from a scheduled task.** If bcli runs inside a Windows job that keeps its
  child processes in the job (for example a Task Scheduler task), the browser extension refuses to fill credentials.
  `bcli daemon start` warns about it, and the daemon log shows `reason=pipe_owner sub=job_contained`.
- **Start at logon.** `bcli daemon autostart enable` starts the daemon at every logon (`--bwbridge` also starts the
  Bitwarden bridge); `bcli daemon autostart disable` turns it off. The vault still needs one `bcli vault unlock` after
  each logon, by design. Details: [installation](installation.md#windows).
- **"Disable developer mode extensions" in Edge.** Every local session loads bcli's credential extension unpacked, so
  Microsoft Edge shows a "Disable developer mode extensions" pop-up each time a session window opens. This is
  expected. Close it with the **×** (do **not** choose "Turn off", or the vault cannot fill logins in that session).
  Google Chrome does not show it.
- **Moving `bcli.exe`** is fine; it registers itself for the extension again on its next start.
- **Not available on Windows:** `bcli assist` and `bcli audio`. Use the live view (`view_url`) to hand a session to a
  human.

## Credential vault

bcli has a local, encrypted credential vault. A browser extension built into bcli fills usernames, passwords and TOTP
codes **into the page** — the agent references an entry by id and never sees the secret.

`bcli vault unlock` asks for your passphrase and then keeps the vault unlocked **in the background**. It locks again
by itself after 15 minutes, and when you run `bcli vault lock`, log out or reboot (on Windows also after
`bcli update`). There is nothing else to keep running. Vault commands that need an unlocked vault exit with code 7
and tell you which command to run.

### Local sessions

```bash
bcli vault unlock      # prompts "Vault passphrase:" (no echo); the first unlock creates the vault
bcli vault status      # absent | locked | unlocked
```

The passphrase can also come from a pipe (first line of stdin) or from `BCLI_VAULT_PASSPHRASE`, e.g. in automation.
Never put it on the command line.

**Store credentials.** Secrets are passed by environment variable **name**, never as arguments:

```bash
# bash / zsh
read -rsp "Password: " SHOP_PW && echo && export SHOP_PW
bcli vault create --name shop --url https://shop.example.com/login --user me@example.com --password-env SHOP_PW
unset SHOP_PW
# optional 2FA: --totp-env VAR, where VAR holds an otpauth:// URI
```

```powershell
# PowerShell
$pw = Read-Host "Password" -AsSecureString
$env:SHOP_PW = [System.Net.NetworkCredential]::new("", $pw).Password
bcli vault create --name shop --url https://shop.example.com/login --user me@example.com --password-env SHOP_PW
Remove-Item Env:SHOP_PW
```

**Fill** — the agent only needs ids:

```bash
bcli vault list --url https://shop.example.com/login    # entries for this page (no secrets)
bcli vault get <id>                                     # metadata only
bcli vault tabs                                         # tab ids and URLs of the local session
bcli vault autofill <id> --tab active --submit          # fill (and submit) the login form
bcli vault totp <id>                                    # current TOTP code
bcli vault lock                                         # lock again when you are done
```

The vault only fills a credential into a page whose origin matches the stored URL.

### Cloud sessions

To use your local vault in a **cloud** session, bind it to that session. bcli keeps the binding in the background and
ends it quietly when the session ends:

```bash
bcli vault unlock --session <session-id>          # asks for the passphrase; prints "attached"
bcli vault tabs --session <session-id>            # tabs of the cloud browser
bcli vault list --session <session-id> --url https://shop.example.com/login
bcli vault autofill <entry-id> --session <session-id> --tab active --submit
```

`list`, `get`, `create`, `totp`, `tabs`, `autofill` and `passkey list|allow-create` all accept `--session`. Credentials
travel only through the session's pinned tunnel and are filled by the extension inside the cloud browser.

**Passkeys.** `bcli vault passkey list` lists stored passkeys; `bcli vault passkey allow-create --rp example.com`
allows one passkey registration for a relying party within a short window (`--ttl`, default 5 minutes).

**Quiet by default.** Vault commands print only their result. For diagnostics set `BAAS_LOG_LEVEL=debug` (or `info`).

Vault exit codes: `7` vault locked, missing or wrong passphrase (the message names the command to run) · `8` no vault
bound to the session · `9` page origin does not match the credential · `10` no login form found or fill incomplete.

## Output and scripting

- `session create`, `session list` and `session get` always print JSON. Add `--json` to other commands
  (`env list`, `whoami`, `tenant`, `exit-node list`, …) for JSON output. The session commands print the session URLs
  with their access tokens: do not paste that output into tickets or chats unredacted.
- Errors go to stderr, usually as `code=<error_code>: <message>`; stdout stays clean for parsing.
- Every failure has a stable [exit code](#exit-codes).

```bash
set -euo pipefail
SID=""
trap 'if [ -n "$SID" ]; then bcli session stop "$SID" >/dev/null; fi' EXIT   # only stop what was created
SESSION_JSON=$(bcli session create --wait) || exit 1                # check the exit code before using the id
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
node my-script.mjs
```

PowerShell:

```powershell
$json = bcli session create --wait
if ($LASTEXITCODE -ne 0) { throw "session create failed (exit $LASTEXITCODE)" }
$s = $json | ConvertFrom-Json
$env:CDP_URL = $s.cdp_url
try { node my-script.mjs } finally { bcli session stop $s.id | Out-Null }
```

## Exit codes

| Code | Meaning | What to do |
|---:|---|---|
| 0 | Success | |
| 1 | Generic error; for a failed session see `failure_reason`. Also `exit_node_unavailable` on create: your tenant's exit node is not running | Read the message; for `exit_node_unavailable` start your exit node, see [Start an exit node](exit-node.md#troubleshooting) |
| 2 | `unauthorized` | Sign in again; check that your account has access |
| 3 | `quota_exceeded` | Stop sessions or profiles you no longer need (`bcli tenant`) |
| 4 | `profile_locked` — the profile is open in another session | Reuse or stop that session |
| 5 | No capacity (`capacity_unavailable`, `no_capacity`, `no_gpu`) or the local daemon is not running (`daemon_unavailable`) | Retry later, drop `--gpu`, or `bcli daemon start` |
| 6 | `--wait` timed out | Check `bcli session get <id>`; raise `--ready-timeout` |
| 7 | Vault locked, missing or wrong passphrase | `bcli vault unlock` (cloud: `bcli vault unlock --session <id>`) |
| 8 | No vault bound to the cloud session | `bcli vault unlock --session <id>` |
| 9 | Page origin does not match the credential | Check the URL of the entry |
| 10 | Autofill incomplete or no login form found | Check the tab and page |
| 11 | `profile_host_offline` — the host that stores the profile is offline | Retry later; the profile itself is fine |
| 12 | Sign-in denied (`login_denied`); for `assist`: the human closed the window | |
| 13 | The device code expired (`device_code_expired`) | Run `bcli login` again and finish within the time shown |
| 15 | Not signed in (`auth_required`) | `bcli login` |

Failed sessions carry `terminate_reason: provision_failed` and a stable `failure_code`: `no_capacity`, `no_gpu`,
`profile_host_offline`, `ready_timeout`, `provision_error`, `gpu_profile_home`. Errors that the API rejects before a
session exists — such as `exit_node_unavailable`, `quota_exceeded` or `profile_locked` — are not failure codes: they
are printed as `code=…` on stderr and set the exit code, and no session id is returned.

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
bcli audio attach --session ID [--dir both|out|in] [--channels 1|2] [--socket PATH | --fifo DIR]   (not on Windows)
bcli assist --session ID [--mode captcha|window] [--rect x,y,w,h] [--heading TEXT] [--hint TEXT]  (not on Windows)

bcli daemon start [--detach] | run | status | stop
bcli daemon autostart enable [--bwbridge] | disable | status                           (Windows)
bcli vault unlock [--session ID] | lock | status
bcli vault list [--url URL] | get ID | create … | totp ID | tabs                      [--session ID]
bcli vault autofill ID [--tab ID|active] [--url URL] [--fields a,b] [--submit]       [--session ID]
bcli vault passkey list | allow-create --rp RP [--ttl D]                             [--session ID]
bcli vault attach [--session ID]          (foreground variant of unlock; rarely needed)

bcli bwbridge start [--restart] | stop | status | remove | apparmor   (remove: Linux/macOS, apparmor: Linux)
bcli vault bw setup [--add] | status | autofill [--session ID] [--wait] [--submit] | lock | grants | revoke ID
bcli uninstall [--purge]

Global flags: --env NAME, --json
```
