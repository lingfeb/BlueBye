param([Parameter(Mandatory = $true)][string]$Path)
# Re-save a UTF-8 (BOM-less) text file as UTF-8 WITH BOM so that Windows
# PowerShell 5.1 parses non-ASCII string literals correctly.
$full = (Resolve-Path -LiteralPath $Path).Path
$text = [IO.File]::ReadAllText($full, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($full, $text, (New-Object Text.UTF8Encoding($true)))
$bytes = Get-Content -LiteralPath $full -Encoding Byte -TotalCount 3
"BOM: " + ($bytes -join ',') + "  file: $full"
