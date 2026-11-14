# uninstall.ps1 - remove BlueBye (task, shortcut, files) for the current user.
# Chinese literals: keep this file UTF-8 WITH BOM.

param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'BlueBye'
$taskName = 'BlueBye-Host'

if (-not $Quiet) {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
  if ('System.Windows.Forms.MessageBox' -as [type]) {
    $r = [System.Windows.Forms.MessageBox]::Show('确定要卸载BlueBye吗？', '卸载', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
  } else {
    $a = Read-Host '确定要卸载BlueBye吗？(y/N)'
    if ($a -notmatch '^(y|yes)$') { return }
  }
}

Write-Host '停止开机任务…'
foreach ($taskName in @('BlueBye-Host', 'BlueBye-Watchdog')) {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host '停止守护进程…'
$stopFile = Join-Path $dst 'supervisor.stop'
if (Test-Path $dst) { Set-Content -Path $stopFile -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue }
Get-Process -Name 'BlueByeSupervisor' -ErrorAction SilentlyContinue | ForEach-Object {
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {
    $_.CommandLine -and $_.CommandLine -match 'bluebye\.ps1' -and $_.CommandLine -match '-Mode\s+Host'
  } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
} catch { }

$desktopDir = [Environment]::GetFolderPath('Desktop')
Get-ChildItem -Path $desktopDir -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -eq 'BlueBye.lnk' -or $_.Name -match '涓|彮|瀹|堟|姢'
} | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  Write-Host ("已删除快捷方式: " + $_.Name)
}

Write-Host '删除程序文件…'
# only the installed program directory - never the source folder this may run from
$targets = @($dst)
foreach ($t in $targets) {
  if ($t -and (Test-Path $t)) {
    Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$left = @($targets | Where-Object { $_ -and (Test-Path $_) })
if ($left.Count -gt 0) {
  # the folder may be busy while this script still lives in it - retry from outside
  foreach ($t in $left) {
    $cmd = 'ping -n 3 127.0.0.1 >nul & rmdir /s /q "' + $t + '"'
    Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmd) -WindowStyle Hidden
  }
}

Write-Host '已卸载。'
