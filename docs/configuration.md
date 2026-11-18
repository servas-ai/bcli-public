# Configuration

bcli talks to one or more **environments**. An environment is either a BaaS cloud installation (`kind: cloud`, an
HTTPS API endpoint) or the local daemon on your machine (`kind: local`, a local socket). You register environments
once, sign in, and then pick one per command.

- [Endpoints](#endpoints)
- [Add the servas.ai cloud](#add-the-servasai-cloud)
- [Sign in (OIDC device flow)](#sign-in-oidc-device-flow)
- [Choosing the environment](#choosing-the-environment)
- [Managing environments](#managing-environments)
- [Files and directories](#files-and-directories)
- [config.yaml reference](#configyaml-reference)
- [Environment variables](#environment-variables)
- [Tenants, quotas and exit nodes](#tenants-quotas-and-exit-nodes)
- [API keys (deprecated)](#api-keys-deprecated)

## Endpoints

All servas.ai endpoints are public HTTPS. No VPN or Tailscale is required on your side.

| Endpoint | Purpose |
|---|---|
| `https://api.baas.servas.ai` | Control API: sessions, profiles, exit nodes, tenant, self-update |
| `https://edge.baas.servas.ai` | Session traffic: CDP (`/s/<id>`), live view (`/s/<id>/view`), tunnels |
| `https://console.baas.servas.ai` | Web console: your sessions, tenant and exit keys |
| `https://auth.servas.ai` | Sign-in (OIDC) |

Quick reachability check, no account needed:

```bash
curl -sS https://api.baas.servas.ai/v1/health
# {"backend":"k8s","status":"ok",...}
```

## Add the servas.ai cloud

```bash
bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai
bcli env use cloud
```

- `--kind` is required (`cloud` or `local`). The environment name is free; `cloud` is just a convention.
- `env add` does not select the environment; `env use` does.
- Use only the HTTPS endpoint of an installation you trust. Your login token is sent there.

## Sign in (OIDC device flow)

```bash
bcli login                 # or: bcli login --env cloud
```

bcli prints a URL and a short code on stderr:

```text
Open https://auth.servas.ai/...
Code: ABCD-EFGH
```

Open the URL in any browser — on this machine or on your phone — enter the code and sign in with your servas.ai
account. bcli waits and then prints `Logged in to cloud.` This works on headless servers and inside agent sandboxes
because no browser is needed on the machine that runs bcli.

```bash
bcli whoami                # env, owner, role and auth method
bcli whoami --json         # machine-readable; auth must be "oidc"
bcli logout                # forget the token of this environment
```

Rules of thumb:

- Every person, and every machine an agent runs on, signs in with **its own** authorized identity.
- Do not copy token files between machines and do not share device codes.
- If you see `auth_required` (exit code 15), run `bcli login` again.

## Choosing the environment

bcli resolves the environment in this order:

1. `--env NAME` on the command line
2. the `BCLI_ENV` environment variable
3. `current_env` in `config.yaml` (set by `bcli env use NAME`)
4. a local environment named `local`, if its daemon socket exists

If nothing matches, commands fail with `env_not_found`. When the selected environment is the local daemon and it is
not running, commands fail with `daemon_unavailable` (exit code 5).

```bash
bcli --env cloud session list          # one command
BCLI_ENV=cloud bcli session list       # one shell / one CI job
bcli env use cloud                     # default from now on
```

## Managing environments

```bash
bcli env list              # name, kind, reachability, installation, version and your role
bcli env list --offline    # do not contact the servers
bcli env current           # the active environment
bcli env use NAME
bcli env remove NAME
```

Several installations side by side are fine — for example the servas.ai cloud and a self-hosted installation of your
company:

```bash
bcli env add cloud  --kind cloud --endpoint https://api.baas.servas.ai
bcli env add onprem --kind cloud --endpoint https://baas.example.com
bcli env add local  --kind local
bcli --env onprem login
```

## Files and directories

`~` is your home directory (`%USERPROFILE%` on Windows).

| Path | Content |
|---|---|
| `~/.config/bcli/config.yaml` | Environments, current environment, options (mode 0600). Override with `BCLI_CONFIG`. |
| `~/.bcli/` | bcli home: login tokens (`tokens/`), local daemon state and socket, logs. Override with `BCLI_HOME`. |
| `~/.bcli/update.log` | Log of the background self-update check |
| `~/.config/bcli/vault/` | Encrypted local credential vault |

Keep these directories private. They contain your login tokens and, for the vault, encrypted credentials.

## config.yaml reference

bcli writes this file for you; editing by hand is rarely needed.

```yaml
current_env: cloud
environments:
  cloud:
    kind: cloud
    endpoint: https://api.baas.servas.ai
  local:
    kind: local
    socket: /home/me/.bcli/daemon.sock
# Browser executable for local sessions (local mode only)
browser_path: /opt/chromium/chrome
# Set to false to turn off the daily background update check
auto_update: true
```

| Key | Meaning |
|---|---|
| `current_env` | Default environment (`bcli env use`) |
| `environments.<name>.kind` | `cloud` or `local` |
| `environments.<name>.endpoint` | HTTPS API endpoint (cloud) |
| `environments.<name>.socket` | Daemon socket (local; filled in automatically) |
| `environments.<name>.api_key_ref` | Deprecated API-key reference, see below |
| `browser_path` | Browser executable for local sessions |
| `auto_update` | `false` disables the background update check; `bcli update` keeps working |

## Environment variables

| Variable | Effect |
|---|---|
| `BCLI_ENV` | Environment name for this process (overridden by `--env`) |
| `BCLI_CONFIG` | Path of the configuration file |
| `BCLI_HOME` | bcli home directory (default `~/.bcli`) |
| `BCLI_NO_AUTO_UPDATE=1` | Disable the background update check |
| `BCLI_TUNNEL_FINGERPRINT` | Fingerprint for `bcli tunnel connect` (alternative to `--fingerprint`) |
| `BAAS_BROWSER_PATH` | Browser executable for local sessions (overrides `browser_path`) |
| `BCLI_VAULT_PASSPHRASE` | Passphrase for `bcli vault unlock` in automation. Prefer an interactive unlock by a human. |

## Tenants, quotas and exit nodes

On the servas.ai cloud every account belongs to a **tenant**. The tenant defines how many sessions (and GPU sessions)
you can run at the same time, how many profiles you can keep, the maximum session duration, when the access expires
and which **exit node** your sessions use to reach the internet.

```bash
bcli tenant          # human-readable
bcli tenant --json   # tenant.{id,name,default_exit_node,expires_at,max_*}, usage.{sessions,gpu_sessions,profiles,profile_bytes}
bcli exit-node list  # exit nodes you may use
```

Sessions need no exit flag: they automatically leave through your tenant's default exit node. To have the browsers
appear with your own public IP — your office line, a data-center host — run an exit node yourself. It is a single
Docker container and needs no VPN installation on the host:
**[servas-ai/baas-exit-docker](https://github.com/servas-ai/baas-exit-docker)**. Create the one-time exit key in the
console under **Tenant & exit keys**.

Limits are enforced by the server. When a limit is reached, `bcli session create` fails with `quota_exceeded`
(exit code 3).

## API keys (deprecated)

Older installations issued personal API keys. They still work for now, but bcli prints a deprecation warning on every
use and they will be removed. Use `bcli login` instead. If you still need one for a self-hosted installation, store
only a **reference**, never the key itself:

```bash
bcli env add onprem --kind cloud --endpoint https://baas.example.com --key-file ~/.config/bcli/onprem.key
# or --api-key env:VAR | file:/path | cmd:<command that prints the key>
```
