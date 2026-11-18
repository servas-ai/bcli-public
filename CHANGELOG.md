# Changelog

All notable changes to bcli are listed here. Releases and binaries:
[github.com/servas-ai/bcli-public/releases](https://github.com/servas-ai/bcli-public/releases).

## v0.14.0-rc.1 — first public release candidate

First public build of bcli for Linux, macOS and Windows.

### Added

- **Cross-platform binaries:** Linux (amd64, arm64), macOS (Apple silicon) and Windows (amd64; arm64 where
  published) — single executables, no runtime dependencies.
- **Local mode on all platforms:** `bcli daemon` runs browser sessions on your own machine with the same commands and
  JSON as the cloud. On Windows, Microsoft Edge or Google Chrome is detected automatically.
- **Local credential vault and browser extension:** encrypted local vault (`bcli vault …`) whose bundled extension
  fills usernames, passwords and TOTP codes into the page without exposing them to the agent; `vault attach` brings the
  vault to cloud sessions.
- **agent-web** (`bin/agent-web` for Linux/macOS, `bin/agent-web.ps1` + `agent-web.cmd` for Windows): starts
  sessions and drives them with the open-source agent-browser CLI (snapshots and element refs), human hand-over via
  `captcha`/`assist`/`view`, tunnels, audio and stop — the recommended path for coding agents.
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
