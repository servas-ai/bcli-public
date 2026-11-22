#!/bin/sh
# bcli installer for Linux and macOS (amd64, arm64).
#
#   curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh -s -- --version v0.14.0
#
# Downloads bcli from the GitHub releases of servas-ai/bcli-public, checks the Ed25519
# signature of SHA256SUMS against the servas.ai release key built into this script, checks
# the binary against SHA256SUMS, and installs it as "bcli". In a desktop session it then sets
# up the Bitwarden bridge as a per-user service ("bcli bwbridge start": systemd user unit on
# Linux, LaunchAgent on macOS) and, on Ubuntu 23.10+ when root or password-less sudo is
# available, the AppArmor profile of the approval window; otherwise it prints the command.
#
# Options:
#   --version vX.Y.Z   install this release (default: the latest release; env BCLI_VERSION)
#   --dir DIR          install into DIR (default: /usr/local/bin as root, else ~/.local/bin;
#                      env BCLI_INSTALL_DIR)
#   --dry-run          download and verify, print what would be installed, change nothing
#   --no-bwbridge      do not set up the Bitwarden bridge service (env BCLI_NO_BWBRIDGE=1)
#   --insecure-skip-signature
#                      skip the signature check when no verifier is available (not
#                      recommended: the checksum then only proves the download is complete)
#   -h, --help         this text
#
# Signature check, first tool that works: OpenSSL 3, python3, or bc (POSIX). The script
# stops before installing anything if the signature or a checksum does not match.
# Besides the install directory and a temporary directory, only the bridge service
# (~/.config/systemd/user/bcli-bwbridge.service or ~/Library/LaunchAgents/ai.servas.bcli.bwbridge.plist,
# both removed by "bcli uninstall") and, with root rights, /etc/apparmor.d/bcli-prompt are written.

set -eu

REPO="servas-ai/bcli-public"
# servas.ai CLI release key (Ed25519), = keys/bcli-release-ed25519.pem in servas-ai/bcli-public.
KEY_B64="fUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E="
KEY_PEM="-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAfUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E=
-----END PUBLIC KEY-----"

say() { printf '%s\n' "$*" >&2; }
die() { say "bcli install: $*"; exit 1; }

usage() {
  cat >&2 <<'EOF'
bcli installer for Linux and macOS.
  curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh -s -- [options]
Options:
  --version vX.Y.Z   install this release (default: latest; env BCLI_VERSION)
  --dir DIR          install directory (default: /usr/local/bin as root, else ~/.local/bin;
                     env BCLI_INSTALL_DIR)
  --dry-run          download and verify only, change nothing
  --no-bwbridge      skip the Bitwarden bridge service (env BCLI_NO_BWBRIDGE=1)
  --insecure-skip-signature
                     install even when no Ed25519 verifier is available (not recommended)
EOF
}

# ---------------------------------------------------------------------------------------
# small portable helpers

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # fetch URL FILE
  if have curl; then
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --retry 3 \
      --connect-timeout 20 --output "$2" "$1" </dev/null
  elif have wget; then
    wget --quiet --https-only --tries=3 --output-document="$2" "$1" </dev/null
  else
    die "neither curl nor wget found"
  fi
}

sha256_of() { # sha256_of FILE -> hex
  if have sha256sum; then sha256sum "$1" </dev/null | cut -d' ' -f1
  elif have shasum; then shasum -a 256 "$1" </dev/null | cut -d' ' -f1
  elif have openssl; then openssl dgst -sha256 "$1" </dev/null | sed 's/^.*= *//'
  else die "no SHA-256 tool (sha256sum, shasum or openssl) found"
  fi
}

sha512_of() { # sha512_of FILE -> hex
  if have sha512sum; then sha512sum "$1" </dev/null | cut -d' ' -f1
  elif have shasum; then shasum -a 512 "$1" </dev/null | cut -d' ' -f1
  elif have openssl; then openssl dgst -sha512 "$1" </dev/null | sed 's/^.*= *//'
  else return 1
  fi
}

