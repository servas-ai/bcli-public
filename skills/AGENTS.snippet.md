<!--
  Paste the section below into your repository's AGENTS.md (Codex, Cursor, Aider, Gemini CLI, Jules and other agents
  that read AGENTS.md). Claude Code users can install skills/bcli/ instead.
-->

## Browser automation with agent-web / bcli (servas.ai Browser as a Service)

Use `agent-web` for every browser this project needs (web tasks, scraping, checking pages, e2e smoke tests). The
browser runs in the servas.ai cloud; you drive it over CDP. Never start a local Chrome/Chromium/Playwright browser
instead, and never call `agent-browser` directly against a session.

**Preflight:** `bcli whoami --json` must show `"auth": "oidc"`. On exit code 15 ask the human to run `bcli login`
(device-code sign-in; the human completes it). Do not configure API keys.

**Loop (agent-web, primary):**

```bash
SID=$(agent-web start)                       # stdout = session id only; add PROFILE, --gpu or bcli flags as needed
agent-web ab "$SID" open https://example.com
agent-web ab "$SID" snapshot -i              # refs @e1, @e2, … ; re-snapshot after every navigation
agent-web ab "$SID" click @e3                # fill @e2 "text" · press Enter · get text body · screenshot x.png
agent-web stop "$SID"                        # always, also after errors
```

- Human needed (captcha, 2FA, consent): `agent-web captcha "$SID"` / `agent-web assist "$SID" "what to do"` — waits for
  the human, run it in the background. Exit 3 = no window here → `agent-web view "$SID"`.
- Local dev server in the cloud browser: `agent-web tunnel "$SID" 3000` (blocks; background it), then open
  `http://localhost:3000`.
- Persistent logins: `agent-web start PROFILE`. Exit 4 = profile already open → reuse that session (`agent-web status`).

**Fallback (own Playwright/Puppeteer code):**

```bash
SESSION_JSON=$(bcli session create --wait)                 # JSON: id, state, cdp_url, cdp_ws_url, view_url
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
trap 'bcli session stop "$SID" >/dev/null' EXIT
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 node e2e.mjs            # chromium.connectOverCDP(process.env.CDP_URL)
```

Connect within 5 minutes; `browser.close()` only disconnects; reuse `browser.contexts()[0]`; screenshots via CDP
`Page.captureScreenshot`.

**Rules:**

- `cdp_url`, `cdp_ws_url`, `view_url` contain access tokens: never log, commit or store them. Give a live-view URL
  only to the human, only when they need to watch or take over.
- Exit codes: 2 unauthorized · 3 quota · 4 profile locked · 5 no capacity · 6 wait timeout · 11 profile host offline ·
  15 not signed in · 64/69 agent-web usage error / missing tool.
- Only use commands and flags shown by `agent-web help` and `bcli --help`.

Docs: https://github.com/servas-ai/bcli-public
