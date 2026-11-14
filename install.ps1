# install.ps1 - install BlueBye for the current user.
# Copies the program to %LOCALAPPDATA%\BlueBye, writes a default config,
# builds an icon + desktop shortcut and registers the logon task that keeps
# the hidden guard host alive.
#
# This file contains Chinese string literals, so it must be saved as UTF-8
# WITH BOM (see set-bom.ps1).

param([switch]$NoStart, [switch]$NoShortcut)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$src      = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst      = Join-Path $env:LOCALAPPDATA 'BlueBye'
$taskName = 'BlueBye-Host'
$sid      = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---- migrate from the previous "AwayGuard / 下班守护" build ----
$legacyDir = Join-Path $env:LOCALAPPDATA 'AwayGuard'
$legacyTasks = @('AwayGuard-Host', 'AwayGuard-Watchdog')
$legacyLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) '下班守护.lnk'
if ((Test-Path $legacyDir) -or (Test-Path $legacyLnk) -or (Get-ScheduledTask -TaskName $legacyTasks[0] -ErrorAction SilentlyContinue)) {
  Write-Host '发现旧版安装，正在迁移…'
  foreach ($t in $legacyTasks) {
    Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
  }
  Get-Process -Name 'AwayGuardSupervisor' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
      $_.CommandLine -and $_.CommandLine -match 'away-guard\.ps1' -and $_.CommandLine -match '-Mode\s+Host'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  if (Test-Path $legacyLnk) { Remove-Item -LiteralPath $legacyLnk -Force -ErrorAction SilentlyContinue }
  if (Test-Path $legacyDir) { Remove-Item -LiteralPath $legacyDir -Recurse -Force -ErrorAction SilentlyContinue }
  Write-Host '旧版已清理'
}

Write-Host "安装到: $dst"

New-Item -ItemType Directory -Path $dst -Force | Out-Null
foreach ($f in @('bluebye-lib.ps1', 'bluebye.ps1', 'bluebye-ui.ps1', 'uninstall.ps1')) {
  Copy-Item -Path (Join-Path $src $f) -Destination (Join-Path $dst $f) -Force
}

# the Chinese scripts only parse when they carry a UTF-8 BOM - self heal it
function Ensure-Bom([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
  $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))
  Write-Host ("补写 BOM: " + (Split-Path -Leaf $path))
}
foreach ($f in @('bluebye-ui.ps1', 'uninstall.ps1')) { Ensure-Bom (Join-Path $dst $f) }

# ------------------------------------------------------------ default cfg ----

$cfgPath = Join-Path $dst 'config.json'
if (-not (Test-Path $cfgPath)) {
  $cfg = @'
{
  "Enabled": true,
  "NightStartHour": 19,
  "NightEndHour": 7,
  "IdleMinutes": 30,
  "RadioOffDelayMinutes": 10,
  "RestoreIdleSeconds": 60,
  "PauseMedia": true,
  "TurnOffBluetooth": true,
  "SkipOnCallSession": true,
  "SkipWhenMicInUse": true,
  "TickSeconds": 10,
  "DebugLog": false
}
'@
  Set-Content -Path $cfgPath -Value $cfg -Encoding ASCII
  Write-Host '已写入默认 config.json'
}

# ------------------------------------------------------------------- icon ----

Add-Type -AssemblyName System.Drawing

function Add-RoundRect($gp, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  if ($r -lt 0.5) { $r = 0.5 }
  $d = $r * 2
  if ($d -gt $w) { $d = $w }
  if ($d -gt $h) { $d = $h }
  $gp.AddArc($x, $y, $d, $d, 180, 90)
  $gp.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $gp.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $gp.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $gp.CloseFigure()
}

function Write-IcoFile($bitmaps, [string]$path) {
  $ms = New-Object IO.MemoryStream
  $bw = New-Object IO.BinaryWriter($ms)
  $bw.Write([UInt16]0)
  $bw.Write([UInt16]1)
  $bw.Write([UInt16]$bitmaps.Count)
  $pngs = @()
  foreach ($bmp in $bitmaps) {
    $pms = New-Object IO.MemoryStream
    $bmp.Save($pms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += , $pms.ToArray()
    $pms.Dispose()
  }
  $offset = 6 + (16 * $bitmaps.Count)
  for ($i = 0; $i -lt $bitmaps.Count; $i++) {
    $bmp = $bitmaps[$i]
    $w = if ($bmp.Width -ge 256) { 0 } else { $bmp.Width }
    $h = if ($bmp.Height -ge 256) { 0 } else { $bmp.Height }
    $bw.Write([byte]$w)
    $bw.Write([byte]$h)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$pngs[$i].Length)
    $bw.Write([UInt32]$offset)
    $offset += $pngs[$i].Length
  }
  foreach ($png in $pngs) { $bw.Write($png) }
  $bw.Flush()
  [IO.File]::WriteAllBytes($path, $ms.ToArray())
  $bw.Dispose()
  $ms.Dispose()
}