b64_to_hex() { # b64_to_hex STRING -> lowercase hex (awk, no base64 tool needed)
  printf '%s\n' "$1" | awk '
    BEGIN { a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            for (i = 0; i < 64; i++) v[substr(a, i + 1, 1)] = i }
    { s = s $0 }
    END {
      gsub(/[^A-Za-z0-9+\/]/, "", s)
      bits = 0; acc = 0; out = ""
      for (i = 1; i <= length(s); i++) {
        acc = acc * 64 + v[substr(s, i, 1)]; bits += 6
        if (bits >= 8) { bits -= 8; b = int(acc / 2 ^ bits); acc -= b * 2 ^ bits; out = out sprintf("%02x", b) }
      }
      print out
    }'
}

hex_to_file() { # hex_to_file HEX FILE  (printf octal escapes; POSIX)
  _fmt=$(printf '%s\n' "$1" | awk '{
      for (i = 1; i < length($0); i += 2) {
        h = substr($0, i, 2); n = 0
        for (j = 1; j <= 2; j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
        printf "\\%03o", n
      } }')
  # shellcheck disable=SC2059 # the format is the data, made of octal escapes only
  printf "$_fmt" >"$2"
}

le_hex() { # le_hex HEX -> the byte-reversed hex in upper case (little-endian integer for bc)
  printf '%s\n' "$1" | awk '{ o = ""; for (i = length($0) - 1; i >= 1; i -= 2) o = o substr($0, i, 2); print toupper(o) }'
}

# ---------------------------------------------------------------------------------------
# Ed25519 verification (RFC 8032). verify_* KEYHEX SIGHEX MSGFILE -> exit 0 valid, 1 invalid,
# 2 tool not usable here. Cofactorless check as Go crypto/ed25519: encode([S]B - [h]A) == R.

verify_openssl() {
  have openssl || return 2
  printf '%s\n' "$KEY_PEM" >"$tmp/key.pem"
  hex_to_file "$2" "$tmp/sig.bin"
  if openssl pkeyutl -verify -pubin -inkey "$tmp/key.pem" -rawin -in "$3" -sigfile "$tmp/sig.bin" \
       </dev/null >"$tmp/openssl.err" 2>&1; then
    return 0
  fi
  # OpenSSL 3 says "Signature Verification Failure" for a bad signature; anything else
  # (LibreSSL on macOS, OpenSSL 1.x: no Ed25519 / no -rawin) means the tool cannot check.
  if grep -q 'Signature Verification Failure' "$tmp/openssl.err"; then return 1; fi
  return 2
}

verify_python() {
  py=""
  for c in python3 python; do
    if have "$c"; then py=$c; break; fi
  done
  [ -n "$py" ] || return 2
  # Stock macOS without the Command Line Tools has a python3 stub that opens an install
  # dialog: use it only when the tools are there.
  if [ "$OS" = darwin ] && [ "$(command -v "$py")" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then
    return 2
  fi
  "$py" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' </dev/null 2>/dev/null || return 2
  "$py" -I - "$1" "$2" "$3" <<'PY' && return 0
import hashlib, sys
p = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
def inv(x): return pow(x, p - 2, p)
d = -121665 * inv(121666) % p
I = pow(2, (p - 1) // 4, p)
def xrec(y, sign):
    xx = (y * y - 1) * inv(d * y * y + 1) % p
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p: x = x * I % p
    if (x * x - xx) % p: return None
    if x == 0 and sign: return None
    return p - x if x & 1 != sign else x
def add(P, Q):
    X1, Y1, Z1, T1 = P; X2, Y2, Z2, T2 = Q
    A = (Y1 - X1) * (Y2 - X2) % p; B = (Y1 + X1) * (Y2 + X2) % p
    C = T1 * 2 * d * T2 % p; D = Z1 * 2 * Z2 % p
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % p, G * H % p, F * G % p, E * H % p)
def mul(s, P):
    Q = (0, 1, 1, 0)
    while s:
        if s & 1: Q = add(Q, P)
        P = add(P, P); s >>= 1
    return Q
key, sig, msg = bytes.fromhex(sys.argv[1]), bytes.fromhex(sys.argv[2]), open(sys.argv[3], "rb").read()
if len(key) != 32 or len(sig) != 64: sys.exit(3)
ay = int.from_bytes(key, "little"); asign = ay >> 255; ay &= (1 << 255) - 1
ax = xrec(ay, asign) if ay < p else None
S = int.from_bytes(sig[32:], "little")
if ax is None or S >= L: sys.exit(3)
by = 4 * inv(5) % p; bx = xrec(by, 0)
h = int.from_bytes(hashlib.sha512(sig[:32] + key + msg).digest(), "little") % L
X, Y, Z, _ = add(mul(S, (bx, by, 1, bx * by % p)), mul(h, (p - ax, ay, 1, (p - ax) * ay % p)))
zi = inv(Z); x, y = X * zi % p, Y * zi % p
sys.exit(0 if (y | (x & 1) << 255).to_bytes(32, "little") == sig[:32] else 3)
PY
  [ $? = 3 ] && return 1
  return 2
}

verify_bc() {
  have bc || return 2
  # h = SHA-512(R || A || M) mod L, computed outside bc.
  hex_to_file "$(printf '%s' "$2" | cut -c1-64)$1" "$tmp/ram"
  cat "$3" >>"$tmp/ram"
  hh=$(sha512_of "$tmp/ram") || return 2
  [ "${#hh}" = 128 ] || return 2
  ka=$(le_hex "$1"); ra=$(le_hex "$(printf '%s' "$2" | cut -c1-64)")
  sa=$(le_hex "$(printf '%s' "$2" | cut -c65-128)"); ha=$(le_hex "$hh")
  out=$(bc <<BC 2>/dev/null
scale = 0
p = 2^255 - 19
l = 2^252 + 27742317777372353535851937790883648493
define m(a) { auto r; r = a % p; if (r < 0) r = r + p; return (r); }
define pw(b, e) { auto r; r = 1; b = m(b); while (e > 0) { if (e % 2 == 1) r = (r * b) % p; b = (b * b) % p; e = e / 2; }; return (r); }
define inv(x) { return (pw(x, p - 2)); }
dc = m(-121665 * inv(121666))
sq = pw(2, (p - 1) / 4)
ok = 1
define xrec(y, s) {
  auto xx, x
  xx = m((y * y - 1) * inv(dc * y * y + 1))
  x = pw(xx, (p + 3) / 8)
  if (m(x * x - xx) != 0) x = m(x * sq)
  if (m(x * x - xx) != 0) { ok = 0; return (0); }
  if (x == 0) { if (s == 1) { ok = 0; return (0); } }
  if (x % 2 != s) x = p - x
  return (x)
}
define ad(a1, b1, c1, d1, a2, b2, c2, d2) {
  auto a, b, c, dd, e, f, g, h
  a = m((b1 - a1) * (b2 - a2)); b = m((b1 + a1) * (b2 + a2))
  c = m(d1 * 2 * dc * d2); dd = m(c1 * 2 * c2)
  e = b - a; f = dd - c; g = dd + c; h = b + a
  rx = m(e * f); ry = m(g * h); rz = m(f * g); rt = m(e * h)
  return (0)
}
define sm(s, a1, b1, c1, d1) {
  auto qa, qb, qc, qd, j
  qa = 0; qb = 1; qc = 1; qd = 0
  while (s > 0) {
    if (s % 2 == 1) { j = ad(qa, qb, qc, qd, a1, b1, c1, d1); qa = rx; qb = ry; qc = rz; qd = rt; }
    j = ad(a1, b1, c1, d1, a1, b1, c1, d1); a1 = rx; b1 = ry; c1 = rz; d1 = rt
    s = s / 2
  }
  rx = qa; ry = qb; rz = qc; rt = qd
  return (0)
}
ibase = 16
ky = $ka
rr = $ra
ss = $sa
hh = $ha
ibase = A
t = 2^255
as = ky / t; ay = ky % t
rs = rr / t; ry0 = rr % t
res = 0
if (ay < p) { if (ss < l) {
  ax = xrec(ay, as)
  if (ok == 1) {
    by = m(4 * inv(5)); bx = xrec(by, 0)
    h = hh % l
    j = sm(ss, bx, by, 1, m(bx * by)); sx = rx; sy = ry; sz = rz; st = rt
    j = sm(h, p - ax, ay, 1, m((p - ax) * ay))
    j = ad(sx, sy, sz, st, rx, ry, rz, rt)
    zi = inv(rz); fx = m(rx * zi); fy = m(ry * zi)
    if (fy == ry0) { if (fx % 2 == rs) res = 1; }
  }
} }
res
BC
) || return 2
  case "$out" in
    1) return 0 ;;
    0) return 1 ;;
    *) return 2 ;;
  esac
}

