# bcli installer for Windows x64 (PowerShell 5.1 or 7), per user, no administrator rights.
#
#   irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
#
# A specific release:   $env:BCLI_VERSION = "v0.14.0"; irm https://raw.githubusercontent.com/servas-ai/bcli-public/main/install.ps1 | iex
# Download and verify only, change nothing:   $env:BCLI_DRY_RUN = "1"; irm … | iex
#
# Downloads bcli-windows-amd64.exe from the GitHub releases of servas-ai/bcli-public, checks the
# Ed25519 signature of SHA256SUMS against the servas.ai release key built into this script (plain
# .NET, RFC 8032, the same check as scripts/windows/verify-release.ps1), checks the file against
# SHA256SUMS and installs it as %LOCALAPPDATA%\Programs\bcli\bcli.exe, on the user PATH.
# Nothing is installed if a check fails. There is no Authenticode signature: the Ed25519
# signature is what proves the file comes from servas.ai.

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest in PowerShell 5.1 is very slow with it
Add-Type -AssemblyName System.Numerics
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$Repo       = 'servas-ai/bcli-public'
$Asset      = 'bcli-windows-amd64.exe'
# servas.ai CLI release key (raw Ed25519, base64) = keys/bcli-release-ed25519.pem in servas-ai/bcli-public.
$ReleaseKey = 'fUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E='
$Version    = $env:BCLI_VERSION
$Dir        = if ($env:BCLI_INSTALL_DIR) { $env:BCLI_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\bcli' }
$DryRun     = $env:BCLI_DRY_RUN -eq '1'

function Fail([string]$msg) { throw "bcli install: $msg" }

# --- Ed25519 (RFC 8032), cofactorless check as Go crypto/ed25519: encode([S]B - [h]A) == R ---
$P = [Numerics.BigInteger]::Pow(2, 255) - 19
$L = [Numerics.BigInteger]::Pow(2, 252) + [Numerics.BigInteger]::Parse('27742317777372353535851937790883648493')
function EdModP([Numerics.BigInteger]$a) { $r = $a % $P; if ($r.Sign -lt 0) { $r += $P }; $r }
function EdModL([Numerics.BigInteger]$a) { $r = $a % $L; if ($r.Sign -lt 0) { $r += $L }; $r }
function EdInv([Numerics.BigInteger]$a) { [Numerics.BigInteger]::ModPow((EdModP $a), $P - 2, $P) }
$D = EdModP ([Numerics.BigInteger]::Parse('-121665') * (EdInv ([Numerics.BigInteger]121666)))
$SqrtM1 = [Numerics.BigInteger]::ModPow(2, ($P - 1) / 4, $P)
function EdFromLE([byte[]]$b) { [Numerics.BigInteger]::new([byte[]]($b + [byte]0)) }
function EdToLE32([Numerics.BigInteger]$v) { $b = $v.ToByteArray(); $o = New-Object byte[] 32; [Array]::Copy($b, $o, [Math]::Min(32, $b.Length)); $o }
function EdAdd($p1, $p2) {
    $t = EdModP ($D * $p1[0] * $p2[0] * $p1[1] * $p2[1])
    $x = EdModP (($p1[0] * $p2[1] + $p2[0] * $p1[1]) * (EdInv (1 + $t)))
    $y = EdModP (($p1[1] * $p2[1] + $p1[0] * $p2[0]) * (EdInv (1 - $t)))
    , @($x, $y)
}
function EdMul([Numerics.BigInteger]$k, $pt) {
    $acc = @([Numerics.BigInteger]::Zero, [Numerics.BigInteger]::One)
    $add = $pt
    while ($k.Sign -gt 0) {
        if (-not $k.IsEven) { $acc = EdAdd $acc $add }
        $add = EdAdd $add $add
        $k = $k / 2
    }
    , $acc
}
function EdDecode([byte[]]$b) {
    $c = [byte[]]$b.Clone(); $sign = ($c[31] -shr 7) -band 1; $c[31] = $c[31] -band 0x7f
    $y = EdFromLE $c
    if ($y -ge $P) { throw 'invalid point' }
    $xx = EdModP (($y * $y - 1) * (EdInv ($D * $y * $y + 1)))
    $x = [Numerics.BigInteger]::ModPow($xx, ($P + 3) / 8, $P)
    if (-not (EdModP ($x * $x - $xx)).IsZero) { $x = EdModP ($x * $SqrtM1) }
    if (-not (EdModP ($x * $x - $xx)).IsZero) { throw 'invalid point' }
    if ($x.IsZero -and $sign -eq 1) { throw 'invalid point' }
    if ([int]($x.IsEven -eq $false) -ne $sign) { $x = $P - $x }
    , @($x, $y)
}
function EdEncode($pt) { $b = EdToLE32 $pt[1]; if (-not $pt[0].IsEven) { $b[31] = $b[31] -bor 0x80 }; , $b }
$Base = EdDecode (EdToLE32 (EdModP ([Numerics.BigInteger]4 * (EdInv ([Numerics.BigInteger]5)))))
function Test-Ed25519([byte[]]$pub, [byte[]]$msg, [byte[]]$sig) {
    if ($pub.Length -ne 32 -or $sig.Length -ne 64) { return $false }
    try { $A = EdDecode $pub } catch { return $false }
    $S = EdFromLE $sig[32..63]
    if ($S -ge $L) { return $false }
    $sha = [Security.Cryptography.SHA512]::Create()
    $h = EdModL (EdFromLE $sha.ComputeHash([byte[]]($sig[0..31] + $pub + $msg)))
    $negA = @((EdModP ($P - $A[0])), $A[1])
    $R = EdEncode (EdAdd (EdMul $S $Base) (EdMul $h $negA))
    for ($i = 0; $i -lt 32; $i++) { if ($R[$i] -ne $sig[$i]) { return $false } }
    $true
}
function HexBytes([string]$h) { [byte[]]($h -split '(..)' -ne '' | ForEach-Object { [Convert]::ToByte($_, 16) }) }

# Self-test, RFC 8032 section 7.1 test 2: accept the vector, refuse it for another message.
$tk = HexBytes '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c'
$ts = HexBytes '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'
if (-not (Test-Ed25519 $tk ([byte[]]@(0x72)) $ts) -or (Test-Ed25519 $tk ([byte[]]@(0x78)) $ts)) {
    Fail 'Ed25519 self-test failed in this PowerShell; nothing was installed'
}

# --- platform -----------------------------------------------------------------------------
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
switch ($arch) {
    'AMD64' { }
    'ARM64' { Write-Host 'Windows on ARM: installing the x64 build, which runs through emulation.' }
    default { Fail "unsupported CPU $arch; bcli for Windows is built for x64" }
}
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated) {
    Write-Warning 'This PowerShell runs as administrator. bcli installs for the current user; its daemon, vault and Bitwarden bridge refuse to run elevated. Use a normal PowerShell window for bcli.'
}

