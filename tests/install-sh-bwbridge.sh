#!/bin/sh
# shellcheck disable=SC2034 # OS, NO_BWBRIDGE, AA_* are read by the sourced install.sh functions
# Checks the Bitwarden part of install.sh (setup_bitwarden, setup_apparmor) with a fake bcli,
# systemctl, launchctl, sudo, apparmor_parser and ldconfig. Writes only below a temp directory.
#
#   sh tests/install-sh-bwbridge.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
lib=$(mktemp)
sed '$d' "$here/../install.sh" >"$lib"   # all functions, without the final main call
# shellcheck disable=SC1090
. "$lib"
rm -f "$lib"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
fail=0
fakebin="$base/bin"
mkdir -p "$fakebin"
LOG="$base/log"
export LOG

cat >"$fakebin/bcli" <<'EOF'
#!/bin/sh
echo "bcli $*" >>"$LOG"
case "$*" in
  "bwbridge status --help") [ "${OLD:-0}" = 0 ] ;;
  "bwbridge apparmor") echo "profile bcli-prompt {}" ;;
  "bwbridge start --restart") [ "${START_RC:-0}" = 0 ] || { echo "start failed: no manager" >&2; exit 1; } ;;
  *) exit 2 ;;
esac
EOF
cat >"$fakebin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$LOG"; exit "${SD_RC:-0}"
EOF
cat >"$fakebin/launchctl" <<'EOF'
#!/bin/sh
echo "launchctl $*" >>"$LOG"; exit "${LC_RC:-0}"
EOF
cat >"$fakebin/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >>"$LOG"
[ "${SUDO_RC:-0}" = 0 ] || exit 1
[ "$1" = -n ] && shift
[ "$1" = true ] && exit 0
exec "$@"
EOF
cat >"$fakebin/apparmor_parser" <<'EOF'
#!/bin/sh
echo "apparmor_parser $*" >>"$LOG"
EOF
cat >"$fakebin/ldconfig" <<'EOF'
#!/bin/sh
[ "${WEBKIT:-1}" = 1 ] && echo "	libwebkit2gtk-4.1.so.0 (libc6,x86-64) => /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0"
exit 0
EOF
chmod +x "$fakebin"/*
PATH="$fakebin:$PATH"

run() { # run NAME — runs setup_bitwarden with the current settings, output in $base/out
  : >"$LOG"
  tmp="$base/tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
  AA_SYSCTL="$base/sysctl"; AA_PROFILE="$base/aa/bcli-prompt"
  setup_bitwarden "$fakebin/bcli" >"$base/out" 2>&1
}
expect() { # expect LABEL grep-pattern FILE
  if grep -q -- "$2" "$3"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s (no "%s" in %s)\n' "$1" "$2" "$3"; cat "$3"; fail=1; fi
}
reject() {
  if grep -q -- "$2" "$3"; then printf 'FAIL  %s ("%s" in %s)\n' "$1" "$2" "$3"; cat "$3"; fail=1; else printf 'ok    %s\n' "$1"; fi
}

reset() { OS=linux NO_BWBRIDGE=0; export DISPLAY=:0 WAYLAND_DISPLAY='' SUDO_RC=0 SD_RC=0 LC_RC=0 WEBKIT=1 OLD=0 START_RC=0; }
reset
mkdir -p "$base/aa"
echo 1 >"$base/sysctl"

reset; export SUDO_RC=0; run
expect "ubuntu+sudo: profile installed" "apparmor_parser -r $base/aa/bcli-prompt" "$LOG"
expect "ubuntu+sudo: profile content" "profile bcli-prompt" "$base/aa/bcli-prompt"
expect "ubuntu+sudo: bridge started" "bcli bwbridge start --restart" "$LOG"
expect "ubuntu+sudo: says running" "bcli-bwbridge.service" "$base/out"

reset; export SUDO_RC=0; run
reject "profile current: not reinstalled" "apparmor_parser" "$LOG"
expect "profile current: reported" "profile bcli-prompt is installed" "$base/out"

rm -f "$base/aa/bcli-prompt"
reset; export SUDO_RC=1; run
reject "no sudo: nothing written" "apparmor_parser" "$LOG"
expect "no sudo: prints command" "sudo tee /etc/apparmor.d/bcli-prompt" "$base/out"
expect "no sudo: bridge still started" "bcli bwbridge start --restart" "$LOG"

echo 0 >"$base/sysctl"
reset; run
reject "no userns restriction: no AppArmor" "bwbridge apparmor" "$LOG"

reset; export WEBKIT=0; run
expect "no WebKitGTK: hint" "libwebkit2gtk-4.1-0" "$base/out"

reset; export DISPLAY=''; run
reject "no display: no start" "bwbridge start" "$LOG"
expect "no display: hint" "in a terminal of your desktop run: bcli bwbridge start" "$base/out"

reset; export SD_RC=1; run
reject "no user manager: no start" "bwbridge start" "$LOG"

reset; NO_BWBRIDGE=1; run
reject "--no-bwbridge: no start" "bwbridge start" "$LOG"
expect "--no-bwbridge: hint" "skipped (--no-bwbridge)" "$base/out"

reset; export OLD=1; run
reject "old release: nothing" "bwbridge start" "$LOG"
[ -s "$base/out" ] && { echo "FAIL  old release printed output"; fail=1; } || echo "ok    old release: silent"

reset; export START_RC=1; run || { echo "FAIL  start failure failed the install"; fail=1; }
expect "start failure: shown" "start failed: no manager" "$base/out"
expect "start failure: retry hint" "retry in a desktop terminal" "$base/out"

reset; OS=darwin; run
reject "macOS: no AppArmor" "bwbridge apparmor" "$LOG"
expect "macOS: bridge started" "bcli bwbridge start --restart" "$LOG"
expect "macOS: says LaunchAgent" "ai.servas.bcli.bwbridge" "$base/out"
reset; OS=darwin; export LC_RC=1; run
reject "macOS without GUI session: no start" "bwbridge start" "$LOG"

if [ "$fail" = 0 ]; then echo "install.sh Bitwarden setup: all checks passed"; fi
exit "$fail"
