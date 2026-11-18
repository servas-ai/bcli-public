# Release signing key

`bcli-release-ed25519.pem` is the public Ed25519 key of the servas.ai CLI release key. It signs the `SHA256SUMS` file
of bcli releases (`SHA256SUMS.sig`, base64-encoded raw signature) and is the same key bcli uses to verify
`bcli update`.

Raw public key (base64): `fUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E=`

How to verify a release: [docs/installation.md](../docs/installation.md#verify-the-signature-of-sha256sums).