# RFC 8032 section 7.1, test 2 (message 0x72): a verifier must accept this and reject the
# same signature over another message ("x") before its verdict counts.
T_KEY=3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c
T_SIG=92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00

verify_signature() { # verify_signature MSGFILE SIGFILE -> 0 ok; dies on a bad signature
  sig_hex=$(b64_to_hex "$(cat "$2")")
  [ "${#sig_hex}" = 128 ] || die "SHA256SUMS.sig is not a base64 Ed25519 signature"
  key_hex=$(b64_to_hex "$KEY_B64")
  printf r >"$tmp/t2"; printf x >"$tmp/x"
  for tool in openssl python bc; do
    if [ "$tool" = openssl ]; then
      # OpenSSL reads the key from a PEM; build one for the test key (SPKI prefix + raw key).
      T_PEM="-----BEGIN PUBLIC KEY-----
$(hex_to_file "302a300506032b6570032100$T_KEY" "$tmp/tk.der"; openssl base64 -A -in "$tmp/tk.der" 2>/dev/null </dev/null || true)
-----END PUBLIC KEY-----"
      SAVED_PEM=$KEY_PEM; KEY_PEM=$T_PEM
      r1=0; verify_openssl "$T_KEY" "$T_SIG" "$tmp/t2" || r1=$?
      r2=0; verify_openssl "$T_KEY" "$T_SIG" "$tmp/x" || r2=$?
      KEY_PEM=$SAVED_PEM
    else
      r1=0; "verify_$tool" "$T_KEY" "$T_SIG" "$tmp/t2" || r1=$?
      r2=0; "verify_$tool" "$T_KEY" "$T_SIG" "$tmp/x" || r2=$?
    fi
    [ "$r1" = 0 ] && [ "$r2" = 1 ] || continue
    rc=0; "verify_$tool" "$key_hex" "$sig_hex" "$1" || rc=$?
    case $rc in
      0) say "  signature  OK (Ed25519, servas.ai release key, checked with $tool)"; return 0 ;;
      1) die "SIGNATURE INVALID: SHA256SUMS of $VERSION is not signed by the servas.ai release key. Nothing was installed." ;;
    esac
  done
  if [ "$SKIP_SIG" = 1 ]; then
    say "  signature  NOT CHECKED (--insecure-skip-signature): the checksum below only proves the download is complete"
    return 0
  fi
  die "cannot check the Ed25519 signature on this machine: no OpenSSL 3, python3 or bc found.
  Install one of them and run the installer again (e.g. apt install openssl, dnf install openssl,
  brew install openssl@3), or install with Homebrew: brew install servas-ai/tap/bcli.
  Nothing was installed. (--insecure-skip-signature skips this check; not recommended.)"
}

