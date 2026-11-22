<!--
  Release notes template for bcli. Copy to release-notes/vX.Y.Z.md, fill in, and pass it to
  `gh release create … --notes-file release-notes/vX.Y.Z.md`.
  Never mention internal hosts, customers, people or ticket ids.
-->

**bcli vX.Y.Z** — one sentence on what this release is about.

## Highlights

- …

## Fixes

- …

## Upgrade notes

- `bcli update` installs this version automatically within a day; run `bcli update` to update now.
- …

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.sh | sh -s -- --version vX.Y.Z
```

```powershell
$env:BCLI_VERSION = "vX.Y.Z"; irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
```

| Platform | Asset |
|---|---|
| Linux x86-64 | `bcli-linux-amd64` |
| Linux ARM64 | `bcli-linux-arm64` |
| macOS Apple silicon | `bcli-darwin-arm64` |
| macOS Intel | `bcli-darwin-amd64` |
| Windows x86-64 | `bcli-windows-amd64.exe` |

Plus `VERSION`, `SHA256SUMS` and `SHA256SUMS.sig`; nothing else is attached.
Instructions: [docs/installation.md](https://github.com/servas-ai/bcli-public/blob/main/docs/installation.md)

## Checksums

```text
<content of SHA256SUMS>
```
