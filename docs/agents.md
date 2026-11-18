# Using bcli with coding agents

bcli was designed to be driven by AI agents as much as by people:

- **Machine-readable output.** `session create|list|get` always print JSON; most other commands accept `--json`.
- **Stable exit codes** for every failure class ([list](usage.md#exit-codes)).
- **No interactive prompts** after the one-time `bcli login`.
- **Standard CDP**, so the agent uses the Playwright or Puppeteer it already knows.
- **Human hand-over** through the live view when a page needs a person.

## agent-web

`agent-web` ([bin/agent-web](../bin/agent-web) for Linux/macOS, [bin/agent-web.cmd](../bin/agent-web.cmd) + [bin/agent-web-ps.ps1](../bin/agent-web-ps.ps1) for Windows)
is the recommended way for an agent to use a browser. It wraps bcli and the open-source
[agent-browser](https://www.npmjs.com/package/agent-browser) CLI, so the agent navigates with page snapshots and element
refs instead of writing Playwright code. [Install it](installation.md#agent-web-helper) next to bcli.

```bash
set -euo pipefail
SID=$(agent-web start) || exit 1                # stdout: only the session id; hints on stderr
trap 'if [ -n "$SID" ]; then agent-web stop "$SID"; fi' EXIT
agent-web ab "$SID" open https://example.com
agent-web ab "$SID" snapshot -i                 # interactive elements with refs @e1, @e2, …
agent-web ab "$SID" fill @e2 "search text"
agent-web ab "$SID" click @e3
agent-web ab "$SID" get text body
agent-web ab "$SID" screenshot page.png
# agent-web stop "$SID" runs from the trap, also after errors
```

| Command | What it does |
|---|---|
| `agent-web start [--gpu] [--env NAME] [PROFILE] [bcli flags]` | Creates a session (`bcli session create --wait`, idle timeout 30 min) and prints only its id. `PROFILE` uses an existing bcli profile; other flags such as `--ttl 2h` or `--locale en-US` go to bcli. |
| `agent-web ab SID ARGS…` | Runs `agent-browser ARGS…` against the session over CDP. Every agent-browser command works: `open`, `snapshot -i`, `click`, `fill`, `type`, `press`, `get`, `eval`, `screenshot`, `tab`, `wait`, … |
| `agent-web view SID [--print]` | Opens the live view in the human's default browser (`--print` prints the URL — it contains an access token). |
| `agent-web captcha SID [HINT]` | Opens a small native window with the session's screen; the human solves the captcha and closes the window. Run it in the background or as a monitor — it waits for the human. |
| `agent-web assist SID [HINT]` | Same window for any other help: a second factor, a consent dialog, a decision. |
| `agent-web tunnel SID PORTS` | Your local ports (e.g. `3000,5173`) as `http://localhost:PORT` in the cloud browser. Blocks: run it in the background. |
| `agent-web audio SID [flags]` | `bcli audio attach` for the session (speaker/microphone as PCM). Blocks. |
| `agent-web stop SID` | Closes the agent-browser connection and stops the session. |
| `agent-web status` | Your running sessions and the ones agent-web started. |

Behaviour and contract:

- The session id is the only thing `start` writes to stdout, so `SID=$(agent-web start)` is safe. Everything else
  (hints, progress) goes to stderr.
- agent-web remembers the bcli environment of each session in `~/.bcli/agent-web/` (`AGENT_WEB_STATE`), so later
  commands need only the id. Choose the environment with `--env NAME` or `AGENT_WEB_ENV`; by default bcli's current
  environment is used. With a [local](usage.md#local-mode) environment, `start` launches the browser on your machine
  and `ab` attaches to it the same way.
- agent-web never prints session URLs except with `view --print`.
- Exit codes are those of bcli (3 quota, 4 profile locked, 5 no capacity, 15 not signed in, …), plus 64 for usage
  errors and 69 when bcli, agent-browser, curl or a JSON tool (jq or python3) is missing.
- `captcha` and `assist` use `bcli assist`, which needs a desktop session on the machine where the human sits. If no
  window can be shown (exit 3), use `agent-web view SID` instead. For local sessions the browser window is already on
  the desktop.
- On PowerShell, quote element refs: `agent-web ab $sid click '@e3'`.

## Install the skill

### Claude Code (and other Agent Skills hosts)

The skill in [`skills/bcli/SKILL.md`](../skills/bcli/SKILL.md) uses the Agent Skills format (`name` + `description`
front matter). Install it for your user or for one project:

```bash
# for all your projects
mkdir -p ~/.claude/skills && cp -r skills/bcli ~/.claude/skills/

# or only for one repository (commit it so your team gets it too)
mkdir -p .claude/skills && cp -r skills/bcli .claude/skills/
```

Without cloning this repository:

```bash
mkdir -p ~/.claude/skills/bcli
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/skills/bcli/SKILL.md \
  -o ~/.claude/skills/bcli/SKILL.md
```

Claude Code loads the skill automatically when a task involves a remote browser, web automation or bcli.

### Codex, Cursor, Aider, Gemini CLI and other AGENTS.md readers

Copy the section from [`skills/AGENTS.snippet.md`](../skills/AGENTS.snippet.md) into the `AGENTS.md` at the root of
your repository. It contains the full create → connect → stop loop, the safety rules and the exit codes in about
40 lines.

## Sign-in for agents

Agents sign in the same way people do — with the OIDC device flow — but the **human completes the sign-in**:

1. The agent (or the human) runs `bcli login` on the machine the agent uses.
2. bcli prints a URL and a code. The human opens the URL on any device and signs in.
3. bcli stores a token for that environment in `~/.bcli/`. From now on the agent works without prompts.

Each machine signs in with an identity that is authorized for it. Do not copy token files between machines and do not
hand an agent your API key — API keys are deprecated.

On a headless server or in a container, run `bcli login` in the agent's terminal and complete the sign-in from your
laptop or phone.

## Without agent-web: bcli + CDP

If you prefer your own Playwright or Puppeteer code, or cannot install agent-browser:

```bash
set -euo pipefail
SID=""
trap 'if [ -n "$SID" ]; then bcli session stop "$SID" >/dev/null; fi' EXIT
SESSION_JSON=$(bcli session create --wait) || exit 1       # never use an id from a failed create
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)

node agent-task.mjs          # chromium.connectOverCDP(process.env.CDP_URL)
```

Rules every agent should follow (the skill and the snippet enforce them):

1. **Connect within 5 minutes** of creating a session, or it ends on its own.
2. **Stop every session it creates**, including on errors — and never stop sessions it did not create.
3. **Treat session URLs as secrets.** `cdp_url`, `cdp_ws_url` and `view_url` carry an access token. Never write them to
   logs, files, commits, issues or chat transcripts. Redact `token=…`.
4. **Never fall back to a local browser.** If a session cannot be created, report the exit code instead of launching
   Chrome locally.
5. **Reuse, don't duplicate.** A profile can be open in one session only; on exit code 4 reuse the running session.
6. **Ask a human** for captchas, second factors and consent dialogs: share the `view_url` with them directly, wait for
   their confirmation, continue.
7. **Only use documented flags.** If it is not in `bcli <command> --help`, it does not exist.

## Credentials without exposing them to the agent

For logins, prefer one of these, in this order:

1. **Persistent profile:** a human signs in once in a session with `--profile NAME` (via `view_url`); later sessions
   start signed in.
2. **Local vault:** a human stores the credential with `bcli vault create … --password-env VAR`. The agent only calls
   `bcli vault list --url …` and `bcli vault autofill <id> --tab active --submit`; the browser extension fills the
   form, and the agent never sees the password. For cloud sessions the human keeps `bcli vault attach --session <id>`
   running. See [Credential vault](usage.md#credential-vault).
3. **Human hand-over:** the human types the credential directly in the live view.

Never put passwords into prompts, scripts or environment variables the agent can read.

## Examples

- [`examples/node/connect.mjs`](../examples/node/connect.mjs) — Playwright (Node.js): create, connect, screenshot, stop
- [`examples/python/connect.py`](../examples/python/connect.py) — Playwright (Python): the same in Python

## Troubleshooting for agents

| Symptom | Cause | Fix |
|---|---|---|
| exit 15 `auth_required` | not signed in on this machine | ask the human to run `bcli login` |
| exit 5 `daemon_unavailable` | no cloud environment selected, bcli fell back to the local daemon | `bcli env use cloud` or `--env cloud` |
| Playwright starts downloading Chromium | normal `npm i playwright` | set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` |
| session gone after a few minutes | never connected (5 min) or idle (10 min) | connect immediately; raise `--idle-timeout` |
| `page.screenshot()` hangs | waits for web fonts on the remote display | use CDP `Page.captureScreenshot` |
| `agent-web ab` exit 69 | agent-browser not installed | `npm install -g agent-browser` |
| `agent-web ab` starts a local browser | an old agent-browser config with a browser profile | agent-web passes its own config; do not call `agent-browser` directly against the session |
| `agent-web captcha` exit 3 | no desktop on this machine | `agent-web view SID` and give the URL to the human directly |

More in [troubleshooting.md](troubleshooting.md).
