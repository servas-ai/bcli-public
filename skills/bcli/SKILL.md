---
name: bcli
description: Use real, headed cloud browsers from servas.ai Browser as a Service via the bcli CLI. Create a browser session, connect Playwright/Puppeteer over CDP, let a human watch or take over via the live view, tunnel localhost into the browser, use persistent login profiles, and always stop the session afterwards. Use when the user wants a remote/cloud browser, a real (non-headless) browser for an agent, web automation or end-to-end tests against a CDP endpoint, or mentions bcli, BaaS, Browser as a Service or servas.ai.
---

# bcli — cloud browsers for agents

bcli creates browser sessions in the servas.ai cloud and returns CDP endpoints. You drive the browser with
Playwright or Puppeteer **from the user's machine**; the browser itself runs remotely. Never launch a local browser
for this.

## 0. Preflight (once per machine)

```bash
bcli version                 # installed? If not: https://github.com/servas-ai/bcli-public#install
bcli whoami --json           # expect "auth": "oidc" and the user's own owner
```

If no environment exists or `whoami` fails with exit code 15 (`auth_required`):

```bash
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai   # only if `bcli env list` lacks it
bcli env use cloud
bcli login                   # prints a URL + code on stderr; the HUMAN completes it
```

`bcli login` waits for a person to open the URL and sign in. Run it in the background or ask the user to run it;
never try to complete the sign-in yourself and never reuse someone else's login. Do not configure API keys.

## 1. Create a session

```bash
SESSION_JSON=$(bcli session create --wait)        # always prints one JSON object
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
```

Useful flags: `--profile NAME` (persistent logins), `--gpu`, `--locale en-US`, `--timezone Europe/London`,
`--viewport 1440x900`, `--ttl 90m`, `--idle-timeout 30m`. Check `bcli session create --help` before using any other
flag; do not invent flags.

Fields you may use: `id`, `state`, `cdp_url`, `cdp_ws_url`, `view_url`, `expires_at`, `profile`, `failure_code`,
`failure_reason`.

## 2. Connect within 5 minutes

A session that nobody connects to ends 5 minutes after it became ready.

```javascript
import { chromium } from 'playwright';
const browser = await chromium.connectOverCDP(process.env.CDP_URL, { timeout: 30_000 });
const context = browser.contexts()[0] ?? await browser.newContext();
const page = context.pages()[0] ?? await context.newPage();
await page.goto('https://example.com', { waitUntil: 'domcontentloaded' });
// Screenshots: prefer CDP over page.screenshot() on remote headed browsers
const cdp = await context.newCDPSession(page);
const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
await browser.close();   // disconnects only; the session keeps running
```

- Use `cdp_url` (HTTPS) with Playwright; use `cdp_ws_url` for Puppeteer `browserWSEndpoint` or raw CDP.
- Install Playwright with `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`; you attach to the remote browser.
- Reuse `browser.contexts()[0]`: it carries the session's fingerprint and profile cookies.

## 3. Human in the loop

When a page needs a human (captcha, second factor, consent, a decision), tell the user to open the session's live view.
Give them the `view_url` **only in your direct reply to them**, never in files, commits, tickets or logs. Wait until
they confirm, then continue.

## 4. Always stop

```bash
bcli session stop "$SID"
```

Stop every session you created, also after errors (use `trap … EXIT` or `try/finally`). Do not stop sessions you did
not create. Running sessions count against the user's limits (`bcli tenant`).

## Profiles (persistent logins)

```bash
bcli profile list
bcli session create --profile shop-1 --wait
```

One profile can be open in only one session. Exit code 4 (`profile_locked`): find the running session with
`bcli session list --json` and reuse it instead of creating another one. Never delete a profile unless the user asks.

## Localhost inside the remote browser

```bash
bcli tunnel start --session "$SID" --ports 3000    # blocks; run in the background, Ctrl-C/kill to close
# the remote browser can now open http://localhost:3000
```

Ports ≥ 1024, max 16. Stop the tunnel process when done.

## Exit codes

| Code | Meaning | Action |
|---:|---|---|
| 0 | ok | |
| 1 | generic / session failed | read stderr and `failure_reason` |
| 2 | unauthorized | ask the user to check access |
| 3 | quota exceeded | stop own unused sessions, then retry once |
| 4 | profile locked | reuse the running session of that profile |
| 5 | no capacity / no GPU | retry later or without `--gpu` |
| 6 | `--wait` timeout | `bcli session get "$SID"`, then stop it |
| 11 | profile host offline | retry later; do not modify the profile |
| 15 | not signed in | ask the user to run `bcli login` |

## Hard rules

- Treat `cdp_url`, `cdp_ws_url`, `view_url` and anything with `token=` as secrets: never print them in full in logs,
  commit them, or store them in files. Redact as `token=REDACTED`.
- Never launch a local Chrome/Chromium/Playwright browser as a substitute for the session.
- Never paste device codes, login tokens or API keys anywhere.
- One task → one session. Stop it when done.
- If a command or flag is not in `bcli --help`, do not use it.
