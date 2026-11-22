# Installation

bcli is a single self-contained executable. There is nothing to compile and no runtime to install. You install it
from a terminal, with one command or a package manager; the installers check the release signature before anything
is written.

- [Quick install](#quick-install)
- [Package managers](#package-managers)
- [What the installers check](#what-the-installers-check)
- [Installer options](#installer-options)
- [Platforms and release assets](#platforms-and-release-assets)
- [Linux](#linux)
- [macOS](#macos)
- [Windows](#windows)
- [Credential extension](#credential-extension)
- [Node.js (for agent-web and the examples)](#nodejs-for-agent-web-and-the-examples)
- [agent-web helper](#agent-web-helper)
- [Manual install from the terminal](#manual-install-from-the-terminal)
- [Verify checksums](#verify-checksums)
- [Verify the signature of SHA256SUMS](#verify-the-signature-of-sha256sums)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Next steps](#next-steps)

## Quick install

**Linux and macOS** (bash, zsh or any POSIX shell):

```bash
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh
```

**Windows** (PowerShell 5.1 or 7, normal window, no administrator rights):

```powershell
irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
```

Both install the latest release for your OS and CPU and print the next steps. Then
[sign in](configuration.md) and [create your first session](usage.md).

A specific release:

```bash
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh -s -- --version v0.14.4
```

```powershell
$env:BCLI_VERSION = "v0.14.4"; irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
```

> [!NOTE]
> bcli is not code-signed: there is no Windows Authenticode certificate and no Apple Developer ID or notarization.
> The Ed25519 signature of `SHA256SUMS` is what proves a file comes from servas.ai. Files downloaded in a terminal
> carry no internet mark (Mark-of-the-Web, macOS quarantine), so Windows and macOS start bcli without a prompt.
> **Not supported:** machines that only allow signed programs, such as Windows with AppLocker, App Control for
> Business (WDAC) or Smart App Control enforcing. Talk to us if you need bcli on such a machine.

## Package managers

| Package manager | Install | Update |
|---|---|---|
| Homebrew (macOS, Linux) | `brew install servas-ai/tap/bcli` | `brew upgrade bcli` |
| Scoop (Windows) | `scoop bucket add servas https://github.com/servas-ai/scoop-bucket` then `scoop install servas/bcli` | `scoop update bcli` |
| winget (Windows) | `winget install servas.bcli` | `winget upgrade servas.bcli` |

Homebrew tap: [servas-ai/homebrew-tap](https://github.com/servas-ai/homebrew-tap). Scoop bucket:
[servas-ai/scoop-bucket](https://github.com/servas-ai/scoop-bucket). Both pin the SHA-256 of each binary from the
signed `SHA256SUMS`. Scoop needs Git to add a bucket: run `scoop install git` first if `scoop bucket add` asks for it.

No Scoop yet? It installs per user, without administrator rights ([scoop.sh](https://scoop.sh)):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # once, if PowerShell refuses to run the installer
irm get.scoop.sh | iex
scoop install git
```

**winget:** the package `servas.bcli` has been submitted to the winget community repository
([microsoft/winget-pkgs#486222](https://github.com/microsoft/winget-pkgs/pull/486222)). `winget install servas.bcli`
works once Microsoft has merged it; until then use `install.ps1` or Scoop.

Update a package-manager install with that package manager, so it keeps track of the installed version.

## What the installers check

`install.sh` and `install.ps1` download from the [GitHub releases](https://github.com/servas-ai/bcli-public/releases)
of this repository and stop before installing anything if a check fails:

1. **Signature.** `SHA256SUMS.sig` must be a valid Ed25519 signature of `SHA256SUMS` with the servas.ai release key,
   which is built into both scripts (the same key as [`keys/bcli-release-ed25519.pem`](../keys/bcli-release-ed25519.pem)
   and inside bcli itself).
   - `install.sh` uses the first verifier that works on the machine: OpenSSL 3, `python3` or `bc`. Each one first has
     to pass an RFC 8032 test vector (accept the valid signature, refuse a changed message) before its verdict counts.
     If none is available, the script explains how to get one and stops (fail closed).
   - `install.ps1` checks the signature in plain .NET (RFC 8032), the same code as
     [`scripts/windows/verify-release.ps1`](../scripts/windows/verify-release.ps1). It needs no OpenSSL, Git or bcli.
2. **Version.** `VERSION` must match its line in the signed `SHA256SUMS` and the release tag.
3. **Checksum.** The SHA-256 of the downloaded binary must match its line in the signed `SHA256SUMS`.

## Installer options

| `install.sh` | `install.ps1` | Meaning |
|---|---|---|
| `--version vX.Y.Z` or `BCLI_VERSION` | `$env:BCLI_VERSION` | Install this release instead of the latest |
| `--dir DIR` or `BCLI_INSTALL_DIR` | `$env:BCLI_INSTALL_DIR` | Install into DIR |
| `--dry-run` | `$env:BCLI_DRY_RUN = "1"` | Download and verify only, change nothing |
| `--insecure-skip-signature` | — | Install even when no signature verifier is available. **Not recommended:** the checksum then only proves that the download is complete |

Default install locations:

- **Linux and macOS:** `~/.local/bin/bcli`; as root `/usr/local/bin/bcli`. If the directory is not on your `PATH`,
  the script prints the line to add to your shell profile.
- **Windows:** `%LOCALAPPDATA%\Programs\bcli\bcli.exe` for the current user, added to the user `PATH`. On Windows on
  ARM the script installs the x64 build, which runs through emulation. A running `bcli.exe` (daemon, vault, bridge) is
  renamed aside, as `bcli update` does, and bcli removes the old copy on its next start.

Pass options to `install.sh` after `sh -s --`, for example `... | sh -s -- --dir /opt/bin`.

## Platforms and release assets

| Platform | Asset | Cloud sessions | Local daemon + vault |
|---|---|:---:|:---:|
| Linux x86-64 | `bcli-linux-amd64` | yes | yes |
| Linux ARM64 | `bcli-linux-arm64` | yes | yes |
| macOS Apple silicon | `bcli-darwin-arm64` | yes | yes |
| macOS Intel | `bcli-darwin-amd64` | yes | see [macOS](#macos) |
| Windows 10/11 x86-64 | `bcli-windows-amd64.exe` | yes | yes |

Every [release](https://github.com/servas-ai/bcli-public/releases) publishes exactly these files:

| Asset | What it is |
|---|---|
| `bcli-linux-amd64`, `bcli-linux-arm64` | Linux, x86-64 and ARM64 (e.g. Graviton, Ampere, Raspberry Pi 4/5 with a 64-bit OS) |
| `bcli-darwin-arm64`, `bcli-darwin-amd64` | macOS on Apple silicon and on Intel |
| `bcli-windows-amd64.exe` | Windows 10/11, x86-64 (Windows 11 on ARM runs it through emulation) |
| `VERSION` | The version string of the release |
| `SHA256SUMS` | SHA-256 checksums of the release files |
| `SHA256SUMS.sig` | Ed25519 signature of `SHA256SUMS` (base64) with the servas.ai release key |

`SHA256SUMS` also lists two files that are not published: the credential extension archive
(`baas-autofill-<version>.zip`, already inside every bcli binary) and an internal macOS bundle. That is why the manual
checks below check one line, or use `--ignore-missing`.

## Linux

Works on any distribution with a 64-bit kernel; the binary has no shared-library dependencies. Use the
[quick install](#quick-install) or Homebrew. `curl` or `wget` must be present, and one of OpenSSL 3 (`openssl`),
`python3` or `bc` for the signature check; every common distribution has at least one of them.

**System-wide install** (all users): run the installer as root, or with `--dir /usr/local/bin` from a user that can
write there. [Self-update](#updating) needs write access to the file, so a user-owned location such as
`~/.local/bin` is recommended.

## macOS

Apple silicon and Intel Macs are supported. Use the [quick install](#quick-install) or Homebrew. The installer works
with the tools of a stock macOS: the system `openssl` there is LibreSSL without Ed25519, so it falls back to
`python3` (when the Command Line Tools are installed) or `bc`. The Go linker gives the Apple silicon binary the ad-hoc
signature macOS requires; a binary downloaded in the terminal carries no quarantine flag and starts without a prompt.

### Local mode on macOS (optional)

For [local mode](usage.md#local-mode) the local daemon and the Bitwarden bridge run as per-user LaunchAgents (no root,
no system service), so they start again after every login.
[`scripts/macos/install-macos.sh`](../scripts/macos/install-macos.sh) sets them up. It needs the absolute path of the
Chromium-based browser the daemon should launch. In v0.14.0 it supports **Apple silicon only**; on Intel Macs use
cloud sessions.

```bash
curl -fsSLO https://raw.githubusercontent.com/servas-ai/bcli-public/main/scripts/macos/install-macos.sh
shasum -a 256 install-macos.sh   # v0.14.0: 6b74ec6a5e8a808d529ce67e0374d9dd262115c57e12a13dfe7575fe3178e720
chmod +x install-macos.sh
BROWSER='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
./install-macos.sh --bin ~/.local/bin/bcli --browser "$BROWSER" --dry-run   # shows what it will install
./install-macos.sh --bin ~/.local/bin/bcli --browser "$BROWSER"
bcli daemon status
```

`./install-macos.sh --uninstall` removes the LaunchAgents again (binaries, profiles and vault stay). Run it as the
logged-in user, without `sudo`.

## Windows

bcli for Windows is one file, `bcli.exe`: CLI, local daemon, local vault, Bitwarden bridge and a native approval
dialog (WebView2).

**Requirements:** Windows 10 or 11 x64 (Windows 11 on ARM runs the x64 build through emulation), Microsoft Edge
(the WebView2 Runtime ships with Windows 11), and a normal, **non-elevated** user. The daemon, the vault and the
bridge refuse an elevated (administrator) token.

### Install

```powershell
irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
bcli --version                  # same as: bcli version
```

Or with Scoop (`scoop install servas/bcli`, see [Package managers](#package-managers)). Other terminals pick up the
changed `PATH` once you open them again. Defender scans a new `bcli.exe` on its first start; `bcli daemon start`
waits up to 90 seconds for that.

To install by hand instead, with the same checks, see [Manual install from the terminal](#manual-install-from-the-terminal).

### First start

```powershell
bcli daemon start                         # local daemon (named pipe), runs in the background
bcli daemon autostart enable --bwbridge   # optional: start daemon (and Bitwarden bridge) at every logon
bcli vault unlock                         # passphrase prompt (first time: creates the vault)
bcli --env local session create           # Edge window
```

**Add a login and fill it.** The password comes from an environment variable, never from the command line:

```powershell
$env:SITE_PW = [Net.NetworkCredential]::new("", (Read-Host -AsSecureString "site password")).Password
bcli vault create --name example --url https://example.com/login --user alice --password-env SITE_PW
Remove-Item env:SITE_PW
bcli vault list                                                   # ID  NAME  (the ID is the first column)
bcli vault tabs                                                   # the open tabs of the local session
bcli vault autofill ID --url https://example.com/login --submit   # {"status":"filled","submitted":true} with --json
```

`--url` picks the tab with that page (`--tab TABID` or `--tab active` instead); the URL must belong to the login's
site, otherwise the fill is refused (`credential origin mismatch`, exit 9). Leave out `--submit` to fill without
sending the form. `--totp-env VAR` adds a one-time-code secret (`otpauth://` URI).

`bcli vault tabs` lists the tabs the session's browser extension reports to the vault (`ID URL TITLE`). It stays
empty until the extension has connected, a few seconds after `session create` (up to about 30 s, longest for the first
session after a `bcli update`). Since v0.14.2 `vault autofill` and `vault bw autofill` wait for it on their own: up to
45 s (`--ready-timeout`, a duration such as `90s`; `0` = no wait), with one line `vault: waiting up to 45s for the browser extension to report
the page` on stderr. Nothing is filled and no approval is requested before the page is listed. If the extension does
not connect in time they exit 1 with `browser extension not connected yet: …`: check that the session still runs and
that `bcli vault tabs` lists the page, then run the command again.

### The vault in the background

`bcli vault unlock` starts a background vault process that serves the browser extension. It **locks itself 15
minutes after `bcli vault unlock`, whether it was used or not**; using it does not extend that time. Vault commands
then exit with code 7 (`vault is locked`) until the next `bcli vault unlock`. After a reboot or a `bcli update` it
needs one new unlock too: bcli never stores the passphrase.

| How to unlock | Command |
| --- | --- |
| Interactive prompt | `bcli vault unlock` |
| Piped (scripts, agents) | `$pass \| bcli vault unlock`, or `Get-Content <private file> \| bcli vault unlock` |
| Environment variable | `$env:BCLI_VAULT_PASSPHRASE = …; bcli vault unlock` (remove it afterwards) |
| File | `%USERPROFILE%\.config\bcli\vault.passphrase`, with an owner-only ACL (below) |

**Passphrase file.** bcli reads the file only if its ACL is private: owned by you, inheritance off, exactly one entry
(you, full control). A file created normally (`Set-Content`, Notepad) inherits the folder's entries. bcli then does not
use it: `bcli vault unlock` stops with exit 7 and `vault: the passphrase file vault.passphrase exists but was not used:
its ACL must be owner-only and not inherited. Fix it in PowerShell with: icacls …`, without opening a passphrase prompt
(v0.14.0 ignored such a file without a message). An empty file is reported the same way. Only `BCLI_VAULT_PASSPHRASE`
takes precedence over the file; **piped input does not**: while `vault.passphrase` exists, `bcli vault unlock` uses it
(and fails on a broken, empty or wrong one) even if you pipe the passphrase in. Delete the file to unlock by pipe or
prompt. (The message's pointer to "Passphrase file" in `WINDOWS-INSTALL.md` means this section.) After creating the file (one line, the passphrase), run once:

```powershell
$f = "$env:USERPROFILE\.config\bcli\vault.passphrase"
icacls $f /inheritance:r /grant:r "${env:USERDOMAIN}\${env:USERNAME}:F"
icacls $f                                   # must show only <PC or domain>\<you>:(F), nothing else
```

The folder `.config\bcli` exists after the first `bcli vault unlock`. To use the prompt again, delete the file. `bcli vault status` prints `absent`, `locked`
or `unlocked`. `bcli vault lock` locks the vault but keeps the background process; `bcli vault stop` locks it and ends
the process (`--session ID` for the vault of a cloud session).

### Cloud sessions and the vault

```powershell
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai; bcli env use cloud
bcli login
bcli session create --wait
bcli vault unlock --session ID                       # serve the local vault to that cloud session
bcli vault autofill ITEM --session ID --url URL --submit
```

`vault unlock --session ID` runs the attach as a background process and returns (`attached`); this is the
recommended form. `vault attach --session ID` does the same in the foreground until the session ends or you press
Ctrl+C. `bcli vault stop --session ID` ends the background attach.

### Bitwarden (optional)

bcli can fill logins from a Bitwarden vault, each one after a person approves it in a native dialog. The Bitwarden
bridge (`bcli bwbridge`) keeps the Bitwarden keys in memory and opens the dialogs.

1. In the Bitwarden web vault create an API key: **Settings → Security → Keys → View API key**
   (`client_id`, `client_secret`).
2. Start the bridge: `bcli bwbridge start` (once per logon), or let the logon start do it:
   `bcli daemon autostart enable --bwbridge`.
3. `bcli vault bw setup` opens the setup dialog: a label, the server (bitwarden.com, bitwarden.eu or a self-hosted
   URL), `client_id`, `client_secret`, the master password and a new **approval password** (different from the master
   password; you type it when you approve a login). `bcli vault bw status` then shows `setup=true`.
   `bcli vault bw setup --add` adds another Bitwarden vault to the same bridge.
4. Fill in a session: `bcli vault bw autofill --wait --submit` (local session, active tab; cloud: `--session ID`).
   The first request after a bridge start asks for the master password, then the approval dialog shows the site, the
   requesting program and the matching logins: **Deny**, **Allow once**, **Always for this site** (local) or **For
   this session** (cloud). Deny exits with code 12. Cloud sessions need the vault attached first
   (`bcli vault unlock --session ID`); with Bitwarden an attach can approve logins for at most 5 minutes, then the next
   login needs `vault unlock --session ID` again.

| Bridge | Command |
| --- | --- |
| Start now | `bcli bwbridge start` |
| Start at every logon | `bcli daemon autostart enable --bwbridge` |
| Forget the Bitwarden keys (stays running) | `bcli vault bw lock` |
| Stop (locks it, ends the process) | `bcli bwbridge stop` |
| Logon start off | `bcli daemon autostart disable` (both entries), or `enable` without `--bwbridge` |

The logon start adds two values to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (`bcli daemon`,
`bcli Bitwarden bridge`). Explorer runs them at logon as the normal user; their output goes to `autostart.log` in
`%USERPROFILE%\.bcli`. The vault passphrase and the Bitwarden unlock are needed once after each logon, by design.
`bcli daemon autostart status` shows the entries.

### Pitfalls

- Run bcli as the logged-on user, not elevated and not from a scheduled task: the credential relay refuses a browser
  inside a Job Object (`bcli daemon start` warns), and daemon and vault refuse elevated tokens.
- Let bcli create `BCLI_HOME` itself (private ACL); a folder made beforehand by PowerShell is refused.
- The vault lives in `%USERPROFILE%\.config\bcli\vault`.
- Moving `bcli.exe` to another folder: the next start registers the browser extension host again; until then local
  sessions fail with `provision_error`. Keep the folder on your `PATH`.
- `bcli assist` and `bcli audio` are not available on Windows; use the live view (`view_url`) for human hand-over.
- **Fixed in v0.14.4: many local sessions could lock your Windows account.** Up to v0.14.3, each new local session
  started Edge with a fresh profile, and Edge then made one failed Windows sign-in check (Security event 4625). Under
  the default Windows 11 lockout policy (10 failures within 10 minutes), about ten local sessions in a row locked the
  account for 10 minutes. v0.14.4 tells the session's Edge profile the answer up front, so Edge skips the check; your own
  Edge profile and Edge policies are not touched. Update with `bcli update`. If your account is locked, wait 10 minutes.

**Execution policy.** A fresh Windows 11 has the PowerShell execution policy `Restricted`. `irm … | iex` and bcli
itself are not affected, and `agent-web` starts through `agent-web.cmd`, which works anyway. `npm` (which is
`npm.ps1` in PowerShell) is blocked: call `npm.cmd` instead, or allow local scripts for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Fixed in v0.14.2

Two minor issues of v0.14.0 on Windows are fixed in v0.14.2:

- The first `vault bw autofill` or `vault autofill` right after `session create` (or after `bcli update`) failed with
  `bw: bridge operation failed` / `vault operation failed` while the browser extension had not connected yet. Both now
  wait for it (see [First start](#first-start)). With v0.14.0: wait until `bcli vault tabs` lists the page.
- A passphrase file with an inherited ACL was ignored without a message. bcli now stops with exit 7 and prints the
  `icacls` fix (see [The vault in the background](#the-vault-in-the-background)).

## Credential extension

The [credential vault](usage.md#credential-vault) fills logins through a small browser extension. **You do not need to
download it.** Every bcli binary (Linux, macOS and Windows) contains the extension and installs it into its local
sessions by itself; a bcli update replaces it together with bcli. Its archive is listed in `SHA256SUMS` but not
published separately.

Do **not** put a copy into `~/.bcli/extensions/`: on Linux a copy there takes precedence over the built-in extension
and would no longer be updated with bcli.

## Node.js (for agent-web and the examples)

bcli does not need Node.js. The [agent-web helper](#agent-web-helper) (via `agent-browser`) and the
[Node.js example](../examples/) do.

**Windows.** As a standard user (no administrator rights), use [Scoop](#package-managers):
`scoop install nodejs-lts`. `winget install OpenJS.NodeJS.LTS` also works, but it installs Node.js for the whole
machine (it may ask for an administrator), and a freshly created user may not have `winget` until the App Installer
has been set up for them. Then open a new terminal:

```powershell
node --version
npm.cmd --version      # plain "npm" also works once the execution policy allows scripts (see above)
```

**Linux (Debian/Ubuntu).** Install Node.js from your distribution, and let global npm packages go into your home
directory so `npm install -g` needs no `sudo` and never fails with `EACCES`:

```bash
sudo apt install nodejs npm
node --version                            # agent-browser needs Node.js 22 or newer
npm config set prefix "$HOME/.local"      # global packages → ~/.local/bin
```

Many distributions still ship an older Node.js (Debian 12: 18, Debian 13: 20, Ubuntu 24.04: 18). If
`node --version` prints less than 22, install a current LTS from [nodejs.org](https://nodejs.org/en/download)
instead, for example with `nvm`, which needs no `sudo` and keeps global packages in your home directory.

**macOS.** `brew install node`.

## agent-web helper

`agent-web` is an optional helper for coding agents: it starts bcli sessions and drives them with the open-source
[agent-browser](https://www.npmjs.com/package/agent-browser) CLI (see [agents.md](agents.md#agent-web)). Install bcli
and [Node.js](#nodejs-for-agent-web-and-the-examples) first.

**Requirements:** bcli, agent-browser; on Linux/macOS also `curl` and `jq` or `python3`. agent-browser only attaches
to the cloud browser over CDP; it does not need to download a browser of its own.

<details open>
<summary><strong>Linux and macOS</strong></summary>

```bash
VERSION=v0.14.4                                                      # the release to install
curl -fsSL "https://raw.githubusercontent.com/servas-ai/bcli-public/$VERSION/bin/agent-web" -o "$HOME/.local/bin/agent-web"
chmod +x "$HOME/.local/bin/agent-web"
npm install -g agent-browser
agent-web --help
```
</details>

<details>
<summary><strong>Windows</strong> (PowerShell)</summary>

```powershell
$Version = "v0.14.4"                                                 # the release to install
$Dir     = "$env:LOCALAPPDATA\Programs\bcli"                         # same folder as bcli.exe, already on PATH
foreach ($f in "agent-web.cmd", "agent-web-ps.ps1") {
  Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/servas-ai/bcli-public/$Version/bin/$f" -OutFile "$Dir\$f"
}
npm.cmd install -g agent-browser
agent-web --help
```

`agent-web.cmd` starts `agent-web-ps.ps1` with `-ExecutionPolicy Bypass` for that one process, so `agent-web` works
from cmd.exe, PowerShell and agent shells even when the execution policy is `Restricted`. The PowerShell script has a
different name on purpose: PowerShell would otherwise run an `agent-web.ps1` directly and hit the execution policy.
In PowerShell, quote element refs: `agent-web ab $sid click '@e3'` (an unquoted `@e3` is PowerShell splatting).
</details>

## Manual install from the terminal

The installers do exactly this; use it if you want to see every step or cannot pipe a script into a shell.

<details>
<summary><strong>Linux and macOS</strong> (needs OpenSSL 3; on macOS <code>brew install openssl@3</code>)</summary>

```bash
VERSION=v0.14.4                                                      # the release to install
OS=$(uname -s | tr 'A-Z' 'a-z')                                      # linux or darwin
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')    # amd64 or arm64
BASE=https://github.com/servas-ai/bcli-public/releases/download/$VERSION
curl -fsSLO "$BASE/bcli-$OS-$ARCH" -O "$BASE/SHA256SUMS" -O "$BASE/SHA256SUMS.sig"
curl -fsSLO https://raw.githubusercontent.com/servas-ai/bcli-public/main/keys/bcli-release-ed25519.pem
openssl base64 -d -A -in SHA256SUMS.sig -out SHA256SUMS.sig.bin
openssl pkeyutl -verify -pubin -inkey bcli-release-ed25519.pem \
  -rawin -in SHA256SUMS -sigfile SHA256SUMS.sig.bin                  # must print: Signature Verified Successfully
grep " bcli-$OS-$ARCH\$" SHA256SUMS | sha256sum --check -        # macOS: shasum -a 256 --check -; must print OK
mkdir -p "$HOME/.local/bin" && install -m 0755 "bcli-$OS-$ARCH" "$HOME/.local/bin/bcli"
bcli version
```
</details>

<details>
<summary><strong>Windows</strong> (PowerShell 5.1 or 7)</summary>

Download the four files into one folder (turn the progress bar off first: with it, `Invoke-WebRequest` in Windows
PowerShell 5.1 takes minutes for a 25 MB file):

```powershell
$ProgressPreference = 'SilentlyContinue'
$Version = "v0.14.4"
$Base = "https://github.com/servas-ai/bcli-public/releases/download/$Version"
$Src  = "$env:USERPROFILE\Downloads\$Version"
New-Item -ItemType Directory -Force -Path $Src | Out-Null
foreach ($f in 'bcli-windows-amd64.exe', 'SHA256SUMS', 'SHA256SUMS.sig', 'VERSION') {
    Invoke-WebRequest -UseBasicParsing "$Base/$f" -OutFile "$Src\$f"
}
```

Stock Windows has no OpenSSL and Windows PowerShell has no Ed25519 API. Check the signature and the checksums with
[`scripts/windows/verify-release.ps1`](../scripts/windows/verify-release.ps1), a short, readable script with the
release key built in (plain .NET, RFC 8032). It is not part of the signed release files (it is what checks them), so
compare its SHA-256 with the value below first:

```powershell
Invoke-WebRequest -UseBasicParsing -OutFile "$env:USERPROFILE\Downloads\verify-release.ps1" `
  "https://raw.githubusercontent.com/servas-ai/bcli-public/main/scripts/windows/verify-release.ps1"
(Get-FileHash "$env:USERPROFILE\Downloads\verify-release.ps1" -Algorithm SHA256).Hash.ToLower()
# must be: b66a687dc8943c57dca5d6ed4f9e6173c79503beec6da192a6b2a87429cd1403
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\verify-release.ps1" -Dir $Src
# Signature OK / OK VERSION / OK bcli-windows-amd64.exe   (exit 0; any mismatch exits 1)
```

Then install for the current user:

```powershell
$Dir = "$env:LOCALAPPDATA\Programs\bcli"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Copy-Item "$Src\bcli-windows-amd64.exe" "$Dir\bcli.exe"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $Dir) {
    [Environment]::SetEnvironmentVariable("Path", ((@($userPath -split ';') + $Dir | Where-Object { $_ }) -join ';'), "User")
}
if (($env:Path -split ';') -notcontains $Dir) { $env:Path = ((@($env:Path -split ';') + $Dir | Where-Object { $_ }) -join ';') }
bcli --version
```
</details>

## Verify checksums

`SHA256SUMS` uses the standard `sha256sum` format (`<hex digest>  <file name>`). Check **one** file:

| OS | Command |
|---|---|
| Linux | `grep " bcli-linux-amd64$" SHA256SUMS \| sha256sum --check -` |
| macOS | `grep " bcli-darwin-arm64$" SHA256SUMS \| shasum -a 256 --check -` |
| Windows | `(Get-FileHash .\bcli-windows-amd64.exe -Algorithm SHA256).Hash.ToLower()` and compare with the line in `SHA256SUMS` |

Check everything you downloaded into one folder (on macOS replace `sha256sum` with `shasum -a 256`):

```bash
sha256sum --check --ignore-missing SHA256SUMS
```

`--ignore-missing` skips the two listed files that are not published. Every downloaded file must say `OK`. A
`FAILED` line means the download is corrupt or was tampered with: delete the file and do not run it.

## Verify the signature of SHA256SUMS

`SHA256SUMS` is signed with the servas.ai CLI release key (Ed25519). The same key is built into bcli, protects
[`bcli update`](#updating) and is built into the install scripts. The public key is in this repository:
[`keys/bcli-release-ed25519.pem`](../keys/bcli-release-ed25519.pem).

```text
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAfUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E=
-----END PUBLIC KEY-----
```

`SHA256SUMS.sig` contains the 64-byte signature, base64-encoded. Verify with OpenSSL 3.x:

```bash
VERSION=v0.14.4
BASE=https://github.com/servas-ai/bcli-public/releases/download/$VERSION
curl -fsSLO "$BASE/SHA256SUMS" -O "$BASE/SHA256SUMS.sig"
curl -fsSLO https://raw.githubusercontent.com/servas-ai/bcli-public/main/keys/bcli-release-ed25519.pem
openssl base64 -d -A -in SHA256SUMS.sig -out SHA256SUMS.sig.bin
openssl pkeyutl -verify -pubin -inkey bcli-release-ed25519.pem \
  -rawin -in SHA256SUMS -sigfile SHA256SUMS.sig.bin    # must print: Signature Verified Successfully
```

Then check the binaries against the verified `SHA256SUMS` as shown above. On macOS the system `openssl` is LibreSSL
and cannot verify Ed25519; use OpenSSL 3 from Homebrew (`brew install openssl@3`) or simply `install.sh`, which
brings its own verifier. On Windows use [`scripts/windows/verify-release.ps1`](../scripts/windows/verify-release.ps1)
(see [Manual install](#manual-install-from-the-terminal)).

## Updating

Release builds keep themselves current on **Linux, macOS and Windows**: once a day bcli checks the API server of your
cloud environment in the background and installs a newer version if there is one (log: `~/.bcli/update.log`, on
Windows `%USERPROFILE%\.bcli\update.log`). Every update is verified against the signed checksum list before it
replaces the binary; bcli never downgrades.

```bash
bcli update --check     # only report whether a newer version is available
bcli update             # install it now
bcli --env NAME update  # update from a specific environment
```

Turn the background check off with `BCLI_NO_AUTO_UPDATE=1` or `auto_update: false` in
[`config.yaml`](configuration.md). The binary must be writable by your user. A running local daemon keeps the old
version until you restart it (`bcli daemon stop && bcli daemon start`).

**Windows.** The running `bcli.exe` is renamed aside (`.bcli-replaced-<random>.old` in the same folder) and the new
file takes its name, so `PATH`, the logon start and the browser registration stay valid. A running daemon and
Bitwarden bridge are stopped and started again from the new file; a background vault needs one new
`bcli vault unlock`. The daily background check never installs while daemon, vault or bridge run; it notes the
available version instead.

**Package managers and the installers.** Running the [installer](#quick-install) again installs the latest release in
place. A Homebrew, Scoop or winget install is best updated with its package manager (`brew upgrade bcli`,
`scoop update bcli`, `winget upgrade servas.bcli`).

## Uninstalling

Start with `bcli logout` (once per cloud environment: `bcli --env NAME logout`). It deletes the stored sign-in of
that environment on this machine and says so. It does not revoke the sign-in at the server; that grant ends on its
own when it expires.

**Linux and macOS:**

```bash
bcli logout
bcli daemon stop 2>/dev/null; rm -f ~/.local/bin/bcli ~/.local/bin/agent-web
rm -rf ~/.bcli ~/.config/bcli     # optional: login tokens, local state, config and local vault
```

On macOS with local mode, run `./install-macos.sh --uninstall` first. Homebrew: `brew uninstall bcli`.

**Windows:**

```powershell
bcli logout
bcli uninstall            # keeps the vault, environments and logs
bcli uninstall --purge    # also deletes them
```

`bcli uninstall` removes everything bcli registered for the user and reports each step:

1. the logon start (both `HKCU\…\Run` values);
2. the background vault, the Bitwarden bridge and the daemon (its local sessions end), then any other process still
   running from this `bcli.exe`;
3. the browser native-messaging registrations of bcli for Edge, Chrome, Chromium and Brave, and `%LOCALAPPDATA%\bcli`;
4. the `PATH` entry and the install folder `%LOCALAPPDATA%\Programs\bcli`. A running `bcli.exe` cannot delete itself,
   so a hidden helper removes the folder about three seconds after the command ends. Do not run it from inside that
   folder.

User data kept without `--purge`: `%USERPROFILE%\.bcli` (logs, session profiles, state), `%USERPROFILE%\.config\bcli`
(the vault, environments) and `%USERPROFILE%\.config\bwbridge` (Bitwarden bridge state). Open PowerShell windows keep
their old `PATH` until they are closed. Scoop: `scoop uninstall bcli`; winget: `winget uninstall servas.bcli`.

Check afterwards (all three print nothing):

```powershell
Get-Process bcli* -ErrorAction SilentlyContinue
(Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run).PSObject.Properties.Name -like 'bcli*'
'Microsoft\Edge', 'Google\Chrome', 'Chromium', 'BraveSoftware\Brave-Browser' |
  ForEach-Object { Get-Item "HKCU:\Software\$_\NativeMessagingHosts\ai.servas.baas.vault" -ErrorAction SilentlyContinue }
```

Deleting `~/.config/bcli/vault/` (Windows: `%USERPROFILE%\.config\bcli\vault`) permanently deletes your local
credential vault.

## Next steps

1. [Configure an environment and sign in](configuration.md)
2. [Create your first session](usage.md)
3. [Connect your coding agent](agents.md)