# ---------------------------------------------------------------------------------------
# Bitwarden bridge (optional; never fails the install). "bcli bwbridge start" writes and starts
# the per-user service and is idempotent; older releases without it are skipped.

bw_note() { say "  bitwarden  $*"; }
AA_SYSCTL=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
AA_PROFILE=/etc/apparmor.d/bcli-prompt

setup_apparmor() { # setup_apparmor BCLI
  # Ubuntu 23.10+ confines unprivileged user namespaces; the WebKitGTK sandbox of the approval
  # window needs the bcli-prompt profile. Debian, Fedora, Ubuntu <= 23.04 and 26.04 do not.
  [ "$(cat "$AA_SYSCTL" 2>/dev/null)" = 1 ] || return 0
  "$1" bwbridge apparmor >"$tmp/bcli-prompt.aa" 2>/dev/null </dev/null || return 0
  if [ -f "$AA_PROFILE" ] && cmp -s "$tmp/bcli-prompt.aa" "$AA_PROFILE"; then
    bw_note "AppArmor profile bcli-prompt is installed"
    return 0
  fi
  sudo_cmd=""
  if [ "$(id -u)" = 0 ]; then sudo_cmd=" "
  elif have sudo && sudo -n true </dev/null >/dev/null 2>&1; then sudo_cmd="sudo -n"
  fi
  # apparmor_parser lives in /sbin, which a normal user's PATH often lacks.
  aa_bin=$(command -v apparmor_parser 2>/dev/null || true)
  for c in /usr/sbin/apparmor_parser /sbin/apparmor_parser; do
    if [ -z "$aa_bin" ] && [ -x "$c" ]; then aa_bin=$c; fi
  done
  if [ -n "$sudo_cmd" ] && [ -n "$aa_bin" ] &&
     $sudo_cmd install -m 644 "$tmp/bcli-prompt.aa" "$AA_PROFILE" </dev/null &&
     $sudo_cmd "$aa_bin" -r "$AA_PROFILE" </dev/null >/dev/null 2>&1; then
    bw_note "AppArmor profile bcli-prompt installed ($AA_PROFILE)"
    return 0
  fi
  say ""
  say "This system restricts user namespaces with AppArmor (Ubuntu 23.10+). The Bitwarden approval"
  say "window needs this profile once (needs sudo):"
  say "  bcli bwbridge apparmor | sudo tee /etc/apparmor.d/bcli-prompt >/dev/null && sudo apparmor_parser -r /etc/apparmor.d/bcli-prompt"
  say ""
}

