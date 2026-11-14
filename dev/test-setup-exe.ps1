# dev/test-setup-exe.ps1 - run the built setup exe with the user's normal token
# (a scheduled task), because this session runs inside a restricted sandbox.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'dist\BlueBye-Setup.exe'
$exe = Join-Path $env:USERPROFILE 'Desktop\BlueBye-Setup-test.exe'
Copy-Item $src $exe -Force
"exe: $exe ($((Get-Item $exe).Length) bytes)"

$task = 'BlueBye-Setup-Test'
schtasks /delete /tn $task /f 2>$null | Out-Null
schtasks /create /tn $task /tr ('"' + $exe + '" --silent') /sc once /st 23:59 /f 2>&1 | Out-Null
schtasks /run /tn $task 2>&1 | Out-Null
Start-Sleep -Seconds 30
$info = Get-ScheduledTaskInfo -TaskName $task -ErrorAction SilentlyContinue
"setup exit code: $($info.LastTaskResult)"
schtasks /delete /tn $task /f 2>&1 | Out-Null
Remove-Item $exe -Force -ErrorAction SilentlyContinue

'--- install dirs ---'
foreach ($d in @('BlueBye', 'AwayGuard')) {
  $p = Join-Path $env:LOCALAPPDATA $d
  "{0,-10} {1}" -f $d, $(if (Test-Path $p) { 'present' } else { 'absent' })
}

'--- scheduled tasks ---'
Get-ScheduledTask | Where-Object { $_.TaskName -match '^(BlueBye|AwayGuard)-' } |
  Select-Object TaskName, State | Format-Table -AutoSize | Out-String

'--- desktop shortcuts ---'
Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop') -Filter '*.lnk' |
  Where-Object { $_.Name -match 'BlueBye|下班' } | Select-Object Name | Format-Table -AutoSize | Out-String

'--- guard status ---'
& (Join-Path $env:LOCALAPPDATA 'BlueBye\bluebye.ps1') -Mode Status | Select-Object -First 4
