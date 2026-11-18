<#
.SYNOPSIS
  agent-web - a browser for coding agents, on top of bcli (servas.ai Browser as a Service).

.DESCRIPTION
  Windows version of bin/agent-web with the same subcommands and output:
  `start` prints ONLY the session id on stdout; hints go to stderr.
  Docs: https://github.com/servas-ai/bcli-public/blob/main/docs/agents.md

.EXAMPLE
  $sid = agent-web start
  agent-web ab $sid open https://example.com
  agent-web ab $sid snapshot -i
  agent-web stop $sid
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Version     = '1.0.0'
$Bcli        = if ($env:AGENT_WEB_BCLI) { $env:AGENT_WEB_BCLI } else { 'bcli' }
$Ab          = if ($env:AGENT_WEB_AGENT_BROWSER) { $env:AGENT_WEB_AGENT_BROWSER } else { 'agent-browser' }
$BcliHome    = if ($env:BCLI_HOME) { $env:BCLI_HOME } else { Join-Path $HOME '.bcli' }
$State       = if ($env:AGENT_WEB_STATE) { $env:AGENT_WEB_STATE } else { Join-Path $BcliHome 'agent-web' }
$IdleTimeout = if ($env:AGENT_WEB_IDLE_TIMEOUT) { $env:AGENT_WEB_IDLE_TIMEOUT } else { '30m' }

