# Bitwarden autofill

bcli can fill logins from your Bitwarden vault into a browser session, **each one after a person approves it** in a
native window on your desktop. The agent never sees the password: it asks for a login, you approve it, and bcli's
browser extension fills it into the page.

The part that talks to Bitwarden is the **Bitwarden bridge**. It is built into every `bcli` (there is no second
program to install) and runs in the background as your user:

| | The bridge runs as | Set up with |
|---|---|---|
| Linux | systemd user service `bcli-bwbridge.service` | `install.sh`, or `bcli bwbridge start` |
| macOS | LaunchAgent `ai.servas.bcli.bwbridge` | `install.sh`, or `bcli bwbridge start` |
| Windows | background process of `bcli.exe` | `bcli bwbridge start`, at logon: `bcli daemon autostart enable --bwbridge` |

The bridge keeps the Bitwarden keys only in memory. They are gone when it stops, at logout and after
`bcli vault bw lock`; the next request asks for the master password again.

## 1. Requirements

- A desktop session: the approval windows open on your screen. Run the commands below in a terminal **inside** that
  session (not over SSH, not as root or administrator).
- **Linux:** a systemd desktop (KDE Plasma, GNOME and most others) and WebKitGTK 4.1 for the windows
  (Debian/Ubuntu: `sudo apt install libwebkit2gtk-4.1-0`; Fedora: `sudo dnf install webkit2gtk4.1`).
- **Ubuntu and Kubuntu 23.10 to 25.10** (and derivatives that restrict user namespaces with AppArmor): an AppArmor
  profile for the window, see [AppArmor](#apparmor-ubuntu-2310-to-2510). Ubuntu 26.04, Debian and Fedora do not need it.
- bcli **v0.14.5 or newer** on Linux and macOS (`bcli version`; `bcli update` or the installer brings it).

## 2. Start the bridge

**Linux and macOS:** the [installer](installation.md#quick-install) does it when you run it in a desktop terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh
```

It prints `bitwarden  bridge running (…)`. If it says it skipped the bridge (no desktop session, run as root, or
`--no-bwbridge`), or you installed with Homebrew, run once in a desktop terminal:

```bash
bcli bwbridge start
bcli bwbridge status     # service installed, starts at login, active; bridge running
```

`bcli bwbridge start` writes the service (`~/.config/systemd/user/bcli-bwbridge.service` or
`~/Library/LaunchAgents/ai.servas.bcli.bwbridge.plist`), starts it now and at every login. It is safe to run again.

**Windows:** `bcli bwbridge start` once per logon, or `bcli daemon autostart enable --bwbridge` for every logon
([details](installation.md#bitwarden-optional)).

## 3. Connect your Bitwarden account

1. In the Bitwarden web vault create an API key: **Settings → Security → Keys → View API key**. You need
   `client_id` and `client_secret`. Accounts on the EU server use the EU web vault (`vault.bitwarden.eu`).
2. Run:

   ```bash
   bcli vault bw setup
   ```

   A window opens. Fill in:
   - **Vault label:** a name for this vault, e.g. `WORK`.
   - **Server:** **choose `bitwarden.eu`** if your account is on the EU server. The window preselects
     `bitwarden.com`; a wrong server fails the setup. A self-hosted server: its URL.
   - `client_id`, `client_secret`, your **master password**.
   - A new **approval password**, different from the master password. You type it when you approve a login.

   Type these only into this window, never into a chat, a command line or a file.
3. `bcli vault bw status` now shows `setup=true`. More vaults: `bcli vault bw setup --add`.

An unanswered setup window closes after five minutes; run `bcli vault bw setup` again.

## 4. Fill a login

### Local sessions (browser on your machine)

Local mode needs the local daemon, the local vault and a Chromium-based browser ([local mode](usage.md#local-mode)):

```bash
bcli daemon start
bcli vault unlock                                  # local vault passphrase (once per login)
bcli --env local session create --wait             # open the login page in that browser window
bcli vault bw autofill --wait --submit             # active tab of the local session
```

The first request after a bridge start asks for the master password. Then the approval window shows the site, the
requesting program and the matching logins: **Deny**, **Allow once** or **Always for this site**. Deny exits with
code 12.

### Cloud sessions

Attach your local vault to the cloud session first, then ask the bridge for the login:

```bash
bcli session create --wait --json                  # note the session id
bcli vault unlock --session <session-id>           # local vault passphrase; prints "attached"
bcli vault bw autofill --session <session-id> --wait --submit
```

For cloud sessions the approval window offers **Allow once** or **For this session**; nothing is approved
permanently. With Bitwarden an attach approves logins for at most 5 minutes; after that run
`bcli vault unlock --session <session-id>` again. Logins with two steps (name, then password on a second page) need
`autofill` once per page.

## AppArmor (Ubuntu 23.10 to 25.10)

These releases forbid new programs to create user namespaces (`kernel.apparmor_restrict_unprivileged_userns=1`),
which the sandbox of the approval window needs. Without a profile the window does not open and bcli reports
`dialog: helper failed (… AppArmor …)`. The profile names only bcli's window program and keeps its sandbox on, like
the profiles Ubuntu ships for other WebKit apps.

The installer installs it when it runs as root or `sudo` works without a password; otherwise it prints this command.
Run it once:

```bash
bcli bwbridge apparmor | sudo tee /etc/apparmor.d/bcli-prompt >/dev/null && sudo apparmor_parser -r /etc/apparmor.d/bcli-prompt
```

Check: `cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns` prints `1` on systems that need it;
`bcli bwbridge status` shows a hint while the profile is missing. A profile from an older bcli package that names only
`~/.local/bin/bcli-prompt` must be replaced with this one. Do not turn the sandbox or the restriction off.

## Manage the bridge

| | Command |
|---|---|
| State | `bcli bwbridge status` (`--json`), `bcli vault bw status` |
| Forget the Bitwarden keys (keeps running) | `bcli vault bw lock` |
| Stop now (locks it; starts again at the next login) | `bcli bwbridge stop` |
| Start, or run the new version after `bcli update` / `brew upgrade` | `bcli bwbridge start --restart` |
| Remove the service (Linux, macOS) | `bcli bwbridge remove` |
| "Always" approvals | `bcli vault bw grants`, `bcli vault bw revoke ID` |
| Uninstall bcli with everything it set up | `bcli uninstall` (`--purge` also deletes the Bitwarden bridge state) |

Logs: Linux `journalctl --user -u bcli-bwbridge`; Windows `bwbridge.log` in `%USERPROFILE%\.bcli`. The bridge state
(no passwords; encrypted account data) is in `~/.config/bwbridge`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `bwbridge is not running or BWBRIDGE_SOCK points elsewhere` | Start it: `bcli bwbridge start`. Unset an old `BWBRIDGE_SOCK` from earlier test packages. |
| No window; `dialog: helper failed (… AppArmor …)` | Ubuntu 23.10–25.10: install the [AppArmor profile](#apparmor-ubuntu-2310-to-2510). |
| No window; `no window possible here` | The bridge has no display (started over SSH or before the desktop) or WebKitGTK 4.1 is missing: install it, then `bcli bwbridge start --restart` in a desktop terminal. |
| Setup fails right after you click **Set up** | Wrong server: EU accounts must choose `bitwarden.eu`. |
| `bcli bwbridge start` says `no systemd user manager answers here` | Run it in a terminal of your desktop session, not over SSH or `su`. Without systemd: `bcli bwbridge run` in a terminal of the desktop (stops when you close it). |
| Cloud fill: attach expired | `bcli vault unlock --session <id>` again (Bitwarden attaches last at most 5 minutes). |
