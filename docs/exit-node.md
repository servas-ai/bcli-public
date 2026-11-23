# Start an exit node

Every cloud session of your tenant reaches the internet through your tenant's **exit node**. Websites see the public
IP of the network the exit node runs in. You run the exit node yourself: one Docker container on an always-on Linux
machine at the site whose internet connection the sessions should use. While it is not running, new cloud sessions of
your tenant fail with `exit_node_unavailable` (see [Troubleshooting](#troubleshooting)).

- [What you need](#what-you-need)
- [1. Find the name of your exit node](#1-find-the-name-of-your-exit-node)
- [2. Build the image](#2-build-the-image)
- [3. Issue a one-time key](#3-issue-a-one-time-key)
- [4. Start the container](#4-start-the-container)
- [5. Check that it works](#5-check-that-it-works)
- [What the exit node can and cannot see](#what-the-exit-node-can-and-cannot-see)
- [Stop, remove, enroll again](#stop-remove-enroll-again)
- [Troubleshooting](#troubleshooting)

## What you need

- A Linux machine that stays on (server, VM, mini PC, NAS with Docker), amd64 or arm64.
- Docker Engine 23 or newer (BuildKit), plus Compose v2 (`docker compose`) if you want to use the Compose file.
  Your user may need `sudo` for `docker`.
- `/dev/net/tun` on the host (present on every normal Linux). The container needs `NET_ADMIN` and that device.
- **Outbound** internet access only. **No inbound ports, no port forwarding, no VPN client** on the host:
  - TCP 443 (HTTPS) to the coordination and relay servers of the overlay network (Tailscale). This alone is enough.
  - UDP 3478 (STUN) and outbound UDP from any port (peer-to-peer WireGuard, usually to UDP 41641) make it faster.
    If your firewall blocks UDP, traffic is relayed over TCP 443 and still works, with more latency.
- A sign-in to the [BaaS Console](https://console.baas.servas.ai) as a member of your tenant (the same account you use
  for `bcli login`). Any member can issue exit keys; there is no separate admin role for it.
- The `git` command is not needed: Docker builds the image straight from GitHub.

## 1. Find the name of your exit node

Sessions use your tenant's **default exit node** by name. Your exit node must register with exactly that name.

```bash
bcli tenant              # last line: "Default exit: <name>", for example "Default exit: acme-exit"
```

Below, `acme-exit` stands for that name. If the line is empty, ask your servas.ai contact which name to use; they set
it as your default once the node is online.

## 2. Build the image

The image is built from the public repository
[servas-ai/baas-exit-docker](https://github.com/servas-ai/baas-exit-docker) (official Tailscale base image, pinned by
digest, plus a small start script and firewall rules). Read the `Dockerfile` and `entrypoint.sh` there if you want to
check what runs.

```bash
docker build -t baas-exit:local https://github.com/servas-ai/baas-exit-docker.git#main
```

No access to GitHub on that machine? In the console, **Tenant & exit node → Offline install: prebuilt image** offers
`customer-exit.tar` (or `bcli tenant image --output customer-exit.tar` on any signed-in machine). Load it with
`docker load --input customer-exit.tar` and use the image name it prints instead of `baas-exit:local`.

## 3. Issue a one-time key

The key enrolls the container **once**. It is not needed again after that, not even after a restart or reboot.

1. Open <https://console.baas.servas.ai/tenant> and sign in.
2. **Set up an exit node → Issue one-time key**. Copy it.

The key is valid for **10 minutes** and for **one** enrollment, so issue it right before step 4. It only lets a
device join as an exit node of your tenant.

On the machine of the exit node, put it into an env file that only you can read (an editor, not the shell, so the key
is not in your shell history):

```bash
mkdir -p ~/baas-exit && cd ~/baas-exit
umask 077
nano exit.env            # or vi; content below
```

```ini
TS_HOSTNAME=acme-exit
TS_AUTHKEY=tskey-auth-PASTE-THE-KEY-HERE
```

For scripts: the console calls `POST https://api.baas.servas.ai/v1/tenant/exit-keys` with your sign-in token and the
body `{"ttl_seconds": 600}` (60 to 3600). The answer contains `id`, `key`, `expires_at` and `"reusable": false`.

## 4. Start the container

Either with `docker run`:

```bash
cd ~/baas-exit
docker volume create acme-exit-state
docker run -d --name acme-exit --restart unless-stopped \
  --cap-add=NET_ADMIN --device=/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv6.conf.all.forwarding=1 \
  --read-only --tmpfs /run:rw,nosuid,nodev --tmpfs /tmp:rw,nosuid,nodev \
  -v acme-exit-state:/var/lib/baas-exit \
  --env-file exit.env \
  baas-exit:local
```

or with Docker Compose, as `~/baas-exit/compose.yaml` next to `exit.env`:

```yaml
services:
  exit:
    image: baas-exit:local
    container_name: acme-exit
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    sysctls:
      net.ipv4.ip_forward: "1"
      net.ipv6.conf.all.forwarding: "1"
    read_only: true
    tmpfs: ["/run:rw,nosuid,nodev", "/tmp:rw,nosuid,nodev"]
    env_file: exit.env
    volumes: ["state:/var/lib/baas-exit"]
volumes:
  state:
```

```bash
docker compose up -d
```

- **`restart: unless-stopped`** brings the node back after a crash or a reboot of the host.
- **The volume** (`/var/lib/baas-exit`) holds the node identity. With it, restarts need no new key and the node keeps
  its name. Without a volume the identity lives only in memory and every restart needs a new key.
- **After the first start**, delete the `TS_AUTHKEY=` line from `exit.env`. The key is used up anyway; the node now
  starts from the identity in the volume.

Alternative with the helper script of the repository (asks for the key without echo, same container settings):
`git clone https://github.com/servas-ai/baas-exit-docker.git && cd baas-exit-docker && NAME=acme-exit TS_HOSTNAME=acme-exit ./up.sh`.

## 5. Check that it works

```bash
docker logs acme-exit
# BaaS exit node enrolled; wait until it shows as online in the BaaS Console.
# (after a restart: BaaS exit node reconnected with its saved identity.)

docker inspect -f '{{.State.Health.Status}}' acme-exit     # healthy (after about 30 s)
```

`docker logs` stays short on purpose: the start script prints only these lines and its own errors, never the key.

Then, from any machine where you use bcli:

```bash
bcli exit-node list            # acme-exit   online   (can take up to a minute)
bcli tenant                    # Default exit: acme-exit
bcli session create --wait     # works again; open the view_url and visit a "what is my IP" page
```

In the console, **Exit nodes** shows `acme-exit` as **online**. The IP that websites see in a session is the public
IP of the exit node's network (on the exit node's host: `curl -s https://api.ipify.org`).

If `acme-exit` is online but your tenant's default exit is still another name, ask your servas.ai contact to set it.
Only the operator can change the default exit, and only to a node that is online.

## What the exit node can and cannot see

What it does:

- It joins the servas.ai overlay network (Tailscale) as an exit node of **your tenant only**. The one-time key is bound
  to your tenant's exit tag; the API only accepts an exit node of your own tenant (another tenant's node gives
  `exit_node_unavailable`).
- It forwards the internet traffic of your tenant's browser sessions. Only your tenant's sessions are allowed to use
  it as exit node (network policy of the operator).
- Like any router, it sees which addresses and ports the sessions connect to and how much traffic flows. Page content
  stays encrypted when the site uses HTTPS.

What it does not do (enforced inside the container by `entrypoint.sh`, in addition to the network policy):

- **Kill switch on the session side.** Sessions use only this node. If you stop it, the browsers of running sessions
  lose internet access until it is back (no fallback route), and new sessions are refused.
- **No access to your LAN.** Session traffic to private and special address ranges is dropped: `10.0.0.0/8`,
  `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`, `169.254.0.0/16`, `127.0.0.0/8`, `0.0.0.0/8`, multicast, and
  for IPv6 `fc00::/7`, `fe80::/10`, `ff00::/8`, `::1`. There is no switch to allow it. Public addresses are reachable,
  as from any machine on that internet connection.
- **No connections into the overlay network.** The node cannot open connections to other devices there (the
  network policy gives the exit tag no access at all), and new connections from the overlay network to the node itself
  are dropped. No SSH, no remote shell.
- It does not use routes or DNS settings pushed by the network (`--accept-routes=false`, `--accept-dns=false`).
- It runs in its own network namespace (Docker bridge), not in the host network, and changes nothing on the host.
  The rest of your host's traffic does not go through it.

What the operator sees: the device in their overlay network (name, overlay IP, public IP, last seen, online state).
What the node sees of the network: its peer list (`tailscale status` inside the container) shows the devices that may
talk to it, that is your tenant's browser sessions and the operator's administration devices, by name. It cannot
connect to any of them.

## Stop, remove, enroll again

```bash
docker stop acme-exit                 # pause: new sessions fail with exit_node_unavailable until you start it
docker start acme-exit                # back, no key needed

docker rm -f acme-exit                # remove the container; the identity stays in the volume
docker volume rm acme-exit-state      # forget the identity (Compose: docker compose down -v)
```

**Rotate / enroll again** (new machine, lost volume, or you want a fresh identity):

1. `docker rm -f acme-exit && docker volume rm acme-exit-state` on the old machine (never run two nodes from the
   same volume at the same time).
2. Issue a new one-time key in the console. Issuing a key removes your tenant's **offline** exit nodes from the
   network, so the new node gets the old name again.
3. Put the key into `exit.env` and start again (step 4).

Unused keys expire after their lifetime. **Valid keys** in the console lists them; **Revoke** invalidates a key that
was not used yet. Revoking does not remove a node that already enrolled with it: stop the container and delete its
volume, then tell your servas.ai contact if the node should also be removed from the network right away (otherwise it
is removed with your next key).

## Troubleshooting

**`code=exit_node_unavailable: exit node is unavailable or belongs to another tenant`** on `bcli session create`
(exit code 1, no session id). The tenant's exit node is not running or not reachable. Check `bcli tenant` (which name
is the default), `bcli exit-node list` (is that name `online`?) and `docker logs <name>` on the exit node's host.
Start it again (`docker start <name>`), or set it up as above. Sessions never fall back to another route.

**`code=exit_node_required`**: your tenant has no default exit and you did not pick one. Ask your servas.ai contact.

**The node is online, but under another name** (for example `acme-exit-1`): an older node with the same name was
still registered. Remove the container and volume, issue a new key (this removes offline nodes of your tenant) and
start again.

**`not enrolled yet: TS_AUTHKEY (one-time exit key) is required`**: first start without a key, or the volume was
deleted. Issue a key and put it into `exit.env`.

**`exit-node enrollment failed; issue a fresh one-time key`**: the key expired (10 minutes), was already used or was
revoked. Issue a new one.

**`/dev/net/tun is required`**: the container was started without `--device=/dev/net/tun`, or the host has no TUN
device (some container-in-container setups).

**Console says "The tenant network is not ready yet"**: your tenant is not fully set up; ask your servas.ai contact.