function Show-Usage {
  @'
agent-web - a browser for coding agents, on top of bcli

Usage:
  agent-web start [--gpu] [--env NAME] [PROFILE] [BCLI_CREATE_FLAGS...]
                                     Create a session and print ONLY its id on stdout (hints go to stderr).
                                     PROFILE: start from a persistent bcli profile (must exist).
                                     Other flags (e.g. --ttl 2h --locale en-US) go to 'bcli session create'.
  agent-web ab SID ARGS...           Run agent-browser against the session, e.g.
                                       agent-web ab SID open https://example.com
                                       agent-web ab SID snapshot -i
                                       agent-web ab SID click '@e3'   (quote @refs in PowerShell)
  agent-web view SID [--print]       Open the live view in the default browser (for a human).
                                     --print writes the URL to stdout instead; it contains an access token.
  agent-web captcha SID [HINT]       Ask the human to solve a captcha in a small native window.
  agent-web assist SID [HINT]        Ask the human for any help (2FA, consent, decision) in a native window.
  agent-web tunnel SID PORTS         Make local ports (e.g. 3000,5173) reachable as http://localhost:PORT
                                     inside the cloud browser. Blocks: run it in the background.
  agent-web audio SID [BCLI_AUDIO_FLAGS...]
                                     Stream the session's speaker/microphone (bcli audio attach). Blocks.
  agent-web stop SID                 Close the agent-browser connection and stop the session.
  agent-web status                   List your running sessions and the sessions started by agent-web.
  agent-web version | help

Environment:
  AGENT_WEB_ENV            bcli environment name (default: bcli's current environment)
  AGENT_WEB_BCLI           bcli executable (default: bcli on PATH)
  AGENT_WEB_AGENT_BROWSER  agent-browser executable (default: agent-browser on PATH)
  AGENT_WEB_IDLE_TIMEOUT   idle timeout for new sessions (default: 30m)
  AGENT_WEB_STATE          state directory (default: %USERPROFILE%\.bcli\agent-web)

Exit codes: those of bcli (e.g. 3 quota, 4 profile locked, 5 no capacity, 15 not signed in);
64 usage error; 69 a required tool is missing.
'@
}

function Write-Hint([string]$Message) { [Console]::Error.WriteLine("agent-web: $Message") }
function Exit-With([int]$Code, [string]$Message) { if ($Message) { Write-Hint $Message }; exit $Code }
function Exit-Usage([string]$Message) { Write-Hint $Message; [Console]::Error.WriteLine("Run 'agent-web help' for usage."); exit 64 }
function Assert-Tool([string]$Name, [string]$Hint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { Exit-With 69 "'$Name' not found on PATH. $Hint" }
}
function Assert-Sid([string]$Sid) {
  if (-not $Sid -or $Sid -notmatch '^[A-Za-z0-9-]+$') { Exit-Usage "invalid session id '$Sid'" }
}

function Get-StateFile([string]$Sid) { Join-Path $State "sid-$Sid.env" }

# Per-session state: bcli environment and kind (cloud|local).
function Get-SidState([string]$Sid) {
  $info = [ordered]@{ Env = [string]$env:AGENT_WEB_ENV; Kind = 'cloud' }
  $file = Get-StateFile $Sid
  if (Test-Path $file) {
    foreach ($line in Get-Content $file) {
      if ($line -like 'env=*') { $info.Env = $line.Substring(4) }
      elseif ($line -like 'kind=*') { $info.Kind = $line.Substring(5) }
    }
  }
  return $info
}

function Get-EnvArgs([string]$EnvName) { if ($EnvName) { @('--env', $EnvName) } else { @() } }

# Runs bcli, returns stdout as one string; exits with bcli's exit code on failure.
function Invoke-Bcli([string[]]$Arguments) {
  $out = & $Bcli @Arguments
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  return ($out -join "`n")
}

function Get-AbConfig {
  # A config without a browser profile: agent-browser then only attaches over CDP.
  $cfg = Join-Path $State 'agent-browser-cdp.json'
  if (-not (Test-Path $cfg)) { Set-Content -Path $cfg -Value '{"headed": false}' -Encoding ascii }
  return $cfg
}

# CDP target for agent-browser: the browser WebSocket of a cloud session, the port of a local one.
function Get-CdpTarget([string]$Sid, $Info) {
  $url = (Invoke-Bcli ((Get-EnvArgs $Info.Env) + @('session', 'url', $Sid))).Trim()
  if ($Info.Kind -eq 'local') { return ($url.TrimEnd('/') -split ':')[-1] }
  $base, $query = $url -split '\?', 2
  $versionUrl = $base.TrimEnd('/') + '/json/version' + $(if ($query) { "?$query" } else { '' })
  $version = Invoke-RestMethod -Uri $versionUrl -TimeoutSec 20
  return [string]$version.webSocketDebuggerUrl
}

function Start-Session([string[]]$Rest) {
  $gpu = $false; $profileName = ''; $envName = [string]$env:AGENT_WEB_ENV; $extra = @()
  for ($i = 0; $i -lt $Rest.Count; $i++) {
    $a = $Rest[$i]
    if ($a -eq '--gpu') { $gpu = $true }
    elseif ($a -eq '--env') {
      if ($i + 1 -ge $Rest.Count) { Exit-Usage '--env needs a name' }
      $i++; $envName = $Rest[$i]
    }
    elseif ($a -eq '--') { if ($i + 1 -lt $Rest.Count) { $extra = $Rest[($i + 1)..($Rest.Count - 1)] }; break }
    elseif ($a.StartsWith('-')) { $extra = $Rest[$i..($Rest.Count - 1)]; break }  # the rest goes to bcli session create
    else { if ($profileName) { Exit-Usage 'only one profile' }; $profileName = $a }
  }
  Assert-Tool $Bcli 'Install bcli: https://github.com/servas-ai/bcli-public#install'
  $cmd = (Get-EnvArgs $envName) + @('session', 'create', '--wait', '--idle-timeout', $IdleTimeout)
  if ($gpu) { $cmd += '--gpu' }
  if ($profileName) { $cmd += @('--profile', $profileName) }
  $session = (Invoke-Bcli ($cmd + $extra)) | ConvertFrom-Json
  if (-not $session.id) { Exit-With 1 'bcli returned no session id' }
  $kind = if ($session.PSObject.Properties['provision_path'] -and $session.provision_path -eq 'local') { 'local' } else { 'cloud' }
  Set-Content -Path (Get-StateFile $session.id) -Value @("env=$envName", "kind=$kind") -Encoding ascii
  Write-Output $session.id
  $detail = $kind
  if ($profileName) { $detail += ", profile $profileName" }
  if ($gpu) { $detail += ', gpu' }
  Write-Hint "session ready ($detail). Next: agent-web ab $($session.id) open <url> · agent-web stop $($session.id) when done"
}

function Invoke-Ab([string[]]$Rest) {
  if ($Rest.Count -lt 2) { Exit-Usage 'usage: agent-web ab SID ARGS...' }
  $sid = $Rest[0]; Assert-Sid $sid
  $info = Get-SidState $sid
  Assert-Tool $Ab 'Install the agent-browser CLI (e.g. npm install -g agent-browser).'
  $target = Get-CdpTarget $sid $info
  if (-not $target) { Exit-With 1 "could not resolve the CDP endpoint of session $sid" }
  $env:AGENT_BROWSER_CONFIG = Get-AbConfig
  $env:AGENT_BROWSER_SESSION = "bcli-$sid"
  $abArgs = $Rest[1..($Rest.Count - 1)]
  & $Ab --cdp $target @abArgs
  exit $LASTEXITCODE
}

function Open-View([string[]]$Rest) {
  if ($Rest.Count -lt 1) { Exit-Usage 'usage: agent-web view SID [--print]' }
  $sid = $Rest[0]; Assert-Sid $sid
  $info = Get-SidState $sid
  $session = (Invoke-Bcli ((Get-EnvArgs $info.Env) + @('session', 'get', $sid))) | ConvertFrom-Json
  $url = if ($session.PSObject.Properties['view_url']) { [string]$session.view_url } else { '' }
  if (-not $url) { Exit-With 1 "session $sid has no live view (local sessions show their window on this desktop)" }
  if ($Rest.Count -ge 2 -and $Rest[1] -eq '--print') { Write-Output $url; return }
  try { Start-Process $url } catch { Exit-With 1 "no desktop browser here. Use 'agent-web view $sid --print' and give the URL to the human directly (it contains an access token)." }
  Write-Hint 'live view opened in the default browser'
}

function Invoke-Assist([string]$Mode, [string[]]$Rest) {
  if ($Rest.Count -lt 1) { Exit-Usage "usage: agent-web $Mode SID [HINT]" }
  $sid = $Rest[0]; Assert-Sid $sid
  $hint = if ($Rest.Count -ge 2) { $Rest[1] } else { '' }
  $info = Get-SidState $sid
  if ($info.Kind -eq 'local') { Write-Hint 'local session: its browser window is on this desktop; ask the human to use it directly.'; return }
  if ($Mode -eq 'captcha') {
    $heading = 'An agent needs your help: please solve the captcha'
    if (-not $hint) { $hint = 'Solve it in this window, then close the window.' }
  } else {
    $heading = 'An agent needs your help'
    if (-not $hint) { $hint = 'Do what the page asks (e.g. a code or a confirmation), then close the window.' }
  }
  Write-Hint 'window open, waiting for the human (run this in the background or as a monitor)'
  $assistArgs = (Get-EnvArgs $info.Env) + @('assist', '--session', $sid, '--mode', 'window', '--heading', $heading, '--hint', $hint)
  & $Bcli @assistArgs
  switch ($LASTEXITCODE) {
    { $_ -in 0, 12 } { Write-Hint "the human closed the window. Check the page: agent-web ab $sid snapshot -i"; exit 0 }
    3 { Exit-With 3 "no window possible on this machine. Use: agent-web view $sid" }
    default { exit $LASTEXITCODE }
  }
}

function Start-Tunnel([string[]]$Rest) {
  if ($Rest.Count -ne 2) { Exit-Usage 'usage: agent-web tunnel SID PORTS' }
  $sid = $Rest[0]; Assert-Sid $sid
  $info = Get-SidState $sid
  if ($info.Kind -eq 'local') { Write-Hint 'local session: localhost is already reachable, no tunnel needed'; return }
  $tunnelArgs = (Get-EnvArgs $info.Env) + @('tunnel', 'start', '--session', $sid, '--ports', $Rest[1])
  & $Bcli @tunnelArgs
  exit $LASTEXITCODE
}

function Start-Audio([string[]]$Rest) {
  if ($Rest.Count -lt 1) { Exit-Usage 'usage: agent-web audio SID [--dir both|out|in] [--channels 1|2] [--fifo DIR | --socket PATH]' }
  $sid = $Rest[0]; Assert-Sid $sid
  $info = Get-SidState $sid
  $more = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }
  $audioArgs = (Get-EnvArgs $info.Env) + @('audio', 'attach', '--session', $sid) + $more
  & $Bcli @audioArgs
  exit $LASTEXITCODE
}

