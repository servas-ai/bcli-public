<!--
  Paste the section below into your repository's AGENTS.md (Codex, Cursor, Aider, Gemini CLI, Jules and other agents
  that read AGENTS.md). Claude Code users can install skills/bcli/ instead.
-->

## Browser automation with bcli (servas.ai Browser as a Service)

Use `bcli` for every browser this project needs (end-to-end tests, scraping, web tasks). The browser runs in the
servas.ai cloud; you drive it over CDP. Never start a local Chrome/Chromium/Playwright browser instead.

**Preflight:** `bcli whoami --json` must show `"auth": "oidc"`. On exit code 15 ask the human to run `bcli login`
(device-code sign-in; the human completes it). Do not configure API keys.

**Loop:**

```bash
SESSION_JSON=$(bcli session create --wait)                 # JSON: id, state, cdp_url, cdp_ws_url, view_url
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
trap 'bcli session stop "$SID" >/dev/null' EXIT            # always stop what you start
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 node e2e.mjs            # chromium.connectOverCDP(process.env.CDP_URL)
```

**Rules:**

- Connect within 5 minutes of `session create`. `browser.close()` only disconnects; `bcli session stop <id>` ends it.
- Reuse `browser.contexts()[0]`. Take screenshots via CDP `Page.captureScreenshot`.
- `cdp_url`, `cdp_ws_url`, `view_url` contain access tokens: never log, commit or store them. Show `view_url` only to
  the human, only when they need to watch or take over (captcha, 2FA).
- Persistent logins: `--profile NAME`. Exit code 4 = profile already open → reuse that session.
- Local dev server inside the remote browser: `bcli tunnel start --session "$SID" --ports 3000` (blocks; background it).
- Exit codes: 2 unauthorized · 3 quota · 4 profile locked · 5 no capacity · 6 wait timeout · 11 profile host offline ·
  15 not signed in.
- Only use commands and flags shown by `bcli --help`.

Docs: https://github.com/servas-ai/bcli-public
