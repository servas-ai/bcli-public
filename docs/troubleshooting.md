# Troubleshooting

Start with these three commands; they answer most questions:

```bash
bcli version
bcli env list          # is the environment reachable, which version, which role?
bcli whoami            # who does the server think you are?
```

## Installation

**`bcli: command not found`**
The install directory is not on your `PATH`. Linux/macOS: add `export PATH="$HOME/.local/bin:$PATH"` to your shell
profile and open a new terminal. Windows: open a **new** terminal after installing; check with
`$env:Path -split ';'`.

**macOS: "bcli cannot be opened because the developer cannot be verified"**
The file was downloaded with a web browser, which marks it with the quarantine flag. bcli is not notarized, so install
it from the terminal instead: `curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh`
(or `brew install servas-ai/tap/bcli`). Terminal downloads carry no quarantine flag.

**macOS: "bad CPU type in executable"**
The binary does not match the CPU (for example `bcli-darwin-arm64` on an Intel Mac). Run the installer again: it picks
`bcli-darwin-amd64` on Intel and `bcli-darwin-arm64` on Apple silicon.

**Windows: "Windows protected your PC", or the file is blocked**
The file was downloaded with a web browser, which marks it as coming from the internet. Install from PowerShell
instead (`irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex`, or Scoop): files
downloaded in the terminal carry no such mark.

**Windows: "This app has been blocked by your system administrator" / blocked by App Control or Smart App Control**
The machine only allows signed programs (AppLocker, App Control for Business / WDAC, Smart App Control). bcli is not
code-signed and is not supported on such machines; ask your contact at servas.ai.

**Installer: "cannot check the Ed25519 signature on this machine"**
`install.sh` found no working verifier. Install OpenSSL 3, `python3` or `bc` and run it again, or use Homebrew.
Avoid `--insecure-skip-signature`.

**Installer: "SIGNATURE INVALID" or "CHECKSUM MISMATCH"**
Nothing was installed. Run it again; if it repeats, do not install from that network and [tell us](../SECURITY.md).

**Checksum mismatch**
Delete the file and download it again from the release page. If it still does not match, do not run it and
[tell us](../SECURITY.md).

## Sign-in

**`code=auth_required` / exit code 15**
You are not signed in to this environment, or your login expired: `bcli login` (or `bcli login --env NAME`).

**`code=device_code_expired` / exit code 13**
The sign-in was not completed in time. Run `bcli login` again and finish it right away.

**`code=login_denied` / exit code 12**
The sign-in was cancelled or your account is not allowed to use this installation. Contact your administrator or your
contact at servas.ai.

**`unauthorized` / exit code 2 although `whoami` works**
Your identity is known but has no access to this resource (for example another user's session or profile, or an
admin-only command).

**`bcli login needs a cloud environment (--env)`**
The selected environment is local. Use `bcli login --env cloud` or `bcli env use cloud`.

**Warning: "API-key authentication is deprecated"**
The environment still uses an API key. Remove it and sign in with OIDC:
`bcli env remove cloud`, then `bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai`, then `bcli login --env cloud`.

## Environments

**`code=env_not_found`**
No environment is selected. `bcli env list`, then `bcli env use NAME` or pass `--env NAME`.

**`daemon_unavailable` / exit code 5**
bcli is talking to the local daemon (no cloud environment selected, or `--env local`) and the daemon is not running.
Either select the cloud (`bcli env use cloud`) or start the daemon (`bcli daemon start`).

**Windows: `daemon_unavailable` although the daemon runs**
The daemon and the vault are only reachable from the same Windows logon session, from non-elevated processes. A
terminal opened with "Run as administrator", another user account or an SSH login cannot reach them. Use a normal
terminal on the desktop where you started the daemon.

**`env list` shows `not-logged-in`**
You have not signed in to that environment yet: `bcli login --env NAME`. `bad-key` means a stored token or API key was
rejected — sign in again.

**`env list` shows the environment as unreachable**
Check your network and proxy: `curl -sS https://api.baas.servas.ai/v1/health` must return JSON with `"status":"ok"`.
Corporate proxies must allow HTTPS and WebSocket (`wss://`) traffic to `*.baas.servas.ai` and `auth.servas.ai`.

