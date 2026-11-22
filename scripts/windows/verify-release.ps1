#requires -Version 5.1
<#
Verify a bcli release directory on stock Windows (PowerShell 5.1 or 7), without
OpenSSL, Git Bash or bcli itself: the Ed25519 signature SHA256SUMS.sig over
SHA256SUMS with the servas.ai CLI release key below (RFC 8032, plain .NET
BigInteger and SHA-512), then the SHA-256 of every listed file that is present.

  powershell -ExecutionPolicy Bypass -File verify-release.ps1 -Dir C:\Users\me\Downloads\v0.14.0-rc.4

Prints "Signature OK" and one "OK <file>" line per present file; exits 1 on any
mismatch. bcli-windows-amd64.exe must be present.
#>
param([string]$Dir = '.')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Numerics

# servas.ai CLI release public key (raw Ed25519, base64) = bcli-public keys/bcli-release-ed25519.pem.
$ReleaseKey = 'fUyxc9eOwrlMrsEPHYTcYJoVTE8b/Lxj4B4I8lfEk/E='

$P = [Numerics.BigInteger]::Pow(2, 255) - 19
$L = [Numerics.BigInteger]::Pow(2, 252) + [Numerics.BigInteger]::Parse('27742317777372353535851937790883648493')
function EdModP([Numerics.BigInteger]$a) { $r = $a % $script:P; if ($r.Sign -lt 0) { $r += $script:P }; $r }
function EdInv([Numerics.BigInteger]$a) { [Numerics.BigInteger]::ModPow((EdModP $a), $script:P - 2, $script:P) }
$D = EdModP ([Numerics.BigInteger]::Parse('-121665') * (EdInv ([Numerics.BigInteger]121666)))
$SqrtM1 = [Numerics.BigInteger]::ModPow(2, ($P - 1) / 4, $P)
function EdFromLE([byte[]]$b) { [Numerics.BigInteger]::new([byte[]]($b + [byte]0)) }
function EdToLE32([Numerics.BigInteger]$v) { $b = $v.ToByteArray(); $o = New-Object byte[] 32; [Array]::Copy($b, $o, [Math]::Min(32, $b.Length)); $o }
# Twisted Edwards curve -x^2 + y^2 = 1 + d x^2 y^2, affine points @(x, y).
function EdAdd($p1, $p2) {
    $t = EdModP ($script:D * $p1[0] * $p2[0] * $p1[1] * $p2[1])
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
    if ($y -ge $script:P) { throw 'invalid point' }
    $xx = EdModP (($y * $y - 1) * (EdInv ($script:D * $y * $y + 1)))
    $x = [Numerics.BigInteger]::ModPow($xx, ($script:P + 3) / 8, $script:P)
    if (-not (EdModP ($x * $x - $xx)).IsZero) { $x = EdModP ($x * $script:SqrtM1) }
    if (-not (EdModP ($x * $x - $xx)).IsZero) { throw 'invalid point' }
    if ($x.IsZero -and $sign -eq 1) { throw 'invalid point' }
    if ([int]($x.IsEven -eq $false) -ne $sign) { $x = $script:P - $x }
    , @($x, $y)
}
function EdEncode($pt) { $b = EdToLE32 $pt[1]; if (-not $pt[0].IsEven) { $b[31] = $b[31] -bor 0x80 }; , $b }
$By = EdModP ([Numerics.BigInteger]4 * (EdInv ([Numerics.BigInteger]5)))
$Base = EdDecode (EdToLE32 $By)

function Test-Ed25519([byte[]]$pub, [byte[]]$msg, [byte[]]$sig) {
    if ($pub.Length -ne 32 -or $sig.Length -ne 64) { return $false }
    try { $A = EdDecode $pub } catch { return $false }
    $S = EdFromLE $sig[32..63]
    if ($S -ge $script:L) { return $false }
    $sha = [Security.Cryptography.SHA512]::Create()
    $h = EdModL (EdFromLE $sha.ComputeHash([byte[]]($sig[0..31] + $pub + $msg)))
    # Cofactorless check as Go crypto/ed25519: encode([S]B - [h]A) == R.
    $negA = @((EdModP ($script:P - $A[0])), $A[1])
    $Q = EdAdd (EdMul $S $script:Base) (EdMul $h $negA)
    $R = EdEncode $Q
    for ($i = 0; $i -lt 32; $i++) { if ($R[$i] -ne $sig[$i]) { return $false } }
    $true
}
function EdModL([Numerics.BigInteger]$a) { $r = $a % $script:L; if ($r.Sign -lt 0) { $r += $script:L }; $r }

$Dir = (Resolve-Path -LiteralPath $Dir).Path
$sums = Join-Path $Dir 'SHA256SUMS'
$sigFile = Join-Path $Dir 'SHA256SUMS.sig'
$msg = [IO.File]::ReadAllBytes($sums)
$sig = [Convert]::FromBase64String(([IO.File]::ReadAllText($sigFile)).Trim())
if (-not (Test-Ed25519 ([Convert]::FromBase64String($ReleaseKey)) $msg $sig)) {
    Write-Output 'Signature INVALID: SHA256SUMS is not signed with the servas.ai CLI release key'
    exit 1
}
Write-Output 'Signature OK'
$bad = 0; $seenExe = $false
foreach ($line in [IO.File]::ReadAllLines($sums)) {
    if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$') { Write-Output "Invalid line in SHA256SUMS: $line"; exit 1 }
    $want = $Matches[1]; $name = $Matches[2]
    $file = Join-Path $Dir $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    if ($name -eq 'bcli-windows-amd64.exe') { $seenExe = $true }
    $got = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -eq $want) { Write-Output "OK $name" } else { Write-Output "MISMATCH $name"; $bad++ }
}
if (-not $seenExe) { Write-Output 'bcli-windows-amd64.exe missing'; exit 1 }
if ($bad -gt 0) { exit 1 }
