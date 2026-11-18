---
name: bcli
description: Use real, headed cloud browsers from servas.ai Browser as a Service via agent-web and the bcli CLI. Start a browser session, navigate and act on pages with agent-browser snapshots and element refs (or Playwright/Puppeteer over CDP), let a human solve captchas or take over, tunnel localhost into the browser, use persistent login profiles, and always stop the session afterwards. Use when the user wants a remote/cloud browser, a real (non-headless) browser for an agent, web automation, scraping or end-to-end tests, or mentions bcli, agent-web, BaaS, Browser as a Service or servas.ai.
---

# bcli + agent-web — cloud browsers for agents

The browser runs in the servas.ai cloud. You drive it from here. Never launch a local Chrome/Chromium/Playwright browser
as a substitute.

**Primary path:** `agent-web` (session + [agent-browser](https://www.npmjs.com/package/agent-browser) over CDP).
**Fallback:** bare `bcli` + Playwright/Puppeteer `connectOverCDP` (section "Fallback" below).

## 0. Preflight (once per machine)

```bash
bcli version && bcli whoami --json        # expect "auth": "oidc" and the user's own owner
agent-web version && command -v agent-browser  # if missing: use the fallback, or ask the user to install
```

Install docs: https://github.com/servas-ai/bcli-public/blob/main/docs/installation.md

If `whoami` fails with exit code 15 (`auth_required`) or no environment exists:

```bash
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai   # only if `bcli env list` lacks it
bcli env use cloud
bcli login        # prints a URL + code on stderr; the HUMAN completes the sign-in
```

Run `bcli login` in the background or ask the user to run it. Never complete the sign-in yourself, never reuse someone
else's login, never configure API keys.

## 1. Start

```bash
SID=$(agent-web start) || exit 1        # stdout = session id only; hints on stderr. Non-zero exit = no session
# variants: agent-web start shop-1 (persistent profile, must exist: bcli profile list)
#           agent-web start --gpu  (WebGL/video-heavy pages)
#           agent-web start --ttl 2h --locale en-US --timezone Europe/London   (extra flags go to bcli)
```

Never use `$SID` if `start` failed: report the exit code (see table) instead.

Windows PowerShell: `$sid = agent-web start; if ($LASTEXITCODE -ne 0) { throw "start failed" }` (same subcommands;
quote refs: `'@e3'`).

## 2. Drive with snapshots and refs

```bash
agent-web ab "$SID" open https://example.com
agent-web ab "$SID" snapshot -i            # interactive elements with refs @e1, @e2, …
agent-web ab "$SID" click @e3
agent-web ab "$SID" fill @e5 "query"
agent-web ab "$SID" press Enter
agent-web ab "$SID" get text body          # read content
agent-web ab "$SID" screenshot shot.png    # when layout matters
```

Take a fresh `snapshot -i` after every navigation or larger page change; refs are only valid for the snapshot they
came from.

## 3. Human in the loop

Captcha, second factor, consent dialog or a decision only a person can make:

```bash
agent-web captcha "$SID"                   # or: agent-web assist "$SID" "Enter the SMS code"
```

It opens a small window on the user's desktop and **waits for the human** — run it in the background / as a monitor,
then re-check the page with `snapshot -i`. If it exits with 3 (no window possible here), run `agent-web view "$SID"`
to open the live view in the user's browser, or `agent-web view "$SID" --print` and give that URL **only** to the user
in your direct reply (it contains an access token; never write it to files, commits, tickets or logs).

## 4. Always stop

```bash
agent-web stop "$SID"
```

Stop every session you started, also after errors. Do not stop sessions you did not start. Running sessions count
against the user's limits (`bcli tenant`).

## Localhost inside the cloud browser

```bash
agent-web tunnel "$SID" 3000               # blocks: run in the background; stop the process when done
agent-web ab "$SID" open http://localhost:3000
```

Ports ≥ 1024, max 16, comma-separated.

## Profiles

One profile can be open in only one session. Exit code 4 (`profile_locked`): find the running session with
`agent-web status` (or `bcli session list --json`) and reuse it instead of starting another. Never create or delete
profiles unless the user asks (`bcli profile create NAME`).

## Fallback: bcli + CDP (no agent-web / own Playwright code)

```bash
SID=""
trap 'if [ -n "$SID" ]; then bcli session stop "$SID" >/dev/null; fi' EXIT
SESSION_JSON=$(bcli session create --wait) || exit 1   # one JSON object; never use an id from a failed create
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
```

```javascript
import { chromium } from 'playwright';            // install with PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
const browser = await chromium.connectOverCDP(process.env.CDP_URL, { timeout: 30_000 });
const context = browser.contexts()[0] ?? await browser.newContext();
const page = context.pages()[0] ?? await context.newPage();
await page.goto('https://example.com', { waitUntil: 'domcontentloaded' });
const cdp = await context.newCDPSession(page);    // screenshots via CDP, not page.screenshot()
const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
await browser.close();                            // disconnects only
```

Then `bcli session stop "$SID"`. Connect within 5 minutes of creating the session or it ends on its own. Use
`cdp_ws_url` for Puppeteer `browserWSEndpoint` or raw CDP. Session fields you may use: `id`, `state`, `cdp_url`,
`cdp_ws_url`, `view_url`, `expires_at`, `profile`, `failure_code`, `failure_reason`.

## Exit codes (agent-web passes bcli's through)

| Code | Meaning | Action |
|---:|---|---|
| 0 | ok | |
| 1 | generic / session failed | read stderr and `failure_reason` |
| 2 | unauthorized | ask the user to check access |
| 3 | quota exceeded (for `captcha`/`assist`: no window possible) | stop own unused sessions / use `view` |
| 4 | profile locked | reuse the running session of that profile |
| 5 | no capacity / no GPU | retry later or without `--gpu` |
| 6 | `--wait` timeout | `bcli session get "$SID"`, then stop it |
| 11 | profile host offline | retry later; do not modify the profile |
| 15 | not signed in | ask the user to run `bcli login` |
| 64 / 69 | agent-web usage error / missing tool | fix the call / use the fallback |

## Hard rules

- Session URLs (`cdp_url`, `cdp_ws_url`, `view_url`, anything with `token=`) are secrets: never print them in full in
  logs, commit them, or store them in files.
- Never call `agent-browser` directly against a session — always through `agent-web ab`, which forces CDP attach mode.
- Never launch a local browser as a substitute; report the exit code instead.
- Never paste device codes, login tokens, passwords or API keys anywhere.
- One task → one session. Stop it when done.
- Only use commands and flags shown by `agent-web help` and `bcli --help`.
