# Changelog

All notable changes to bcli are listed here. Releases and binaries:
[github.com/servas-ai/bcli-public/releases](https://github.com/servas-ai/bcli-public/releases).

## v0.14.2 — Windows fixes

### Fixed

- **Autofill right after `session create`:** `vault autofill` and `vault bw autofill` wait up to 45 s
  (`--ready-timeout`) until the session's browser extension lists the page in `vault tabs`, instead of failing with
  `bridge operation failed` / `vault operation failed`. A missing extension ends with `browser extension not connected
  yet`. Nothing is filled and no approval is requested before that.
- **Windows passphrase file:** a `vault.passphrase` with an inherited ACL is no longer ignored silently; `vault unlock`
  exits 7 with the `icacls` fix. An empty file is reported.
- **`update --check` without a cloud environment** says `no cloud environment configured` and how to add one.

### Changed

- `env list` shows only the release part of the server version.
- Public builds no longer contain the identity of an internal agent mode or the comments of the embedded database
  schema.

## v0.14.0 — first final public release

### Added

- **Terminal installers:** `install.sh` (Linux, macOS) and `install.ps1` (Windows) download from this repository's
  releases, verify the Ed25519 signature of `SHA256SUMS` and the SHA-256 of the binary, and install per user. Homebrew
  tap (`brew install servas-ai/tap/bcli`) and Scoop bucket (`scoop install servas/bcli`).
- **Windows client:** per-user install without administrator rights, named-pipe daemon, local vault in the background
  (`vault unlock`, `vault lock`, `vault stop`), Edge sessions with the credential extension, cloud sessions with
  `vault unlock --session`, Bitwarden bridge with a native WebView2 dialog, logon start
  (`bcli daemon autostart enable [--bwbridge]`), signed self-update (`bcli update`), `bcli uninstall [--purge]`,
  `bcli --version`.
- **macOS:** full CLI with the native dialog and the Bitwarden bridge on Apple silicon and, new, on Intel
  (`bcli-darwin-amd64`).
- **Several Bitwarden vaults in one approval window:** `bcli vault bw setup --add`; logins are grouped by vault label,
  account and server; `setup --account ID` relabels an account.

### Changed

- Release assets are the five binaries plus `VERSION`, `SHA256SUMS` and `SHA256SUMS.sig`. There is no
  `bcli-windows-arm64.exe` anymore (Windows 11 on ARM runs the x64 build) and no separate macOS bundle or extension
  archive.
- Documentation describes terminal and package-manager installs only. bcli is not code-signed; machines that only
  allow signed programs (AppLocker, App Control for Business / WDAC, Smart App Control) are not supported.

### Known issues

- Windows: the first `bcli vault bw autofill` shortly after a new local session opened can fail once
  (`bw: bridge operation failed`); run it again. The passphrase file is ignored without a message unless its ACL is
  owner-only. Both are fixed in a later patch release.

## v0.14.0-rc.2 — second release candidate, first public release

First public build of bcli for Linux, macOS and Windows.

### Added

- **Cross-platform binaries:** Linux (amd64, arm64), macOS (Apple silicon) and Windows (amd64; arm64 where
  published) — single executables, no runtime dependencies.
- **Local mode on all platforms:** `bcli daemon` runs browser sessions on your own machine with the same commands and
  JSON as the cloud. On Windows, Microsoft Edge or Google Chrome is detected automatically.
- **Local credential vault and browser extension:** encrypted local vault whose built-in extension fills usernames,
  passwords and TOTP codes into the page without exposing them to the agent. `bcli vault unlock` asks for the
  passphrase and keeps the vault unlocked in the background until `bcli vault lock`; `bcli vault unlock --session ID`
  serves it to a cloud session, and the data commands accept `--session ID`. Vault commands are quiet unless
  `BAAS_LOG_LEVEL` is set.
- `bcli env list` shows `not-logged-in` before the first login; `--env local` works without configuration.
- **agent-web** (`bin/agent-web` for Linux/macOS, `bin/agent-web.cmd` + `bin/agent-web-ps.ps1` for Windows): starts
  sessions and drives them with the open-source agent-browser CLI (snapshots and element refs), human hand-over via
  `view` (plus `captcha`/`assist` on Linux/macOS), tunnels, audio (Linux/macOS) and stop — the recommended path for coding agents. agent-browser's background process is started
  detached, so captured output never hangs; the Windows script writes UTF-8.
- **Public release repository** with installation guides, configuration and usage documentation, a ready-made agent
  skill (`skills/bcli/SKILL.md`), an `AGENTS.md` snippet and examples.

### Included from earlier releases

- OIDC device-code sign-in (`bcli login`, `whoami`, `logout`) against `auth.servas.ai`; API keys deprecated.
- Tenants with quotas, access expiry and a mandatory per-tenant exit node (`bcli tenant`, `bcli exit-node list`);
  self-hosted exit node via [baas-exit-docker](https://github.com/servas-ai/baas-exit-docker).
- Signed self-update (`bcli update`): Ed25519-signed `SHA256SUMS`, no downgrades.
- Pinned tunnels (`bcli tunnel start`), GPU sessions (`--gpu`), session audio (`bcli audio attach`), human hand-over
  (`view_url`, `bcli assist`), persistent and shareable profiles.
- Stable `failure_code` on failed sessions and dedicated exit codes (e.g. 11 = profile host offline).

### Notes

- The macOS binary is not notarized and the Windows binary is not Authenticode-signed; verify checksums before use.
- Windows has no self-update yet (`bcli update --check` explains it): re-run the installer to update. No service
  autostart, no `bcli assist` / `bcli audio`; the ARM64 build has no native dialog window.
- The macOS build has not yet been run on Apple silicon for this release candidate (preview); not notarized.
- In the cloud the default session TTL is the tenant's maximum session duration; local daemon sessions default to 60 minutes.