function Stop-Session([string[]]$Rest) {
  if ($Rest.Count -ne 1) { Exit-Usage 'usage: agent-web stop SID' }
  $sid = $Rest[0]; Assert-Sid $sid
  $info = Get-SidState $sid
  if (Get-Command $Ab -ErrorAction SilentlyContinue) {
    $env:AGENT_BROWSER_CONFIG = Get-AbConfig
    $env:AGENT_BROWSER_SESSION = "bcli-$sid"
    try { & $Ab close *> $null } catch { Write-Verbose 'agent-browser close failed; continuing' }
  }
  [void](Invoke-Bcli ((Get-EnvArgs $info.Env) + @('session', 'stop', $sid)))
  Remove-Item -Force -ErrorAction SilentlyContinue (Get-StateFile $sid)
  Write-Hint "stopped $sid"
}

function Show-Status {
  Assert-Tool $Bcli 'Install bcli: https://github.com/servas-ai/bcli-public#install'
  Write-Output '# running sessions (id state profile)'
  $sessions = (Invoke-Bcli ((Get-EnvArgs ([string]$env:AGENT_WEB_ENV)) + @('session', 'list'))) | ConvertFrom-Json
  foreach ($s in @($sessions)) {
    if ($null -eq $s -or $s.state -in 'terminated', 'failed') { continue }
    $p = if ($s.PSObject.Properties['profile'] -and $s.profile) { $s.profile } else { '' }
    Write-Output ("{0} {1} {2}" -f $s.id, $s.state, $p).TrimEnd()
  }
  $files = @(Get-ChildItem -Path $State -Filter 'sid-*.env' -ErrorAction SilentlyContinue)
  if ($files.Count -gt 0) {
    Write-Output '# started by agent-web'
    foreach ($f in $files) { Write-Output ($f.BaseName.Substring(4)) }
  }
}

New-Item -ItemType Directory -Force -Path $State | Out-Null

$command = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$rest = [string[]]@(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })

switch ($command) {
  'start'   { Start-Session $rest }
  'ab'      { Invoke-Ab $rest }
  'view'    { Open-View $rest }
  'captcha' { Invoke-Assist 'captcha' $rest }
  'assist'  { Invoke-Assist 'assist' $rest }
  'tunnel'  { Start-Tunnel $rest }
  'audio'   { Start-Audio $rest }
  'stop'    { Stop-Session $rest }
  'status'  { Show-Status }
  { $_ -in 'version', '--version' } { Write-Output "agent-web $Version" }
  { $_ -in 'help', '-h', '--help' } { Show-Usage }
  default   { Exit-Usage "unknown command '$command'" }
}
