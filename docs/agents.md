# Using bcli with coding agents

bcli was designed to be driven by AI agents as much as by people:

- **Machine-readable output.** `session create|list|get` always print JSON; most other commands accept `--json`.
- **Stable exit codes** for every failure class ([list](usage.md#exit-codes)).
- **No interactive prompts** after the one-time `bcli login`.
- **Standard CDP**, so the agent uses the Playwright or Puppeteer it already knows.
- **Human hand-over** through the live view when a page needs a person.

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

## The agent loop

```bash
SESSION_JSON=$(bcli session create --wait)
SID=$(printf '%s' "$SESSION_JSON" | jq -r .id)
export CDP_URL=$(printf '%s' "$SESSION_JSON" | jq -r .cdp_url)
trap 'bcli session stop "$SID" >/dev/null' EXIT

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

More in [troubleshooting.md](troubleshooting.md).