# --- download -----------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("bcli-install-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    function Get-File([string]$url, [string]$out) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out } catch { Fail "download failed: $url ($($_.Exception.Message))" }
    }
    if (-not $Version) {
        Get-File "https://github.com/$Repo/releases/latest/download/VERSION" "$tmp\VERSION"
        $Version = 'v' + ([IO.File]::ReadAllText("$tmp\VERSION")).Trim()
    }
    if (-not $Version.StartsWith('v')) { $Version = "v$Version" }
    if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { Fail "invalid version $Version (expected vX.Y.Z)" }
    $RelUrl = "https://github.com/$Repo/releases/download/$Version"
    Write-Host "bcli $Version for windows/amd64 -> $Dir\bcli.exe"

    foreach ($f in 'SHA256SUMS', 'SHA256SUMS.sig', 'VERSION') { Get-File "$RelUrl/$f" "$tmp\$f" }
    $sums = [IO.File]::ReadAllBytes("$tmp\SHA256SUMS")
    $sig  = [Convert]::FromBase64String(([IO.File]::ReadAllText("$tmp\SHA256SUMS.sig")).Trim())
    if (-not (Test-Ed25519 ([Convert]::FromBase64String($ReleaseKey)) $sums $sig)) {
        Fail "SIGNATURE INVALID: SHA256SUMS of $Version is not signed by the servas.ai release key. Nothing was installed."
    }
    Write-Host '  signature  OK (Ed25519, servas.ai release key)'

    $want = @{}
    foreach ($line in [IO.File]::ReadAllLines("$tmp\SHA256SUMS")) {
        if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$') { Fail "invalid line in SHA256SUMS: $line" }
        $want[$Matches[2]] = $Matches[1]
    }
    function Test-Sum([string]$name, [string]$file) {
        if (-not $want.ContainsKey($name)) { Fail "$name is not listed in the signed SHA256SUMS of $Version" }
        $got = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($got -ne $want[$name]) { Fail "CHECKSUM MISMATCH for $name (got $got, want $($want[$name])). Nothing was installed." }
    }
    Test-Sum 'VERSION' "$tmp\VERSION"
    if (('v' + ([IO.File]::ReadAllText("$tmp\VERSION")).Trim()) -ne $Version) { Fail "release $Version carries another version" }

    Write-Host "  download   $Asset"
    Get-File "$RelUrl/$Asset" "$tmp\$Asset"
    Test-Sum $Asset "$tmp\$Asset"
    Write-Host "  checksum   OK (sha256 $($want[$Asset]))"

    if ($DryRun) { Write-Host "  dry run    would install $Asset as $Dir\bcli.exe; nothing changed"; return }

    # --- install ----------------------------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $exe = Join-Path $Dir 'bcli.exe'
    if (Test-Path -LiteralPath $exe) {
        # A running bcli.exe (daemon, vault, bridge) cannot be overwritten but can be renamed;
        # bcli deletes such .old files itself on its next start, as after `bcli update`.
        $old = Join-Path $Dir (".bcli-replaced-" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + ".old")
        Move-Item -LiteralPath $exe -Destination $old
        Write-Host '  replaced   the previous bcli.exe (restart a running daemon: bcli daemon stop; bcli daemon start)'
    }
    Copy-Item -LiteralPath "$tmp\$Asset" -Destination $exe
    Test-Sum $Asset $exe
    Write-Host "  installed  $exe"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';') -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', ((@($userPath -split ';') + $Dir | Where-Object { $_ }) -join ';'), 'User')
        Write-Host "  PATH       added $Dir to your user PATH (new terminals pick it up)"
    }
    if (@($env:Path -split ';') -notcontains $Dir) { $env:Path = ((@($env:Path -split ';') + $Dir | Where-Object { $_ }) -join ';') }

    try { $v = & $exe version 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { Write-Host "  bcli says  $v" } } catch { }
    Write-Host ''
    Write-Host 'Next steps (normal, non-elevated PowerShell):'
    Write-Host '  bcli env add cloud --kind cloud --endpoint https://api.baas.servas.ai; bcli env use cloud'
    Write-Host '  bcli login                   # sign in with your servas.ai account (device code)'
    Write-Host '  bcli session create --wait   # a cloud browser; prints cdp_url and view_url'
    Write-Host "Docs: https://github.com/$Repo/blob/main/docs/installation.md#windows"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
}