## Sessions

**`quota_exceeded` / exit code 3**
Your tenant's limit for concurrent sessions, GPU sessions or profiles is reached. `bcli tenant` shows usage and limits;
`bcli session list --json` shows your running sessions — stop the ones you no longer need.

**`profile_locked` / exit code 4**
The profile is already open in another session. Find it with `bcli session list --json` and reuse or stop it.

**exit code 5 with `no_capacity` or `no_gpu`**
No free capacity right now. Retry after a short wait, or run without `--gpu`.

**exit code 6 (`--wait` timed out)**
The session did not become ready within `--ready-timeout` (default 5 minutes). Check it with
`bcli session get <id> --json`, stop it, and retry. Sessions with a profile start cold and take longer.

**exit code 11 (`profile_host_offline`)**
The host that stores this profile is temporarily offline. Retry later — the profile itself is fine. Do not delete or
recreate it.

**`code=exit_node_unavailable: exit node is unavailable or belongs to another tenant` on `session create` (exit code 1)**
The tenant's exit node is not running (or the exit you named belongs to another tenant), so the API refuses to create
the session (no session id is returned — this is an error, not a `failure_code`). Sessions never fall back to another
route. `bcli tenant` shows the name of your default exit, `bcli exit-node list` whether it is `online`. Start it again
on its host (`docker start <name>`, `docker logs <name>`; no new key needed after the first enrollment), or set it up
from scratch: **[Start an exit node](exit-node.md)**. The console (**Tenant & exit node → Refresh**) shows when it is
online again.

