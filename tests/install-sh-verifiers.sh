#!/bin/sh
# Checks the three Ed25519 verifiers of install.sh (openssl, python, bc) against RFC 8032
# test vectors and a signed release directory, including tampered inputs.
#
#   sh tests/install-sh-verifiers.sh [RELEASE_DIR]
#
# RELEASE_DIR holds SHA256SUMS and SHA256SUMS.sig of a release (optional). A verifier that
# is not available on this machine is reported as "n/a"; any wrong verdict fails (exit 1).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
lib=$(mktemp)
sed '$d' "$here/../install.sh" >"$lib"   # all functions, without the final main call
# shellcheck disable=SC1090
. "$lib"
rm -f "$lib"
OS=linux
[ "$(uname -s)" = Darwin ] && OS=darwin
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # check TOOL WANT KEYHEX SIGHEX MSGFILE LABEL
  rc=0; "verify_$1" "$3" "$4" "$5" || rc=$?
  if [ "$rc" = 2 ]; then printf 'n/a   %-8s %s\n' "$1" "$6"; return 0; fi
  if [ "$rc" = "$2" ]; then printf 'ok    %-8s %s\n' "$1" "$6"; else printf 'FAIL  %-8s %s (got %s, want %s)\n' "$1" "$6" "$rc" "$2"; fail=1; fi
}
pem_for() { # make KEY_PEM for a raw hex key (openssl reads PEM)
  hex_to_file "302a300506032b6570032100$1" "$tmp/k.der"
  KEY_PEM="-----BEGIN PUBLIC KEY-----
$(openssl base64 -A -in "$tmp/k.der" 2>/dev/null || true)
-----END PUBLIC KEY-----"
}

# RFC 8032 7.1 tests 1-3
k1=d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a
s1=e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b
k2=$T_KEY; s2=$T_SIG
k3=fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025
s3=6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a
: >"$tmp/m1"; printf r >"$tmp/m2"; hex_to_file af82 "$tmp/m3"; printf 'af83' >"$tmp/bad"
saved_pem=$KEY_PEM
for tool in openssl python bc; do
  pem_for "$k1"; check "$tool" 0 "$k1" "$s1" "$tmp/m1" "RFC 8032 test 1 (empty message)"
  pem_for "$k2"; check "$tool" 0 "$k2" "$s2" "$tmp/m2" "RFC 8032 test 2"
  pem_for "$k3"; check "$tool" 0 "$k3" "$s3" "$tmp/m3" "RFC 8032 test 3"
  check "$tool" 1 "$k3" "$s3" "$tmp/bad" "RFC 8032 test 3, other message"
  check "$tool" 1 "$k3" "$(printf '%s' "$s3" | cut -c1-127)b" "$tmp/m3" "RFC 8032 test 3, changed signature"
done
KEY_PEM=$saved_pem

if [ $# -ge 1 ]; then
  key=$(b64_to_hex "$KEY_B64")
  sig=$(b64_to_hex "$(cat "$1/SHA256SUMS.sig")")
  sed 's/^0/1/' "$1/SHA256SUMS" >"$tmp/SHA256SUMS.tampered"
  for tool in openssl python bc; do
    check "$tool" 0 "$key" "$sig" "$1/SHA256SUMS" "release SHA256SUMS"
    check "$tool" 1 "$key" "$sig" "$tmp/SHA256SUMS.tampered" "release SHA256SUMS, one digit changed"
  done
  # The full chain as main() runs it: self-tests, then the release signature.
  VERSION=test SKIP_SIG=0
  ( verify_signature "$1/SHA256SUMS" "$1/SHA256SUMS.sig" ) && echo "ok    chain    verify_signature accepts the release" ||
    { echo "FAIL  chain    verify_signature rejected the release"; fail=1; }
  if ( verify_signature "$tmp/SHA256SUMS.tampered" "$1/SHA256SUMS.sig" ) 2>/dev/null; then
    echo "FAIL  chain    verify_signature accepted a tampered SHA256SUMS"; fail=1
  else
    echo "ok    chain    verify_signature refuses a tampered SHA256SUMS"
  fi
fi
exit "$fail"