setup_bitwarden() { # setup_bitwarden BCLI
  # Releases before v0.14.5 have no bridge service on Linux and macOS.
  "$1" bwbridge status --help >/dev/null 2>&1 </dev/null || return 0
  if [ "$OS" = linux ]; then
    setup_apparmor "$1"
    if ! { ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null; } | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then
      bw_note "the approval window needs WebKitGTK 4.1 (Debian/Ubuntu: sudo apt install libwebkit2gtk-4.1-0)"
    fi
  fi
  if [ "$NO_BWBRIDGE" = 1 ]; then
    bw_note "bridge service skipped (--no-bwbridge); set it up later with: bcli bwbridge start"
    return 0
  fi
  if [ "$(id -u)" = 0 ]; then
    bw_note "the bridge is a per-user service: run 'bcli bwbridge start' as the desktop user"
    return 0
  fi
  desktop=0
  if [ "$OS" = darwin ]; then
    launchctl print "gui/$(id -u)" >/dev/null 2>&1 </dev/null && desktop=1
  elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && systemctl --user show-environment >/dev/null 2>&1 </dev/null; then
    desktop=1
  fi
  if [ "$desktop" = 0 ]; then
    bw_note "no desktop session here; in a terminal of your desktop run: bcli bwbridge start"
    return 0
  fi
  if out=$("$1" bwbridge start --restart </dev/null 2>&1); then
    if [ "$OS" = darwin ]; then
      bw_note "bridge running (LaunchAgent ai.servas.bcli.bwbridge, starts at login)"
    else
      bw_note "bridge running (systemd user unit bcli-bwbridge.service, starts at desktop login)"
    fi
    bw_note "set up your Bitwarden account: bcli vault bw setup   (remove: bcli bwbridge remove)"
  else
    printf '%s\n' "$out" | sed 's/^/  bitwarden  /' >&2
    bw_note "bridge not started; retry in a desktop terminal: bcli bwbridge start"
  fi
}

# ---------------------------------------------------------------------------------------

