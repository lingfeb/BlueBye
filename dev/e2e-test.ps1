# e2e-test.ps1 - end to end check of the installed AwayGuard.
#
# Because a human is normally sitting at the machine while this runs, the test
# makes "restore" impossible first (RestoreIdleSeconds = -1) so the off state
# can be observed, then puts the threshold back so the host restores by itself.
#
# ASCII only.

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$inst = Join-Path $env:LOCALAPPDATA 'AwayGuard'
$exe = Join-Path $inst 'away-guard.ps1'
$cfgPath = Join-Path $inst 'config.json'
$taskName = 'AwayGuard-Host'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SimInput {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
  public static void Jiggle() {
    var inp = new INPUT[1];
    inp[0].type = 0;
    inp[0].mi.dx = 1; inp[0].mi.dy = 1;
    inp[0].mi.dwFlags = 0x0001;
    SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@

function Engine([string]$m) { (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exe -Mode $m 2>&1 | Out-String).Trim() }

function BtState {
  $s = Engine 'Status'
  if ($s -match 'bluetooth\s*:\s*(\w+)') { return $matches[1] }
  return '?'
}

function Restart-Host {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 800
  Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

function Set-ConfigValue([string]$name, $value) {
  $c = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $c.$name = $value
  $c | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8
}

$orig = Get-Content -Path $cfgPath -Raw -Encoding UTF8

'--- setup -------------------------------------------------'
Set-ConfigValue 'RestoreIdleSeconds' -1     # the host must not restore during step 2
Restart-Host
"bt before       : $(BtState)"

'--- 1. leave-now: pause media + bluetooth off ------------'
(Engine 'Night') -split "`n" | ForEach-Object { if ($_.Trim()) { "  $_" } }
$off = BtState
"bt after night  : $off"

'--- 2. must stay off while the host keeps ticking --------'
Start-Sleep -Seconds 13
$stay = BtState
"bt after 13s    : $stay"

'--- 3. host restores by itself once the user is back -----'
Set-ConfigValue 'RestoreIdleSeconds' 60
Restart-Host
[SimInput]::Jiggle()
Start-Sleep -Seconds 4
$back = BtState
"bt after return : $back"

'--- teardown ---------------------------------------------'
$c = $orig | ConvertFrom-Json
$c.DebugLog = $false
$c | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8
Restart-Host
Engine 'Resume' | Out-Null

'--- result -----------------------------------------------'
"1. night mode switched bt off : " + $(if ($off -eq 'Off') { 'PASS' } else { "FAIL ($off)" })
"2. stayed off while unattended: " + $(if ($stay -eq 'Off') { 'PASS' } else { "FAIL ($stay)" })
"3. restored on return         : " + $(if ($back -eq 'On') { 'PASS' } else { "FAIL ($back)" })
''
'--- log tail ---------------------------------------------'
Get-Content -Path (Join-Path $inst 'guard.log') -Tail 12 -Encoding UTF8 | ForEach-Object { "  $_" }