If `bcli exit-node list` shows an exit as `online` but under another name than `bcli tenant` (for example
`baas-exit` after a plain `./up.sh`), sessions do not use it: remove it, issue a new key and start it with the default
exit name ([Start an exit node → Troubleshooting](exit-node.md#troubleshooting)).

**Session `failed` with `failure_code: ready_timeout`**
The browser did not become ready in time (`terminate_reason: provision_failed`). This is usually transient: stop it
if it is still listed and create a new session. If it keeps happening, retry later and report the session id.

**The session disappeared after a few minutes**
`terminate_reason` in `bcli session get <id> --json` tells you why:

- `idle_timeout` — nobody connected within 5 minutes after start, or the last CDP client disconnected and the idle
  timer (default 10 minutes) ran out. Connect right after `create`; raise `--idle-timeout` (max `1h`).
- `ttl_expired` — the lifetime ended. Use `--ttl` (capped by your tenant's maximum session duration).
- `client_stop` — someone ran `bcli session stop`.

## Connecting

**Playwright downloads a browser / launches a local window**
You called `chromium.launch()` instead of `chromium.connectOverCDP(cdp_url)`, or installed browsers you do not need.
Use `connectOverCDP` and set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` when installing.

**`connectOverCDP` fails with 401 / 403**
The token in the URL is wrong, cut off, or the session has ended. Copy the complete `cdp_url` (with `?token=…`) or get
it again with `bcli session url <id>`. Shell-quote the URL.

**Some tools treat the HTTPS URL as `host:9222` and start their own Chrome**
Not every CDP tool understands an HTTPS discovery URL with a query string. Pass `cdp_ws_url` (the `wss://` URL) to
such tools instead.

**`page.screenshot()` hangs**
On a remote headed browser it may wait a long time for web fonts. Use CDP:
`(await context.newCDPSession(page)).send('Page.captureScreenshot', { format: 'png' })`.

**New pages do not have my cookies / fingerprint**
Use the session's existing context (`browser.contexts()[0]`) instead of `browser.newContext()`.

## Tunnels

**`port … reserved` / validation error**
Ports must be ≥ 1024, at most 16 per tunnel, and not one of `3128, 5432, 7000, 7070, 8080, 9100, 9222, 9223`.
Run your dev server on another port.

**`connection refused` inside the remote browser**
The tunnel only forwards; your local service must be listening on `127.0.0.1:<port>` and the `bcli tunnel start`
process must still be running.

**Fingerprint mismatch**
The tunnel endpoint presented a different key than the API announced. bcli refuses to connect on purpose. Stop the
session, create a new one, and report it if it happens again.

## Local mode

**Windows: filling is refused / `daemon start` warns about a Windows job**
bcli runs inside a Windows job that keeps its child processes in the job — typically because it was started from Task
Scheduler or another launcher. The browser extension then refuses to fill credentials, and `~/.bcli/daemon.log` shows
`reason=pipe_owner sub=job_contained`. Stop the daemon (`bcli daemon stop`) and start it again from a normal,
non-elevated terminal.

**Windows: local sessions stopped working after moving `bcli.exe`**
Moving the executable is supported: run `bcli daemon stop`, then start it from the new location
(`bcli daemon start`); it registers itself for the extension again. Make sure `PATH` points to the new folder.

**Windows: Edge shows "Disable developer mode extensions"**
Expected for every local session: bcli loads its credential extension unpacked. Close the pop-up with **×**; do not
choose "Turn off", otherwise the vault cannot fill logins in that session.

**Local session does not start / no browser found**
Set the browser executable: `browser_path` in `~/.config/bcli/config.yaml` or `BAAS_BROWSER_PATH`. On Windows, install
Microsoft Edge or Google Chrome in the default location.

**`bcli daemon status` says it is not running after an update**
Restart it: `bcli daemon stop`, then `bcli daemon start`.

**`vault autofill` or `vault bw autofill` waits 45 s, then `browser extension not connected yet`**
No local session is running, or its browser has not loaded bcli's extension yet. Start a session
(`bcli --env local session create --wait`), wait until `bcli vault tabs` lists the page, then run the command again.
For a cloud session add `--session <id>`.

**Vault: exit code 7**
The vault is locked, does not exist yet, or the passphrase is wrong; the message names the command to run. Local:
`bcli vault unlock`. Cloud session: `bcli vault unlock --session <id>`. The unlock stays active in the background
for 15 minutes or until `bcli vault lock`, logout or reboot (on Windows: per logon session, from a non-elevated
terminal).

**Vault: exit code 8**
No vault is bound to that cloud session (or the binding ended with the session): `bcli vault unlock --session <id>`.

**Vault: I need more detail**
Vault commands are quiet by default. Run the failing command again with `BAAS_LOG_LEVEL=debug` and remove anything
that contains `token=` before sharing the output.

**Vault: exit code 9 / 10**
9: the page's origin does not match the URL stored with the credential. 10: no login form was found or not all fields
could be filled — check that the right tab is active (`bcli vault tabs`) and the login form is visible.

## Updates

**`bcli update` says `no cloud environment configured`, or that you are up to date although GitHub has a newer release**
`bcli update` installs the version your cloud environment ships, so it needs a cloud environment and `bcli login`.
The servas.ai cloud can ship a new release a little after it appears on GitHub. To install the newest GitHub release
now, or without a cloud environment, run the [installer](installation.md#quick-install) again or use your package
manager (`brew upgrade bcli`, `scoop update bcli`).

**Linux/macOS: the Bitwarden bridge still runs the old version after an update**
`bcli bwbridge start --restart` (the bridge locks; unlock it again when asked). The local daemon:
`bcli daemon stop`, then `bcli daemon start`.

**Windows: `bcli update` says a newer version is available but does not install it in the background**
Expected: the daily background check never replaces bcli while the daemon, the vault or the Bitwarden bridge run. Run
`bcli update` yourself; it stops and restarts daemon and bridge, and the vault needs one new `bcli vault unlock`.

**`bcli update` refuses to install**
bcli only installs builds whose checksum list is signed by the servas.ai release key and never downgrades. A
development build is only replaced with `--force`. The file must be writable by your user — move a system-wide
install to `~/.local/bin`, or update with your package manager (`brew upgrade bcli`, `scoop update bcli`).

## Still stuck?

Collect `bcli version`, `bcli env list --offline`, the exact command and its stderr output (**remove any URL that
contains `token=`**) and send it to your contact at servas.ai, or open an
[issue](https://github.com/servas-ai/bcli-public/issues).