function New-BlueByeIcon([string]$path) {
  $bitmaps = @()
  foreach ($s in @(256, 64, 32, 16)) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $f = $s / 256.0

    $rect = New-Object System.Drawing.RectangleF(0, 0, $s, $s)
    $bg = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RoundRect $bg 0 0 $s $s ([single](56 * $f))
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255, 92, 141, 255), [System.Drawing.Color]::FromArgb(255, 42, 92, 226), 90)
    $g.FillPath($brush, $bg)

    # headband
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single](20 * $f))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arc = New-Object System.Drawing.RectangleF((62 * $f), (70 * $f), (132 * $f), (132 * $f))
    $g.DrawArc($pen, $arc, 180, 180)

    # earcups
    foreach ($c in @(@(44, 116, 38, 74), @(174, 116, 38, 74))) {
      $cp = New-Object System.Drawing.Drawing2D.GraphicsPath
      Add-RoundRect $cp ([single]($c[0] * $f)) ([single]($c[1] * $f)) ([single]($c[2] * $f)) ([single]($c[3] * $f)) ([single](14 * $f))
      $g.FillPath([System.Drawing.Brushes]::White, $cp)
      $cp.Dispose()
    }

    $pen.Dispose()
    $brush.Dispose()
    $bg.Dispose()
    $g.Dispose()
    $bitmaps += $bmp
  }
  Write-IcoFile $bitmaps $path
  foreach ($b in $bitmaps) { $b.Dispose() }
}

$icoPath = Join-Path $dst 'bluebye.ico'
try {
  New-BlueByeIcon $icoPath
  $null = New-Object System.Drawing.Icon($icoPath)
  Write-Host "图标已生成: $icoPath"
} catch {
  Write-Host ("图标生成失败（用系统图标代替）: " + $_.Exception.Message)
  $icoPath = ''
}

# the cute mascot that sits in the window header
try {
  & (Join-Path $src 'make-mascot.ps1') -Path (Join-Path $dst 'mascot.png') | Out-Null
  Write-Host '吉祥物已生成'
} catch {
  Write-Host ("吉祥物生成失败（界面会留空）: " + $_.Exception.Message)
}

# --------------------------------------------------------------- shortcut ----

if (-not $NoShortcut) {
  try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    # remove leftovers from builds where install.ps1 lost its BOM (mojibake name)
    Get-ChildItem -Path $desktop -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -ne 'BlueBye.lnk' -and ($_.Name -match '涓|彮|瀹|堟|姢')
    } | ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
      Write-Host ("清理旧乱码快捷方式: " + $_.Name)
    }
    $lnkPath = Join-Path $desktop 'BlueBye.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath = $psExe
    $sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dst 'bluebye-ui.ps1') + '"'
    $sc.WorkingDirectory = $dst
    if ($icoPath) { $sc.IconLocation = $icoPath } else { $sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,15" }
    $sc.Description = 'BlueBye · 离开后暂停播放并断开蓝牙耳机'
    $sc.WindowStyle = 7
    $sc.Save()
    Write-Host "桌面快捷方式: $lnkPath"
  } catch {
    Write-Host ("快捷方式创建失败: " + $_.Exception.Message)
  }
}

# ---------------------------------------------------------- stop old host ----

$stopFile = Join-Path $dst 'supervisor.stop'
try { Set-Content -Path $stopFile -Value 'stop' -Encoding ASCII } catch { }
Get-Process -Name 'BlueByeSupervisor' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "停止旧守护器 pid=$($_.Id)"
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 300
Remove-Item -Path $stopFile -Force -ErrorAction SilentlyContinue

try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {
    $_.CommandLine -and $_.CommandLine -match 'bluebye\.ps1' -and $_.CommandLine -match '-Mode\s+Host'
  } | ForEach-Object {
    Write-Host "停止旧宿主进程 pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
} catch {
  Write-Host ("无法枚举旧进程: " + $_.Exception.Message)
}

