# dev/test-tray.ps1 - end-to-end check of the tray behaviour.
$ErrorActionPreference = 'Continue'

function Get-Ui { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'bluebye-ui' } }
function Get-Sup { Get-CimInstance Win32_Process -Filter "Name='BlueByeSupervisor.exe'" }

'--- cleanup ---'
Stop-ScheduledTask -TaskName 'BlueBye-Tray' -ErrorAction SilentlyContinue
Get-Ui | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Sup | Where-Object { $_.CommandLine -match '--tray' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3

'--- start tray task ---'
Start-ScheduledTask -TaskName 'BlueBye-Tray'
Start-Sleep -Seconds 7
"task state : $((Get-ScheduledTask -TaskName 'BlueBye-Tray').State)"
$ui = Get-Ui
"ui count   : $(@($ui).Count)"
$ui | ForEach-Object { "  pid=$($_.ProcessId) tray=$($_.CommandLine -match '-Tray')" }

'--- double-click the shortcut -> window must appear ---'
Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'BlueBye.lnk')
Start-Sleep -Seconds 6
$w = Get-Process | Where-Object { $_.MainWindowTitle -like '*BlueBye*' }
"windows    : $(@($w).Count)"
$w | ForEach-Object { "  pid=$($_.Id) title='$($_.MainWindowTitle)'" }

'--- close the window -> hide, keep running ---'
$target = @($w)[0]
if ($target) {
  [void]$target.CloseMainWindow()
  Start-Sleep -Seconds 3
  "alive after close: $([bool](Get-Process -Id $target.Id -ErrorAction SilentlyContinue))"
  "windows after close: $(@(Get-Process | Where-Object { $_.MainWindowTitle -like '*BlueBye*' }).Count)"
}

'--- survive 25 seconds (no console-control kill) ---'
Start-Sleep -Seconds 25
$ui2 = Get-Ui
"ui after 25s: $(@($ui2).Count)"
"task state : $((Get-ScheduledTask -TaskName 'BlueBye-Tray').State)"
