# bluebye-lib.ps1
# Shared engine for BlueBye. Dot-source this file, then call the functions.
# ASCII only: Windows PowerShell 5.1 reads BOM-less files as ANSI (GBK on a
# Chinese Windows) and a stray multibyte character would eat a quote.

$script:Root = $PSScriptRoot
if (-not $script:Root) { $script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

$script:LogFile    = Join-Path $script:Root 'bluebye.log'
$script:StateFile  = Join-Path $script:Root 'state.json'
$script:CfgFile    = Join-Path $script:Root 'config.json'
$script:StatusFile = Join-Path $script:Root 'status.json'
$script:ResumeFile = Join-Path $script:Root 'resume.json'
$script:Quiet      = $false
$script:SupervisorPid = 0

# ---------------------------------------------------------------- config ----

$defaultCfg = [ordered]@{
  Enabled              = $true
  NightStartHour       = 19      # only act from 19:00 on
  NightEndHour         = 7       # ... and until 07:00 (covers post-midnight stragglers)
  IdleMinutes          = 30      # keyboard/mouse idle that counts as "left the desk"
  RadioOffDelayMinutes = 10      # after pausing, wait this long before killing the radio
  RestoreIdleSeconds   = 60      # user is "back" once idle drops below this
  PauseMedia           = $true
  TurnOffBluetooth     = $true
  SkipOnCallSession    = $true
  SkipWhenMicInUse     = $true
  TickSeconds          = 10
  DebugLog             = $false
}

$script:CfgCache = $null
$script:CfgStamp = [datetime]::MinValue

function Get-Cfg {
  if ($script:CfgCache -and ((Get-Date) - $script:CfgStamp).TotalSeconds -lt 30) {
    return $script:CfgCache
  }
  $cfg = [ordered]@{}
  foreach ($k in $defaultCfg.Keys) { $cfg[$k] = $defaultCfg[$k] }
  if (Test-Path $script:CfgFile) {
    try {
      $user = Get-Content -Path $script:CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in $defaultCfg.Keys) {
        if ($null -ne $user.$k) { $cfg[$k] = $user.$k }
      }
    } catch { }
  }
  $script:CfgCache = $cfg
  $script:CfgStamp = Get-Date
  return $cfg
}

function Save-Cfg($cfg) {
  $out = [ordered]@{}
  foreach ($k in $defaultCfg.Keys) {
    if ($null -ne $cfg[$k]) { $out[$k] = $cfg[$k] } else { $out[$k] = $defaultCfg[$k] }
  }
  $tmp = $script:CfgFile + '.tmp'
  ($out | ConvertTo-Json) | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $script:CfgFile -Force
  $script:CfgCache = $null
}

# ------------------------------------------------------------------ log ----

