# installer/build.ps1 - compile the single-file setup exe.
# Everything the installer needs is embedded as a manifest resource.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File installer/build.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out 'BlueBye-Setup.exe'

$cscCandidates = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe not found - .NET Framework 4.x is required to build the setup exe.' }

$files = @(
  'bluebye-lib.ps1',
  'bluebye.ps1',
  'bluebye-ui.ps1',
  'uninstall.ps1',
  'install.ps1',
  'make-mascot.ps1'
)

$cscArgs = @(
  '/nologo',
  '/codepage:65001',
  '/target:winexe',
  '/optimize+',
  ('/out:' + $exe),
  ('/win32icon:' + (Join-Path $root 'assets\bluebye.ico'))
)
foreach ($f in $files) {
  $cscArgs += ('/resource:' + (Join-Path $root $f) + ',' + $f)
}
$cscArgs += (Join-Path $root 'installer\BlueByeSetup.cs')

& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw ("csc failed with exit code " + $LASTEXITCODE) }
if (-not (Test-Path $exe)) { throw 'setup exe was not produced' }

$size = (Get-Item $exe).Length
Write-Host ("built {0} ({1:N0} bytes)" -f $exe, $size)