main() {
  VERSION=${BCLI_VERSION:-}
  DIR=${BCLI_INSTALL_DIR:-}
  DRY=0
  SKIP_SIG=0
  NO_BWBRIDGE=${BCLI_NO_BWBRIDGE:-0}
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a value"; VERSION=$2; shift 2 ;;
      --version=*) VERSION=${1#*=}; shift ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a value"; DIR=$2; shift 2 ;;
      --dir=*) DIR=${1#*=}; shift ;;
      --dry-run) DRY=1; shift ;;
      --no-bwbridge) NO_BWBRIDGE=1; shift ;;
      --insecure-skip-signature) SKIP_SIG=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option $1 (see --help)" ;;
    esac
  done

  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) die "on Windows use PowerShell: irm https://raw.githubusercontent.com/$REPO/main/install.ps1 | iex" ;;
    *) die "unsupported OS $(uname -s); bcli is built for Linux, macOS and Windows" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64|armv8*) ARCH=arm64 ;;
    *) die "unsupported CPU $(uname -m); bcli is built for amd64 (x86-64) and arm64" ;;
  esac
  # A shell running under Rosetta reports x86_64 on an Apple silicon Mac: take the native build.
  if [ "$OS" = darwin ] && [ "$ARCH" = amd64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    ARCH=arm64
  fi
  ASSET="bcli-$OS-$ARCH"

  if [ -z "$DIR" ]; then
    if [ "$(id -u)" = 0 ]; then DIR=/usr/local/bin; else DIR="$HOME/.local/bin"; fi
  fi

  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t bcli-install)
  trap 'rm -rf "$tmp"' EXIT INT TERM HUP

  if [ -z "$VERSION" ]; then
    fetch "https://github.com/$REPO/releases/latest/download/VERSION" "$tmp/VERSION" ||
      die "could not find the latest release of $REPO"
    VERSION="v$(tr -d ' \r\n' <"$tmp/VERSION")"
  fi
  case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
  printf '%s\n' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ||
    die "invalid version $VERSION (expected vX.Y.Z)"
  BASE="https://github.com/$REPO/releases/download/$VERSION"

  say "bcli $VERSION for $OS/$ARCH -> $DIR/bcli"
  fetch "$BASE/SHA256SUMS" "$tmp/SHA256SUMS" || die "release $VERSION not found ($BASE/SHA256SUMS)"
  fetch "$BASE/SHA256SUMS.sig" "$tmp/SHA256SUMS.sig" || die "SHA256SUMS.sig missing in release $VERSION"
  verify_signature "$tmp/SHA256SUMS" "$tmp/SHA256SUMS.sig"

  # The signed list names the version it belongs to (line "VERSION").
  fetch "$BASE/VERSION" "$tmp/VERSION" || die "VERSION missing in release $VERSION"
  want_v=$(awk '$2 == "VERSION" { print $1 }' "$tmp/SHA256SUMS")
  [ -n "$want_v" ] && [ "$(sha256_of "$tmp/VERSION")" = "$want_v" ] || die "VERSION does not match the signed SHA256SUMS"
  [ "v$(tr -d ' \r\n' <"$tmp/VERSION")" = "$VERSION" ] || die "release $VERSION carries version $(cat "$tmp/VERSION")"

  want=$(awk -v f="$ASSET" '$2 == f { print $1 }' "$tmp/SHA256SUMS")
  [ -n "$want" ] || die "$ASSET is not part of release $VERSION"
  say "  download   $ASSET"
  fetch "$BASE/$ASSET" "$tmp/$ASSET" || die "download of $ASSET failed"
  got=$(sha256_of "$tmp/$ASSET")
  [ "$got" = "$want" ] || die "CHECKSUM MISMATCH for $ASSET (got $got, want $want). Nothing was installed."
  say "  checksum   OK (sha256 $want)"

  if [ "$DRY" = 1 ]; then
    say "  dry run    would install $ASSET as $DIR/bcli; nothing changed"
    return 0
  fi

  mkdir -p "$DIR" || die "cannot create $DIR (use --dir, or run as root for /usr/local/bin)"
  [ -w "$DIR" ] || die "$DIR is not writable (use --dir DIR, or sudo for a system directory)"
  cp "$tmp/$ASSET" "$DIR/.bcli.new.$$"
  chmod 0755 "$DIR/.bcli.new.$$"
  mv -f "$DIR/.bcli.new.$$" "$DIR/bcli"
  say "  installed  $DIR/bcli"
  if v=$("$DIR/bcli" version </dev/null 2>/dev/null); then say "  bcli says  $v"; fi

  case ":$PATH:" in
    *":$DIR:"*) on_path=1 ;;
    *) on_path=0 ;;
  esac
  say ""
  if [ "$on_path" = 0 ]; then
    case "${SHELL:-}" in
      */zsh) rc="$HOME/.zshrc" ;;
      */bash) if [ "$OS" = darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
      */fish) rc="" ;;
      *) rc="$HOME/.profile" ;;
    esac
    say "$DIR is not on your PATH yet. Add it:"
    if [ -n "$rc" ]; then
      say "  echo 'export PATH=\"$DIR:\$PATH\"' >> $rc && export PATH=\"$DIR:\$PATH\""
    else
      say "  fish_add_path $DIR"
    fi
    say ""
  fi
  setup_bitwarden "$DIR/bcli"
  say "Next steps:"
  say "  bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai && bcli env use cloud"
  say "  bcli login                   # sign in with your servas.ai account (device code)"
  say "  bcli session create --wait   # a cloud browser; prints cdp_url and view_url"
  say "Docs: https://github.com/$REPO#quick-start"
}

main "$@"