function Write-Log([string]$msg, [string]$level = 'INFO') {
  if ($level -eq 'DEBUG' -and -not $script:DebugLog) { return }
  $line = '{0} {1,-5} {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $level, $msg
  try {
    if ((Test-Path $script:LogFile) -and ((Get-Item $script:LogFile).Length -gt 1048576)) {
      Move-Item -Path $script:LogFile -Destination ($script:LogFile + '.old') -Force
    }
    [IO.File]::AppendAllText($script:LogFile, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
  } catch { }
  if (-not $script:Quiet) { Write-Host $line }
}

# ----------------------------------------------------------------- idle ----

function Get-IdleSeconds {
  if (-not ('BlueBye.IdleTime' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace BlueBye {
  public static class IdleTime {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint Seconds() {
      var lii = new LASTINPUTINFO();
      lii.cbSize = (uint)Marshal.SizeOf(lii);
      if (!GetLastInputInfo(ref lii)) return 0;
      return ((uint)Environment.TickCount - lii.dwTime) / 1000;
    }
  }
}
'@
  }
  return [BlueBye.IdleTime]::Seconds()
}

# ---------------------------------------------------------------- winrt ----

$script:AsTask = $null

function Initialize-WinRT {
  if ($script:AsTask) { return $true }
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $script:AsTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    return [bool]$script:AsTask
  } catch {
    return $false
  }
}

function Await-Result($op, [Type]$resultType, [int]$timeoutMs = 15000) {
  $m = $script:AsTask.MakeGenericMethod($resultType)
  $t = $m.Invoke($null, @($op))
  if (-not $t.Wait($timeoutMs)) { throw ("winrt timeout after {0} ms" -f $timeoutMs) }
  return $t.Result
}

function Test-HeartbeatFresh([int]$maxAgeSeconds = 60) {
  $s = Read-Status
  if (-not $s) { return $false }
  try {
    $ts = [datetime]::Parse([string]$s.ts, [Globalization.CultureInfo]::InvariantCulture)
    return (((Get-Date) - $ts).TotalSeconds -le $maxAgeSeconds)
  } catch { return $false }
}

# ----------------------------------------------------------- bluetooth ----

function Get-BtRadio {
  if (-not (Initialize-WinRT)) { return $null }
  try {
    [void][Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
    $list = Await-Result ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
    foreach ($r in $list) {
      if ($r.Kind.ToString() -eq 'Bluetooth') { return $r }
    }
  } catch {
    Write-Log ("radio query failed: " + $_.Exception.Message) 'ERROR'
  }
  return $null
}

function Get-BtState {
  $r = Get-BtRadio
  if (-not $r) { return 'Missing' }
  try { return $r.State.ToString() } catch { return 'Unknown' }
}

function Get-BtName {
  $r = Get-BtRadio
  if (-not $r) { return '' }
  try { return $r.Name } catch { return '' }
}

function Set-BtRadio([bool]$enable) {
  $want = if ($enable) { 'On' } else { 'Off' }
  $radio = Get-BtRadio
  if (-not $radio) { return 'no-radio' }
  try {
    if ($radio.State.ToString() -eq $want) { return 'already' }
  } catch { }

  try {
    [void][Windows.Devices.Radios.RadioAccessStatus]
    $access = Await-Result ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
    if ($access.ToString() -ne 'Allowed') { return ("access-" + $access.ToString()) }
    $target = if ($enable) { [Windows.Devices.Radios.RadioState]::On } else { [Windows.Devices.Radios.RadioState]::Off }
    $st = Await-Result ($radio.SetStateAsync($target)) ([Windows.Devices.Radios.RadioAccessStatus])
    if ($st.ToString() -ne 'Allowed') { return ("status-" + $st.ToString()) }
  } catch {
    return ("error:" + $_.Exception.Message)
  }

  for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Milliseconds 250
    if ((Get-BtState) -eq $want) { return 'ok' }
  }
  return 'verify-failed'
}

# --------------------------------------------------------------- media ----

function Get-MediaState {
  $result = [pscustomobject]@{ Sessions = @(); Playing = 0; CallLike = 0; Ok = $false; PlayingApps = '' }
  if (-not (Initialize-WinRT)) { return $result }
  try {
    [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $t = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
    $mgr = Await-Result ($t::RequestAsync()) $t
    if (-not $mgr) { return $result }
    $list = @()
    foreach ($s in $mgr.GetSessions()) {
      $pi = $s.GetPlaybackInfo()
      $list += [pscustomobject]@{
        Session  = $s
        App      = $s.SourceAppUserModelId
        Status   = $pi.PlaybackStatus.ToString()
        CanPause = [bool]$pi.Controls.IsPauseEnabled
        CanPlay  = [bool]$pi.Controls.IsPlayEnabled
      }
    }
    $result.Sessions = $list
    $result.Playing  = @($list | Where-Object { $_.Status -eq 'Playing' }).Count
    $result.CallLike = @($list | Where-Object { $_.Status -eq 'Playing' -and -not $_.CanPause }).Count
    $result.PlayingApps = (@($list | Where-Object { $_.Status -eq 'Playing' } | ForEach-Object { $_.App }) -join ', ')
    $result.Ok = $true
  } catch {
    Write-Log ("media query failed: " + $_.Exception.Message) 'ERROR'
  }
  return $result
}

function Pause-Media($media) {
  $paused = @()
  foreach ($s in $media.Sessions) {
    if ($s.Status -ne 'Playing' -or -not $s.CanPause) { continue }
    try {
      if (Await-Result ($s.Session.TryPauseAsync()) ([bool])) {
        $paused += [string]$s.App
        Write-Log ("paused: " + $s.App) 'ACT'
      }
    } catch {
      Write-Log ("pause failed for " + $s.App + ": " + $_.Exception.Message) 'ERROR'
    }
  }
  return $paused
}

# Remember exactly which players *we* paused, so a later "resume" never
# starts something the user had paused themselves.
function Read-ResumeList {
  if (-not (Test-Path $script:ResumeFile)) { return @() }
  try {
    $o = Get-Content -Path $script:ResumeFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($o -and $o.apps) {
      $ts = $null
      try { $ts = [datetime]::Parse([string]$o.ts, [Globalization.CultureInfo]::InvariantCulture) } catch { }
      if ($ts -and ((Get-Date) - $ts).TotalHours -gt 8) { return @() }   # stale, forget it
      return @($o.apps)
    }
  } catch { }
  return @()
}

function Save-ResumeList($apps) {
  $list = @(Read-ResumeList)
  foreach ($a in @($apps)) {
    if ($a -and ($list -notcontains $a)) { $list += [string]$a }
  }
  if ($list.Count -eq 0) { return }
  $o = [ordered]@{ apps = $list; ts = (Get-Date).ToString('o') }
  try { $o | ConvertTo-Json | Set-Content -Path $script:ResumeFile -Encoding UTF8 } catch { }
}

function Clear-ResumeList {
  if (Test-Path $script:ResumeFile) { Remove-Item -Path $script:ResumeFile -Force -ErrorAction SilentlyContinue }
}

function Resume-Media {
  $apps = @(Read-ResumeList)
  if ($apps.Count -eq 0) { return 0 }
  $media = Get-MediaState
  $n = 0
  foreach ($s in $media.Sessions) {
    if ($s.Status -ne 'Paused' -or -not $s.CanPlay) { continue }
    if ($apps -notcontains $s.App) { continue }
    try {
      if (Await-Result ($s.Session.TryPlayAsync()) ([bool])) {
        $n++
        Write-Log ("resumed: " + $s.App) 'ACT'
      }
    } catch { }
  }
  Clear-ResumeList
  return $n
}

# ------------------------------------------------------------- guards ----

function Test-MicInUse {
  $keys = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged'
  )
  foreach ($k in $keys) {
    if (-not (Test-Path $k)) { continue }
    foreach ($c in (Get-ChildItem -Path $k -ErrorAction SilentlyContinue)) {
      $p = Get-ItemProperty -Path $c.PSPath -ErrorAction SilentlyContinue
      if ($null -ne $p.LastUsedTimeStop -and [int64]$p.LastUsedTimeStop -eq 0) { return $true }
    }
  }
  return $false
}

function Invoke-ExeCapture([string]$file, [string]$arguments, [int]$timeoutMs = 5000) {
  # run a helper exe with a hard timeout; a hung pnputil must not hang the guard
  $outFile = Join-Path $script:Root ('capture-' + [guid]::NewGuid().ToString('N') + '.txt')
  try {
    $p = Start-Process -FilePath $file -ArgumentList $arguments -NoNewWindow -PassThru `
      -RedirectStandardOutput $outFile -ErrorAction Stop
    if (-not $p.WaitForExit($timeoutMs)) {
      try { $p.Kill() } catch { }
      Write-Log ("{0} timed out after {1} ms" -f $file, $timeoutMs) 'ERROR'
      return ''
    }
    if (Test-Path $outFile) { return (Get-Content -Path $outFile -Raw -ErrorAction SilentlyContinue) }
    return ''
  } catch {
    return ''
  } finally {
    Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-ConnectedBtDeviceCount {
  try {
    $txt = Invoke-ExeCapture 'pnputil.exe' '/enum-devices /connected' 5000
    if (-not $txt) { return -1 }
    $m = [regex]::Matches($txt, '(?im)Instance ID:\s+(?:BTHENUM|BTHLE)\\Dev_([0-9A-F]+)')
    $addrs = @($m | ForEach-Object { $_.Groups[1].Value.ToUpper() } | Sort-Object -Unique)
    return $addrs.Count
  } catch {
    return -1
  }
}

function Test-BtHidConnected {
  # pnputil cannot show the HID class through /class Bluetooth (HID nodes live
  # in HIDClass), so stay conservative: more than one connected bluetooth
  # device means one of them may be a mouse or keyboard -> keep the radio on.
  $n = Get-ConnectedBtDeviceCount
  if ($n -lt 0) { return $false }
  if ($n -gt 1) {
    Write-Log ("{0} bluetooth devices connected -> keep the radio on" -f $n) 'SKIP'
    return $true
  }
  return $false
}

function Test-HostRunning {
  try {
    $m = [System.Threading.Mutex]::OpenExisting('Local\BlueByeHost')
    $m.Dispose()
    return $true
  } catch {
    return $false
  }
}

# --------------------------------------------------------------- state ----

function Read-State {
  if (-not (Test-Path $script:StateFile)) { return $null }
  try { return Get-Content -Path $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Save-State([string]$phase, [bool]$seenAway = $false, [string]$since = '') {
  if (-not $since) { $since = (Get-Date).ToString('o') }
  $o = [ordered]@{ phase = $phase; since = $since; seenAway = $seenAway }
  $tmp = $script:StateFile + '.tmp'
  try {
    ($o | ConvertTo-Json) | Set-Content -Path $tmp -Encoding UTF8 -ErrorAction Stop
    Move-Item -Path $tmp -Destination $script:StateFile -Force -ErrorAction Stop
  } catch {
    Write-Log ("state write failed: " + $_.Exception.Message) 'ERROR'
    throw
  }
}

function Clear-State {
  if (Test-Path $script:StateFile) { Remove-Item -Path $script:StateFile -Force -ErrorAction SilentlyContinue }
}

function Get-Phase {
  $s = Read-State
  if (-not $s) { return '' }
  try { return [string]$s.phase } catch { return '' }
}

# -------------------------------------------------------------- status ----

function Write-StatusFile($idle, $bt, $phase, $media, $cfg) {
  $o = [ordered]@{
    ts          = (Get-Date).ToString('o')
    idleSeconds = [int]$idle
    bt          = [string]$bt
    phase       = [string]$phase
    enabled     = [bool]$cfg.Enabled
    playing     = ''
    sessions    = 0
    callLike    = 0
    hostPid     = $PID
  }
  if ($media) {
    $o.sessions = [int]$media.Sessions.Count
    $o.callLike = [int]$media.CallLike
    $o.playing  = [string]$media.PlayingApps
  }
  $tmp = $script:StatusFile + '.tmp'
  try {
    ($o | ConvertTo-Json) | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $script:StatusFile -Force
  } catch { }
}

function Read-Status {
  if (-not (Test-Path $script:StatusFile)) { return $null }
  try { return Get-Content -Path $script:StatusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

# ---------------------------------------------------------------- tick ----

function Invoke-Tick {
  $cfg = Get-Cfg
  $script:DebugLog = [bool]$cfg.DebugLog

  $now   = Get-Date
  $idle  = Get-IdleSeconds
  $phase = Get-Phase
  $bt    = Get-BtState
  $media = $null
  if ($bt -eq 'On') { $media = Get-MediaState }
  Write-StatusFile $idle $bt $phase $media $cfg

  Write-Log ("tick idle={0}s phase={1} bt={2}" -f $idle, $(if ($phase) { $phase } else { '-' }), $bt) 'DEBUG'

  # 0. the radio is off because of us
  if ($phase -eq 'radiooff') {
    $st = Read-State
    $seen = $false
    if ($st -and $null -ne $st.seenAway) { $seen = [bool]$st.seenAway }
    $awayIdle = [int]$cfg.IdleMinutes * 60
    $sinceStr = ''
    if ($st) { try { $sinceStr = [string]$st.since } catch { } }

    # coming back always wins - even when the guard is switched off, and also
    # when the adapter reads Off/Missing/Unknown (a USB dongle can drop off the bus)
    if ($seen -and $idle -le [int]$cfg.RestoreIdleSeconds) {
      $r = Set-BtRadio $true
      Write-Log ("back at the desk (idle {0}s, bt was {1}) -> bluetooth on: {2}" -f $idle, $bt, $r) 'ACT'
      if ($r -eq 'ok' -or $r -eq 'already') { Clear-State }
      return
    }

    # "leave now" is pressed while somebody is still at the keyboard, so wait
    # until the desk really went idle before the come-back path may fire
    if (-not $seen -and $idle -ge $awayIdle) {
      try { Save-State 'radiooff' $true $sinceStr } catch { }
    }

    # safety net: never leave the radio off for more than a day
    $since = $null
    try { $since = [datetime]::Parse($sinceStr, [Globalization.CultureInfo]::InvariantCulture) } catch { }
    if ($since -and ($now - $since).TotalHours -ge 24) {
      $r = Set-BtRadio $true
      Write-Log ("radiooff older than 24h -> bluetooth on: {0}" -f $r) 'ACT'
      if ($r -eq 'ok' -or $r -eq 'already') { Clear-State }
    }
    return
  }
  if ($phase -and $bt -eq 'On' -and $idle -le [int]$cfg.RestoreIdleSeconds) {
    Clear-State
    return
  }

  if (-not [bool]$cfg.Enabled) { return }

  # 1. the desk is attended
  if ($idle -lt ([int]$cfg.IdleMinutes * 60)) {
    if ($phase -eq 'paused') { Clear-State }
    return
  }

  # 2. off-hours only; start == end means "never"
  $start = [int]$cfg.NightStartHour
  $end = [int]$cfg.NightEndHour
  if ($start -eq $end) { return }
  $h = $now.Hour
  if ($start -lt $end) { $inNight = ($h -ge $start -and $h -lt $end) }
  else { $inNight = ($h -ge $start -or $h -lt $end) }
  if (-not $inNight) { return }

  # 3. no radio, nothing to do
  if ($bt -ne 'On') { return }
  if (-not $media) { $media = Get-MediaState }

  # 4. somebody talking is not somebody away
  if ([bool]$cfg.SkipOnCallSession -and $media.CallLike -gt 0) {
    Write-Log ("call-like media session active ({0}) -> skip" -f $media.CallLike) 'SKIP'
    return
  }
  if ([bool]$cfg.SkipWhenMicInUse -and (Test-MicInUse)) {
    Write-Log 'microphone in use -> skip' 'SKIP'
    return
  }

  if ($phase -eq 'paused') {
    $since = $null
    try { $since = [datetime]::Parse([string](Read-State).since, [Globalization.CultureInfo]::InvariantCulture) } catch { }
    if ($since -and (($now - $since).TotalMinutes -lt [double]$cfg.RadioOffDelayMinutes)) { return }
  } else {
    if ([bool]$cfg.PauseMedia -and $media.Playing -gt 0) {
      $pausedApps = @(Pause-Media $media)
      $n = $pausedApps.Count
      if ($n -gt 0) { Save-ResumeList $pausedApps }
      Write-Log ("desk idle {0} min -> paused {1} media session(s)" -f [int]($idle / 60), $n) 'ACT'
      Save-State 'paused'
      if ($n -gt 0 -and [double]$cfg.RadioOffDelayMinutes -gt 0) { return }
    }
  }

  if (-not [bool]$cfg.TurnOffBluetooth) { return }

  # never yank the audio device out from under something that is still playing
  $probe = Get-MediaState
  if (-not $probe.Ok) {
    Write-Log 'media state unavailable -> keep the radio on' 'SKIP'
    return
  }
  if ($probe.Playing -gt 0) {
    if (-not [bool]$cfg.PauseMedia) {
      Write-Log 'media is playing and PauseMedia is off -> keep the radio on' 'SKIP'
      return
    }
    $more = @(Pause-Media $probe)
    if ($more.Count -gt 0) { Save-ResumeList $more; Start-Sleep -Milliseconds 800 }
    $probe = Get-MediaState
    if ($probe.Playing -gt 0) {
      Write-Log 'media still playing -> keep the radio on' 'SKIP'
      return
    }
  }

  if (Test-BtHidConnected) {
    Write-Log 'a bluetooth HID device is connected -> keep the radio on' 'SKIP'
    return
  }

  # intent first: if we cannot record it, do not touch the radio at all
  try { Save-State 'radiooff' $true } catch {
    Write-Log 'could not record intent, skipping radio off' 'ERROR'
    return
  }
  $r = Set-BtRadio $false
  Write-Log ("desk idle {0} min -> bluetooth off: {1}" -f [int]($idle / 60), $r) 'ACT'
  if ($r -eq 'ok' -or $r -eq 'already') {
    Write-StatusFile $idle 'Off' 'radiooff' $null $cfg
    return
  }
  # the switch failed - try to put it back, otherwise keep the intent so the
  # restore path retries as soon as somebody touches the machine
  Write-Log ("bluetooth off failed: {0}" -f $r) 'ERROR'
  $back = Set-BtRadio $true
  if ($back -eq 'ok' -or $back -eq 'already') { Clear-State }
}

# ---------------------------------------------------------------- host ----

function Invoke-Host {
  $mutex = $null
  $acquired = $false
  try {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\BlueByeHost')
    try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  } catch {
    $acquired = $true
  }
  if (-not $acquired) { return }

  # a fresh host (logon / manual start) means the user wants the guard on again
  $stoppedFlag = Join-Path $script:Root 'stopped.flag'
  if (Test-Path $stoppedFlag) { Remove-Item $stoppedFlag -Force -ErrorAction SilentlyContinue }

  Write-Log 'host started' 'INFO'
  try {
    $radio = Get-BtRadio
    if ($radio) {
      $access = Await-Result ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
      Write-Log ("radio: " + $radio.Name + " state=" + $radio.State + " access=" + $access.ToString()) 'INFO'
    } else {
      Write-Log 'radio: not found' 'INFO'
    }
  } catch {
    Write-Log ("radio probe failed: " + $_.Exception.Message) 'ERROR'
  }
  $beat = Get-Date
  while ($true) {
    # if the supervisor that started us is gone, do not linger as an orphan
    # holding the mutex (a plain task stop would otherwise leave one behind).
    # A named mutex is PID-reuse proof; the parent-process name is the fallback
    # for an older supervisor that does not publish the mutex yet.
    if ($script:SupervisorPid -gt 0) {
      $alive = $false
      try {
        $m2 = [System.Threading.Mutex]::OpenExisting('Local\BlueByeSupervisorAlive')
        $m2.Dispose()
        $alive = $true
      } catch { }
      if (-not $alive) {
        try {
          $pp = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $script:SupervisorPid) -ErrorAction Stop
          if ($pp -and $pp.Name -eq 'BlueByeSupervisor.exe') { $alive = $true }
        } catch { }
      }
      if (-not $alive) {
        Write-Log 'supervisor is gone -> host exits' 'INFO'
        return
      }
    }
    try {
      Invoke-Tick
      if (((Get-Date) - $beat).TotalHours -ge 1) {
        Write-Log 'host alive' 'INFO'
        $beat = Get-Date
      }
    } catch {
      Write-Log ("tick error: " + $_.Exception.Message) 'ERROR'
    }
    $sleep = 10
    try {
      $cfg = Get-Cfg
      $sleep = [int]$cfg.TickSeconds
    } catch { }
    if ($sleep -lt 2) { $sleep = 2 }
    if ($sleep -gt 300) { $sleep = 300 }
    Start-Sleep -Seconds $sleep
  }
}
