# bluebye.ps1 - command line front end for the BlueBye engine.
# ASCII only (see bluebye-lib.ps1).

param(
  [ValidateSet('Host', 'Tick', 'Status', 'Night', 'Restore', 'Resume', 'Probe', 'Test', 'Ensure', 'Start', 'Stop')]
  [string]$Mode = 'Tick',
  [int]$ParentPid = 0
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'bluebye-lib.ps1')
$script:Quiet = ($Mode -eq 'Host')
$script:SupervisorPid = $ParentPid

function Invoke-Probe {
  "idle            : $(Get-IdleSeconds) s"
  "host running    : $(Test-HostRunning)"
  "state           : $(Get-Phase)"
  "mic in use      : $(Test-MicInUse)"
  "bt hid connected: $(Test-BtHidConnected)"
  ''
  $radio = Get-BtRadio
  if ($radio) {
    try { "radio           : $($radio.Name) / $($radio.Kind) / $($radio.State)" } catch { 'radio           : query error' }
    try {
      $access = Await-Result ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
      "radio access    : $($access.ToString())"
    } catch { "radio access    : error $($_.Exception.Message)" }
  } else {
    'radio           : not found'
  }
  ''
  $media = Get-MediaState
  "media sessions  : $($media.Sessions.Count) (playing $($media.Playing), call-like $($media.CallLike))"
  foreach ($s in $media.Sessions) {
    "  - {0}  status={1} pause={2} play={3}" -f $s.App, $s.Status, $s.CanPause, $s.CanPlay
  }
  ''
  'config:'
  $cfg = Get-Cfg
  foreach ($k in $cfg.Keys) { "  {0} = {1}" -f $k, $cfg[$k] }
}

function Invoke-TestRadio {
  "bt before : $(Get-BtState)"
  "off       : $(Set-BtRadio $false)"
  Start-Sleep -Seconds 2
  "bt mid    : $(Get-BtState)"
  "on        : $(Set-BtRadio $true)"
  Start-Sleep -Seconds 2
  "bt after  : $(Get-BtState)"
}

function Invoke-Night {
  $cfg = Get-Cfg
  $idle = Get-IdleSeconds
  $media = Get-MediaState
  $n = 0
  if ([bool]$cfg.PauseMedia -and $media.Playing -gt 0) {
    $pausedApps = @(Pause-Media $media)
    $n = $pausedApps.Count
    if ($n -gt 0) { Save-ResumeList $pausedApps }
  }
  "paused: $n"
  if ([bool]$cfg.TurnOffBluetooth) {
    if (Test-BtHidConnected) {
      'bluetooth kept on: more than one bluetooth device is connected'
      return
    }
    $r = Set-BtRadio $false
    "bluetooth off: $r"
    if ($r -eq 'ok' -or $r -eq 'already') {
      # seenAway=false: the user pressed the button while still at the desk,
      # so the come-back path must wait until the desk really went idle
      Save-State 'radiooff' $false
      Write-StatusFile $idle 'Off' 'radiooff' $null $cfg
    }
  }
}

function Invoke-Restore {
  $cfg = Get-Cfg
  $r = Set-BtRadio $true
  "bluetooth on: $r"
  if ($r -eq 'ok' -or $r -eq 'already') {
    Clear-State
    Write-StatusFile (Get-IdleSeconds) 'On' '' (Get-MediaState) $cfg
  }
}

function Invoke-Status {
  "idle        : $(Get-IdleSeconds) s"
  "bluetooth   : $(Get-BtState)"
  "phase       : $(Get-Phase)"
  "host running: $(Test-HostRunning)"
  "log file    : $($script:LogFile)"
  if (Test-Path $script:LogFile) {
    ''
    'last 12 log lines:'
    Get-Content -Path $script:LogFile -Tail 12 -Encoding UTF8 | ForEach-Object { "  $_" }
  }
}

function Invoke-Ensure {
  $flag = Join-Path $script:Root 'stopped.flag'
  if (Test-Path $flag) { return 'stopped' }

  $cfg = Get-Cfg
  $maxAge = [int]$cfg.TickSeconds * 3
  if ($maxAge -lt 60) { $maxAge = 60 }

  if ((Test-HostRunning) -and (Test-HeartbeatFresh $maxAge)) { return 'running' }

  try {
    $t = Get-ScheduledTask -TaskName 'BlueBye-Host' -ErrorAction Stop
    if ($t.State -eq 'Disabled') { return 'disabled' }
  } catch {
    return 'no-task'
  }

  if (Test-HostRunning) {
    # holds the mutex but stopped ticking: a hung WinRT call or a blocked loop.
    # Restarting the task alone is not enough (IgnoreNew sees it as running).
    Write-Log 'host holds the mutex but its heartbeat is stale -> restarting' 'ERROR'
    Stop-ScheduledTask -TaskName 'BlueBye-Host' -ErrorAction SilentlyContinue
    Get-Process -Name 'BlueByeSupervisor' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    try {
      Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'bluebye\.ps1' -and $_.CommandLine -match '-Mode\s+Host'
      } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    Start-Sleep -Seconds 1
  }

  Start-ScheduledTask -TaskName 'BlueBye-Host' -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 4
  if ((Test-HostRunning) -and (Test-HeartbeatFresh $maxAge)) { 'restarted' } else { 'failed' }
}

function Invoke-Stop {
  # the user asked to quit: leave a marker so the watchdog does not revive us
  $flag = Join-Path $script:Root 'stopped.flag'
  Set-Content -Path $flag -Value (Get-Date).ToString('o') -Encoding ASCII
  foreach ($t in @('BlueBye-Host', 'BlueBye-Watchdog')) {
    Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
  }
  Get-Process -Name 'BlueByeSupervisor' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Stop-ScheduledTask -TaskName 'BlueBye-Tray' -ErrorAction SilentlyContinue
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
      $_.CommandLine -and $_.CommandLine -match 'bluebye-ui\.ps1'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
      $_.CommandLine -and $_.CommandLine -match 'bluebye\.ps1' -and $_.CommandLine -match '-Mode\s+Host'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  'stopped'
}

function Invoke-Start {
  $flag = Join-Path $script:Root 'stopped.flag'
  if (Test-Path $flag) { Remove-Item $flag -Force -ErrorAction SilentlyContinue }
  foreach ($t in @('BlueBye-Host', 'BlueBye-Watchdog')) {
    Enable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null
  }
  if (Test-HostRunning) { 'running'; return }
  Start-ScheduledTask -TaskName 'BlueBye-Host' -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  if (Test-HostRunning) { 'started' } else { 'failed' }
}

switch ($Mode) {
  'Host'    { Invoke-Host }
  'Tick'    { Invoke-Tick }
  'Status'  { Invoke-Status }
  'Night'   { Invoke-Night }
  'Restore' { Invoke-Restore }
  'Resume'  { "resumed: $(Resume-Media)" }
  'Probe'   { Invoke-Probe }
  'Test'    { Invoke-TestRadio }
  'Ensure'  { Invoke-Ensure }
  'Start'   { Invoke-Start }
  'Stop'    { Invoke-Stop }
}
