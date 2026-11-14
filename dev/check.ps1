# dev/check.ps1 - parse every PowerShell file with the AST parser (no execution).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File dev/check.ps1
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$files = @()
$files += Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -ErrorAction SilentlyContinue
$files += Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File -ErrorAction SilentlyContinue
$files += Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue

$bad = 0
foreach ($f in $files) {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
  $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
  if ($errs -and $errs.Count -gt 0) {
    $bad++
    "FAIL $rel"
    foreach ($e in $errs) { "  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message }
  } else {
    "ok   $rel"
  }
}
if ($bad -eq 0) { 'all parsed' } else { "`n$bad file(s) failed" }