# ------------------------------------------------------- supervisor binary ----
# A tiny compiled launcher without a console window. A console process gets
# killed by CTRL_C/CTRL_CLOSE (exit code 0xC000013A) when its console goes away,
# which is exactly how the first version died overnight. A WindowsApplication
# has no console at all, and it also restarts the host if PowerShell ever exits.

$cs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

public static class BlueByeSupervisor {
  public static void Main() {
    string dir = AppDomain.CurrentDomain.BaseDirectory;
    string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
    string script = Path.Combine(dir, "bluebye.ps1");
    string log = Path.Combine(dir, "supervisor.log");
    string stop = Path.Combine(dir, "supervisor.stop");

    // the host watches this mutex to notice that its supervisor died; the OS
    // releases it when this process goes away, so it cannot go stale like a PID
    var alive = new System.Threading.Mutex(true, "Local\\BlueByeSupervisorAlive");

    while (true) {
      if (File.Exists(stop)) {
        try { File.Delete(stop); } catch { }
        break;
      }
      try {
        var psi = new ProcessStartInfo(ps);
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Mode Host -ParentPid " + Process.GetCurrentProcess().Id;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        var p = Process.Start(psi);
        p.WaitForExit();
        try {
          File.AppendAllText(log, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " host exited code=" + p.ExitCode + "\r\n");
        } catch { }
      } catch (Exception ex) {
        try { File.AppendAllText(log, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " supervisor error: " + ex.Message + "\r\n"); } catch { }
      }
      Thread.Sleep(5000);
    }
  }
}
'@

$supervisor = Join-Path $dst 'BlueByeSupervisor.exe'
$tmpExe = Join-Path $dst 'BlueByeSupervisor.tmp.exe'
Remove-Item -Path $tmpExe -Force -ErrorAction SilentlyContinue
try {
  Add-Type -TypeDefinition $cs -OutputAssembly $tmpExe -OutputType WindowsApplication
  Move-Item -Path $tmpExe -Destination $supervisor -Force
  Write-Host "守护器已编译: $supervisor"
} catch {
  Write-Host ("守护器编译失败: " + $_.Exception.Message)
  if (Test-Path $tmpExe) { Remove-Item $tmpExe -Force -ErrorAction SilentlyContinue }
}

# never register a task that points at a missing binary
if (-not (Test-Path $supervisor) -or ((Get-Item $supervisor).Length -lt 1024)) {
  throw '守护器编译失败，已中止安装（不会注册指向不存在程序的任务）。请确认 .NET Framework 4.x 可用后重试。'
}
Write-Host ("守护器大小: " + (Get-Item $supervisor).Length + " bytes")

# ------------------------------------------------------------- task setup ----

$engine = Join-Path $dst 'bluebye.ps1'

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\$taskName</URI>
    <Description>BlueBye: pause media and switch the Bluetooth radio off when the desk is unattended, restore it when the user is back.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$sid</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$supervisor</Command>
      <Arguments></Arguments>
    </Exec>
  </Actions>
</Task>
"@

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Xml $xml -Force | Out-Null
Write-Host "开机任务已注册: $taskName"

# watchdog: every 20 minutes, restart the host if it is not running
# (Test-HostRunning is a mutex probe, so a healthy host costs ~200 ms)
$wdName = 'BlueBye-Watchdog'
$wdArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $engine + '" -Mode Ensure'
$wdXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\$wdName</URI>
    <Description>BlueBye watchdog: make sure the background host is alive.</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2026-11-14T00:00:00</StartBoundary>
      <Repetition>
        <Interval>PT20M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$psExe</Command>
      <Arguments>$wdArgs</Arguments>
    </Exec>
  </Actions>
</Task>
"@
Register-ScheduledTask -TaskName $wdName -Xml $wdXml -Force | Out-Null
Write-Host "看门狗任务已注册: $wdName"

if (-not $NoStart) {
  Start-ScheduledTask -TaskName $taskName
  Start-Sleep -Seconds 3
}

$t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Write-Host ("任务状态: " + $(if ($t) { $t.State } else { '缺失' }))
$w = Get-ScheduledTask -TaskName $wdName -ErrorAction SilentlyContinue
Write-Host ("看门狗状态: " + $(if ($w) { $w.State } else { '缺失' }))
Write-Host ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File $engine -Mode Status
