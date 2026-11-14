# dev/inspect-ui.ps1 - objective checks for a UI screenshot when no vision model is available.
#  * pixel probes on the rendered PNG (regions, contrast)
#  * OCR of the screenshot to prove the labels actually rendered
# ASCII only.

param([string]$Png = "$env:LOCALAPPDATA\BlueBye\ui-selftest.png")

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $Png)) { "missing $Png"; exit 1 }
$bmp = [System.Drawing.Bitmap]::FromFile($Png)
"png        : $($bmp.Width)x$($bmp.Height)"

# --- transparency of the outer shadow margin -------------------------------
$c = $bmp.GetPixel(2, 2)
"corner a   : $($c.A)  (expect 0 = frameless rounded window)"

# --- region colours --------------------------------------------------------
function Probe([string]$name, [int]$x, [int]$y) {
  if ($x -lt 0 -or $y -lt 0 -or $x -ge $bmp.Width -or $y -ge $bmp.Height) { return "{0,-12} out of range" -f $name }
  $p = $bmp.GetPixel($x, $y)
  return ('{0,-12} ({1,3},{2,3}) #{3:X2}{4:X2}{5:X2} a={6}' -f $name, $x, $y, $p.R, $p.G, $p.B, $p.A)
}

Probe 'header bg'  480 30
Probe 'shell bg'   700 100
Probe 'card bg'    120 200
Probe 'accent btn' 810 636
Probe 'divider'    600 300

# --- count of accent pixels (buttons / switches / icon) --------------------
$accent = 0
$white = 0
for ($y = 0; $y -lt $bmp.Height; $y += 2) {
  for ($x = 0; $x -lt $bmp.Width; $x += 2) {
    $p = $bmp.GetPixel($x, $y)
    if ($p.R -gt 60 -and $p.R -lt 130 -and $p.G -gt 100 -and $p.G -lt 175 -and $p.B -gt 220) { $accent++ }
    if ($p.R -gt 215 -and $p.G -gt 215 -and $p.B -gt 215) { $white++ }
  }
}
"accent px  : $accent (buttons, switches, logo)"
"light px   : $white (headline text)"

# --- WCAG contrast for the main text pairs ---------------------------------
function Lum([string]$hex) {
  $col = [System.Drawing.ColorTranslator]::FromHtml($hex)
  $channels = @([double]$col.R, [double]$col.G, [double]$col.B)
  $lin = @()
  foreach ($v in $channels) {
    $x = $v / 255.0
    if ($x -le 0.03928) { $lin += ($x / 12.92) } else { $lin += [math]::Pow((($x + 0.055) / 1.055), 2.4) }
  }
  return (0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2])
}
function Ratio([string]$fg, [string]$bg) {
  $a = Lum $fg
  $b = Lum $bg
  if ($a -lt $b) { $t = $a; $a = $b; $b = $t }
  return [math]::Round((($a + 0.05) / ($b + 0.05)), 2)
}
"contrast primary text : $(Ratio '#E7E9F0' '#141821') (>= 4.5 good)"
"contrast muted text   : $(Ratio '#7B8091' '#141821') (>= 4.5 good)"
"contrast section title: $(Ratio '#6B7182' '#0E1015') (>= 4.5 good)"
"contrast footer msg   : $(Ratio '#5F6577' '#0E1015') (>= 4.5 good)"
"contrast button text  : $(Ratio '#FFFFFF' '#4F7FFF') (>= 4.5 good)"

$bmp.Dispose()

# --- OCR: prove the labels really rendered ---------------------------------
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, [Type]$t) { $m = $asTask.MakeGenericMethod($t); $x = $m.Invoke($null, @($op)); $x.Wait(-1) | Out-Null; $x.Result }

  [void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
  [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]

  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  if (-not $engine) { 'ocr        : no engine for current languages'; exit 0 }
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Png)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  $text = ($result.Lines | ForEach-Object { $_.Text }) -join ' | '
  "ocr        : $text"
} catch {
  "ocr        : failed - $($_.Exception.Message)"
}
