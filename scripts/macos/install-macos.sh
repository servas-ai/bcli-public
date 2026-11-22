#!/bin/bash
# User-only LaunchAgents. See Apple's launchd.plist(5) and launchctl(1).
# Source: https://github.com/apple-oss-distributions/launchd/tree/main/man
set -euo pipefail
umask 077

die() { printf 'install-macos: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: scripts/install-macos.sh --bin /absolute/bcli-darwin-arm64 --browser /absolute/CloakBrowser [--dry-run]
       scripts/install-macos.sh --uninstall [--dry-run]
Installs the full CLI into $HOME/.local/bin/bcli and two user LaunchAgents.
Run as the logged-in Apple-chip macOS user, without sudo. No accounts are created.
--dry-run prints both plists and performs no writes or launchctl calls.
--uninstall unloads/removes only these two LaunchAgents; binaries and state are kept.
USAGE
}

BINARY='' BROWSER='' DRY=0 UNINSTALL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin) [ "$#" -ge 2 ] || die '--bin needs a path'; BINARY=$2; shift 2 ;;
    --browser) [ "$#" -ge 2 ] || die '--browser needs a path'; BROWSER=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# Reject control characters rather than embedding them in XML or diagnostics.
valid_absolute() {
  case "$1" in /*) ;; *) die 'all paths must be absolute' ;; esac
  # [[:cntrl:]], not a \001-\037 range: macOS /bin/bash 3.2 ignores such
  # ranges under a UTF-8 locale and accepted newlines (DKS-572).
  case "$1" in *[[:cntrl:]]*) die 'control characters are not allowed in paths' ;; esac
}
[ -n "${HOME:-}" ] || die 'HOME is required'
valid_absolute "$HOME"
USER_HOME=${HOME%/}
[ -n "$USER_HOME" ] || die 'HOME must not be /'
AGENTS="$USER_HOME/Library/LaunchAgents"
STATE="$USER_HOME/.bcli"
DEST="$USER_HOME/.local/bin/bcli"
DOMAIN="gui/$(id -u)"
DAEMON=ai.servas.bcli.daemon
BRIDGE=ai.servas.bcli.bwbridge

xml() {
  local value=$1
  value=${value//&/\&amp;}
  value=${value//</\&lt;}
  value=${value//>/\&gt;}
  value=${value//\"/\&quot;}
  value=${value//\'/\&apos;}
  printf '%s' "$value"
}

plist() {
  local label=$1 command=$2
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/env</string><string>-i</string>
    <string>HOME=$(xml "$USER_HOME")</string>
    <string>PATH=$(xml "$USER_HOME/.local/bin"):/usr/bin:/bin:/usr/sbin:/sbin</string>
    <string>BCLI_HOME=$(xml "$STATE")</string>
    <string>BWBRIDGE_SOCK=$(xml "$STATE/bwbridge.sock")</string>
    <string>BCLI_NO_AUTO_UPDATE=1</string>
    <string>BAAS_BROWSER_PATH=$(xml "$BROWSER")</string>
    <string>BAAS_FINGERPRINT_PLATFORM=macos</string>
    <string>$(xml "$DEST")</string><string>$command</string><string>run</string>
  </array>
  <key>WorkingDirectory</key><string>$(xml "$STATE")</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>AbandonProcessGroup</key><false/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ExitTimeOut</key><integer>30</integer>
  <key>Umask</key><integer>63</integer>
  <key>SoftResourceLimits</key><dict><key>Core</key><integer>0</integer></dict>
  <key>HardResourceLimits</key><dict><key>Core</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
}

if [ "$UNINSTALL" = 1 ]; then
  [ -z "$BINARY$BROWSER" ] || die '--uninstall does not accept --bin or --browser'
else
  [ -n "$BINARY" ] && [ -n "$BROWSER" ] || { usage >&2; exit 2; }
  valid_absolute "$BINARY"
  valid_absolute "$BROWSER"
fi

if [ "$DRY" = 1 ]; then
  if [ "$UNINSTALL" = 1 ]; then
    printf 'Would unload/remove only %s and %s from %s. State and binaries are kept.\n' "$DAEMON" "$BRIDGE" "$AGENTS"
  else
    plist "$DAEMON" daemon
    printf '\n'
    plist "$BRIDGE" bwbridge
  fi
  exit 0
fi

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || die 'installation requires Apple-chip macOS'
[ "$(id -u)" != 0 ] || die 'run as the logged-in user, without sudo'
safe_mode() {
  local mode
  mode=$(stat -f '%Lp' "$1") || die 'cannot check installation directory permissions'
  (( (8#$mode & 022) == 0 )) || die 'installation directories must not be writable by other users'
}
[ -d "$USER_HOME" ] && [ -O "$USER_HOME" ] && [ ! -L "$USER_HOME" ] || die 'HOME must be an owned directory, not a symlink'
safe_mode "$USER_HOME"
# A missing GUI domain means there is no logged-in user session to show approvals.
/bin/launchctl print "$DOMAIN" >/dev/null 2>&1 || die 'log into the macOS graphical session before installing'

# Unload only our exact labels; do not infer ownership from a filename glob.
unload() {
  if /bin/launchctl print "$DOMAIN/$1" >/dev/null 2>&1; then
    /bin/launchctl bootout "$DOMAIN/$1" || die 'could not unload the existing LaunchAgent'
  fi
  # bootout can return while launchd is still tearing the job down (up to its
  # ExitTimeOut of 30 s); an immediate bootstrap then fails with
  # "5: Input/output error" and leaves no job loaded (DKS-572 MacBook).
  local waited=0
  while /bin/launchctl print "$DOMAIN/$1" >/dev/null 2>&1; do
    [ "$waited" -lt 70 ] || die 'existing LaunchAgent did not unload within 35 seconds'
    sleep 0.5
    waited=$((waited + 1))
  done
}
if [ "$UNINSTALL" = 1 ]; then
  for dir in "$USER_HOME/Library" "$AGENTS"; do
    [ ! -L "$dir" ] || die 'refusing a symlinked LaunchAgent directory'
    if [ -e "$dir" ]; then
      [ -d "$dir" ] && [ -O "$dir" ] || die 'LaunchAgent directory must be owned by this user'
      safe_mode "$dir"
    fi
  done
  for label in "$DAEMON" "$BRIDGE"; do
    path="$AGENTS/$label.plist"
    [ ! -L "$path" ] || die 'refusing symlinked LaunchAgent'
    [ ! -e "$path" ] || [ -O "$path" ] || die 'LaunchAgent is not owned by this user'
    unload "$label"
    [ ! -e "$path" ] || rm "$path"
  done
  printf 'bcli LaunchAgents removed. Binaries and private state were kept.\n'
  exit 0
fi

[ -f "$BINARY" ] && [ -x "$BINARY" ] || die '--bin must name an executable full bcli'
[ -f "$BROWSER" ] && [ -x "$BROWSER" ] || die '--browser must name an executable CloakBrowser'
# Check capability before replacing a working installation. Help/version must not
# trigger an account login, browser, dialog or an automatic update.
/usr/bin/env -i HOME="$USER_HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin BCLI_NO_AUTO_UPDATE=1 "$BINARY" daemon run --help >/dev/null || die 'binary lacks the local daemon'
/usr/bin/env -i HOME="$USER_HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin BCLI_NO_AUTO_UPDATE=1 "$BINARY" bwbridge run --help >/dev/null || die 'binary lacks the Bitwarden bridge'

# Every ancestor is checked before mkdir/copy: reject symlinks and foreign-owned
# directories instead of following them to another installation.
owned_dir() {
  [ ! -L "$1" ] || die 'refusing a symlinked installation directory'
  if [ -e "$1" ]; then
    [ -d "$1" ] && [ -O "$1" ] || die 'installation directory must be owned by this user'
  else
    mkdir "$1"
  fi
  safe_mode "$1"
}
for dir in "$USER_HOME/Library" "$AGENTS" "$USER_HOME/.local" "$USER_HOME/.local/bin" "$STATE"; do
  owned_dir "$dir"
done
chmod 700 "$STATE"
[ ! -L "$DEST" ] || die 'refusing a symlinked bcli destination'
[ ! -e "$DEST" ] || { [ -f "$DEST" ] && [ -O "$DEST" ]; } || die 'bcli destination is not an owned regular file'
for label in "$DAEMON" "$BRIDGE"; do
  path="$AGENTS/$label.plist"
  [ ! -L "$path" ] || die 'refusing a symlinked LaunchAgent'
  [ ! -e "$path" ] || { [ -f "$path" ] && [ -O "$path" ]; } || die 'LaunchAgent is not an owned regular file'
done

# Prepare all replacements before stopping the old services. temp names remain
# inside their destination directory, so each rename is atomic.
BINARY_TMP=$(mktemp "$USER_HOME/.local/bin/.bcli.XXXXXX")
DAEMON_TMP=$(mktemp "$AGENTS/.bcli-daemon.XXXXXX")
BRIDGE_TMP=$(mktemp "$AGENTS/.bcli-bwbridge.XXXXXX")
trap 'rm -f "$BINARY_TMP" "$DAEMON_TMP" "$BRIDGE_TMP"' EXIT
cp "$BINARY" "$BINARY_TMP"
chmod 700 "$BINARY_TMP"
plist "$DAEMON" daemon >"$DAEMON_TMP"
plist "$BRIDGE" bwbridge >"$BRIDGE_TMP"
/usr/bin/plutil -lint "$DAEMON_TMP" "$BRIDGE_TMP" >/dev/null
unload "$DAEMON"
unload "$BRIDGE"
mv "$BINARY_TMP" "$DEST"
mv "$DAEMON_TMP" "$AGENTS/$DAEMON.plist"
mv "$BRIDGE_TMP" "$AGENTS/$BRIDGE.plist"
for label in "$BRIDGE" "$DAEMON"; do
  /bin/launchctl bootstrap "$DOMAIN" "$AGENTS/$label.plist"
  /bin/launchctl kickstart "$DOMAIN/$label"
done
printf 'bcli and its user LaunchAgents are installed. Use bcli daemon status to check readiness.\n'
