# Installation

bcli is a single self-contained executable. There is nothing to compile and no runtime to install.

- [Release assets](#release-assets)
- [Linux](#linux)
- [macOS (Apple silicon)](#macos-apple-silicon)
- [Windows](#windows)
- [agent-web helper](#agent-web-helper)
- [Verify checksums](#verify-checksums)
- [Verify the signature of SHA256SUMS](#verify-the-signature-of-sha256sums)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Next steps](#next-steps)

## Release assets

Every [release](https://github.com/servas-ai/bcli-public/releases) contains:

| Asset | What it is |
|---|---|
| `bcli-linux-amd64` | Linux, x86-64 |
| `bcli-linux-arm64` | Linux, ARM64 (e.g. Graviton, Ampere, Raspberry Pi 4/5 with a 64-bit OS) |
| `bcli-darwin-arm64` | macOS on Apple silicon (M1 and later) |
| `bcli-windows-amd64.exe` | Windows 10/11, x86-64 |
| `bcli-windows-arm64.exe` | Windows 11 on ARM (when listed in the release) |
| credential extension archive | The browser extension that fills vault entries in local sessions (file name and SHA-256 are listed in the release notes) |
| `VERSION` | The version string of this release |
| `SHA256SUMS` | SHA-256 checksums of `VERSION` and all bcli binaries |
| `SHA256SUMS.sig` | Ed25519 signature of `SHA256SUMS` (from the release that introduces it) |

In the examples below, set `VERSION` to the release tag you want, for example `v0.14.0-rc.1`.

> [!TIP]
> Download the binary **and** `SHA256SUMS` from the same release, and check the checksum before you run the binary.

## Linux

Works on any distribution with a 64-bit kernel; the binary has no shared-library dependencies.

```bash
VERSION=v0.14.0-rc.1
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')   # amd64 or arm64
BASE=https://github.com/servas-ai/bcli-public/releases/download/$VERSION

curl -fsSLO "$BASE/bcli-linux-$ARCH"
curl -fsSLO "$BASE/SHA256SUMS"
grep " bcli-linux-$ARCH\$" SHA256SUMS | sha256sum --check -    # must print: OK

install -D -m 0755 "bcli-linux-$ARCH" "$HOME/.local/bin/bcli"
bcli version
```

If `bcli` is not found, add `~/.local/bin` to your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
```

**System-wide install** (all users): `sudo install -m 0755 "bcli-linux-$ARCH" /usr/local/bin/bcli`.
Note that [self-update](#updating) needs write access to the file, so a user-owned location such as
`~/.local/bin` is recommended.

**Using the GitHub CLI** instead of `curl`:

```bash
gh release download "$VERSION" --repo servas-ai/bcli-public --pattern "bcli-linux-$ARCH" --pattern SHA256SUMS
```

## macOS (Apple silicon)

```bash
VERSION=v0.14.0-rc.1
BASE=https://github.com/servas-ai/bcli-public/releases/download/$VERSION

curl -fsSLO "$BASE/bcli-darwin-arm64"
curl -fsSLO "$BASE/SHA256SUMS"
grep " bcli-darwin-arm64\$" SHA256SUMS | shasum -a 256 --check -   # must print: OK

mkdir -p "$HOME/.local/bin"
install -m 0755 bcli-darwin-arm64 "$HOME/.local/bin/bcli"
xattr -d com.apple.quarantine "$HOME/.local/bin/bcli" 2>/dev/null || true
bcli version
```

Add `~/.local/bin` to your `PATH` if needed:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

### Gatekeeper

The macOS binary is **not notarized** by Apple. When a file was downloaded through a web browser, macOS adds the
`com.apple.quarantine` attribute and Gatekeeper refuses to start it ("cannot be opened because the developer cannot be
verified"). After verifying the checksum you have two options:

- remove the attribute: `xattr -d com.apple.quarantine ~/.local/bin/bcli`, or
- open **System Settings → Privacy & Security** and choose **Open Anyway** for `bcli` after the first blocked start.

Files downloaded with `curl` usually do not get the attribute; the `xattr` command is then a harmless no-op.

Intel Macs are not supported.

## Windows

The commands below install bcli for the current user into `%LOCALAPPDATA%\Programs\bcli` — no administrator rights
needed. Run them in **PowerShell** (Windows PowerShell 5.1 or PowerShell 7).

```powershell
$Version = "v0.14.0-rc.1"
$Arch    = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
$Asset   = "bcli-windows-$Arch.exe"
$Base    = "https://github.com/servas-ai/bcli-public/releases/download/$Version"
$Dir     = "$env:LOCALAPPDATA\Programs\bcli"

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Invoke-WebRequest "$Base/$Asset"     -OutFile "$Dir\bcli.exe"
Invoke-WebRequest "$Base/SHA256SUMS" -OutFile "$Dir\SHA256SUMS"

# Verify the checksum before running anything
$line     = Select-String -Path "$Dir\SHA256SUMS" -Pattern (" " + [regex]::Escape($Asset) + '$')
$expected = ($line.Line -split '\s+')[0]
$actual   = (Get-FileHash "$Dir\bcli.exe" -Algorithm SHA256).Hash.ToLower()
if (-not $expected -or $actual -ne $expected) { Remove-Item "$Dir\bcli.exe"; throw "Checksum mismatch - file removed." }
"Checksum OK"

# Add to the user PATH (once)
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$Dir*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$Dir", "User")
}
& "$Dir\bcli.exe" version
```

Open a **new** terminal afterwards so the changed `PATH` is picked up.

If no ARM64 build is listed in the release, use the `amd64` asset; Windows 11 on ARM runs it through emulation.

**SmartScreen.** The executable is not code-signed with a Windows publisher certificate yet. If Windows shows
"Windows protected your PC", verify the checksum, then choose **More info → Run anyway**. Files downloaded with
`Invoke-WebRequest` are usually not blocked; if they are, `Unblock-File "$Dir\bcli.exe"` removes the mark.

**Local mode on Windows.** To use the local daemon with the credential vault, unpack the credential extension archive
from the same release next to `bcli.exe`, so that the folder `%LOCALAPPDATA%\Programs\bcli\extensions\baas-autofill\`
contains `manifest.json`. See [Local mode](usage.md#local-mode).

## agent-web helper

`agent-web` is an optional helper for coding agents: it starts bcli sessions and drives them with the open-source
[agent-browser](https://www.npmjs.com/package/agent-browser) CLI (see [agents.md](agents.md#agent-web)). Install bcli
first, then:

**Requirements:** bcli, Node.js (for `npm install -g agent-browser`); on Linux/macOS also `curl` and `jq` or `python3`.
agent-browser only attaches to the cloud browser over CDP; it does not need to download a browser of its own.

<details open>
<summary><strong>Linux and macOS</strong></summary>

```bash
VERSION=v0.14.0-rc.1
curl -fsSL "https://raw.githubusercontent.com/servas-ai/bcli-public/$VERSION/bin/agent-web" -o "$HOME/.local/bin/agent-web"
chmod +x "$HOME/.local/bin/agent-web"
npm install -g agent-browser
agent-web --help
```
</details>

<details>
<summary><strong>Windows</strong> (PowerShell)</summary>

```powershell
$Version = "v0.14.0-rc.1"
$Dir     = "$env:LOCALAPPDATA\Programs\bcli"          # same folder as bcli.exe, already on PATH
foreach ($f in "agent-web.ps1", "agent-web.cmd") {
  Invoke-WebRequest "https://raw.githubusercontent.com/servas-ai/bcli-public/$Version/bin/$f" -OutFile "$Dir\$f"
}
Unblock-File "$Dir\agent-web.ps1"
npm install -g agent-browser
agent-web --help
```

`agent-web.cmd` makes `agent-web` callable from cmd.exe, PowerShell and most agent shells. In PowerShell, quote
element refs: `agent-web ab $sid click '@e3'` (an unquoted `@e3` is PowerShell splatting).
</details>

## Verify checksums

`SHA256SUMS` uses the standard `sha256sum` format (`<hex digest>  <file name>`). Check **one** file:

| OS | Command |
|---|---|
| Linux | `grep " bcli-linux-amd64$" SHA256SUMS \| sha256sum --check -` |
| macOS | `grep " bcli-darwin-arm64$" SHA256SUMS \| shasum -a 256 --check -` |
| Windows | `(Get-FileHash .\bcli-windows-amd64.exe -Algorithm SHA256).Hash.ToLower()` and compare with the line in `SHA256SUMS` |

Check **everything** you downloaded into one folder (Linux; on macOS replace `sha256sum` with `shasum -a 256`):

```bash
sha256sum --check --ignore-missing SHA256SUMS
```

The output must say `OK` for every file. A `FAILED` line means the download is corrupt or was tampered with: delete
the file and do not run it.

## Verify the signature of SHA256SUMS

From the release that ships `SHA256SUMS.sig`, the checksum file is signed with the servas.ai CLI release key
(Ed25519). The same key is built into bcli and protects [`bcli update`](#updating). The public key is in this
repository: [`keys/bcli-release-ed25519.pem`](../keys/bcli-release-ed25519.pem).

```text
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAfUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E=
-----END PUBLIC KEY-----
```

`SHA256SUMS.sig` contains the 64-byte signature, base64-encoded. Verify with OpenSSL 3.x:

```bash
curl -fsSLO "$BASE/SHA256SUMS.sig"
curl -fsSLO https://raw.githubusercontent.com/servas-ai/bcli-public/main/keys/bcli-release-ed25519.pem
base64 -d < SHA256SUMS.sig > SHA256SUMS.sig.bin        # macOS: base64 -D
openssl pkeyutl -verify -pubin -inkey bcli-release-ed25519.pem \
  -rawin -in SHA256SUMS -sigfile SHA256SUMS.sig.bin    # must print: Signature Verified Successfully
```

Then check the binaries against the verified `SHA256SUMS` as shown above. On macOS the system `openssl` is LibreSSL
and lacks `-rawin`; use OpenSSL 3 from Homebrew (`brew install openssl@3`). On Windows, the OpenSSL that ships with
Git for Windows works from Git Bash.

## Updating

Release builds keep themselves current: once a day bcli checks the API server of your environment in the background
and installs a newer version if there is one (log: `~/.bcli/update.log`). Every update is verified against the signed
checksum list before it replaces the binary; bcli never downgrades.

```bash
bcli update --check     # only report whether a newer version is available
bcli update             # install it now
bcli --env NAME update  # update from a specific environment
```

Turn the background check off with `BCLI_NO_AUTO_UPDATE=1` or `auto_update: false` in
[`config.yaml`](configuration.md). The binary must be writable by your user. A running local daemon keeps the old
version until you restart it (`bcli daemon stop && bcli daemon start`).

You can always update manually by repeating the installation steps with a newer `VERSION`.

## Uninstalling

```bash
# Linux / macOS
bcli daemon stop 2>/dev/null; rm -f ~/.local/bin/bcli
rm -f ~/.local/bin/agent-web
rm -rf ~/.bcli ~/.config/bcli     # optional: login tokens, local state, config and local vault
```

```powershell
# Windows
bcli daemon stop
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\bcli"
Remove-Item -Recurse -Force "$HOME\.bcli", "$HOME\.config\bcli"   # optional: tokens, state, config, vault
```

Deleting `~/.config/bcli/vault/` permanently deletes your local credential vault.

## Next steps

1. [Configure an environment and sign in](configuration.md)
2. [Create your first session](usage.md)
3. [Connect your coding agent](agents.md)
