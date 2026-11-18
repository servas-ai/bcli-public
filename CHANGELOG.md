# Changelog

All notable changes to bcli are listed here. Releases and binaries:
[github.com/servas-ai/bcli-public/releases](https://github.com/servas-ai/bcli-public/releases).

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
