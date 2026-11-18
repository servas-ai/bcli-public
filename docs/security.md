# Security

This page explains what bcli protects, what you are responsible for, and how to report a vulnerability.

## Identity and sign-in

- bcli signs in with **OpenID Connect** (device authorization flow) against `https://auth.servas.ai`. The browser part
  of the sign-in happens on a device of your choice; bcli never sees your password or second factor.
- The resulting token is stored per environment in `~/.bcli/tokens/`, readable only by your user. `bcli logout`
  deletes it.
- Every session, profile and tunnel belongs to the signed-in identity. Other users' session ids and profile names
  answer `404`.
- **API keys are deprecated.** bcli warns on every use. Prefer OIDC; if you must use a key for a self-hosted
  installation, store a reference (`env:`, `file:`, `cmd:`) instead of the literal key.

## Session access tokens

`cdp_url`, `cdp_ws_url` and `view_url` contain a session access token (`token=…`). Whoever has one of these URLs can
control or watch that browser until the session ends.

- Keep them in memory or in environment variables of the process that needs them.
- Never write them into logs, CI output, tickets, chat, screenshots or commits. Redact as `token=REDACTED`.
- `bcli session url <id>` reprints the existing URL; it does not issue a new token. If a URL leaked, **stop the
  session** (`bcli session stop <id>`); the token dies with it.

## Isolation

- Every session is a separate browser instance with its own user data. Throwaway sessions start from a clean state.
- Profiles are bound to their owner and can only be open in one session at a time.
- Session traffic leaves the internet only through an exit node of your own tenant. Requests to use another tenant's
  exit are rejected, and if your exit node is down, sessions fail instead of using a fallback route.
- The [exit-node container](https://github.com/servas-ai/baas-exit-docker) blocks connections from the platform into
  the host, and blocks session traffic to private, link-local and loopback ranges of your network.

## Transport

- All traffic uses HTTPS / WSS to public servas.ai endpoints.
- `bcli tunnel` pins the tunnel endpoint's host key to the fingerprint delivered in the authenticated API response.
  A mismatch aborts the connection; there is no option to skip verification.

## Credentials

- The local vault is encrypted at rest under `~/.config/bcli/vault/`, protected by your passphrase.
- Secrets are passed to `bcli vault create` by **environment variable name** (`--password-env`, `--totp-env`), so they
  never appear in the process list or shell history.
- Credentials are filled into the page by the bundled browser extension, only on a page whose origin matches the
  stored URL. The CLI never prints stored passwords; `vault get` and `vault list` show metadata only.
- Let a human unlock the vault. An agent should only reference entries by id.

## Updates and release integrity

- Every release publishes `SHA256SUMS` for all binaries. Verify before running ([how](installation.md#verify-checksums)).
- From the release that adds `SHA256SUMS.sig`, the checksum list is signed with the servas.ai CLI release key
  (Ed25519). The public key is in [`keys/bcli-release-ed25519.pem`](../keys/bcli-release-ed25519.pem):

  ```text
  MCowBQYDK2VwAyEAfUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E=
  ```

- `bcli update` verifies that signature and the per-platform hash **before** it downloads and replaces the binary,
  and it never downgrades.
- The macOS build is not notarized and the Windows build is not Authenticode-signed yet; rely on the checksums and the
  signature above.

## Your responsibilities

- Keep `~/.bcli/` and `~/.config/bcli/` private (they contain tokens and the encrypted vault).
- Sign in with your own identity on each machine; do not share or copy tokens.
- Stop sessions when you are done.
- Use bcli only for websites and accounts you are allowed to automate, and follow their terms.

## Reporting a vulnerability

Please report security issues **privately** through the contact options on [servas.ai](https://servas.ai) — do not open
a public GitHub issue. Include the bcli version, your OS and steps to reproduce, and leave out any `token=` values. We
acknowledge reports promptly and keep you informed until the issue is resolved.
