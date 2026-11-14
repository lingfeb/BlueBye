# make-mascot.ps1 - draw the chibi headphone mascot as a PNG (transparent bg).
# Cool blue palette so it fits a neutral / boyish cute style.
# ASCII only. Usage: powershell -File make-mascot.ps1 -Path mascot.png [-Preview]

param(
  [string]$Path = 'mascot.png',
  [switch]$Preview,
  [int]$Size = 256
)

Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$f = $Size / 256.0
function S([single]$v) { return [single]($v * $f) }

$blue      = [System.Drawing.Color]::FromArgb(255, 86, 184, 232)
$blueDeep  = [System.Drawing.Color]::FromArgb(255, 52, 148, 208)
$blueLight = [System.Drawing.Color]::FromArgb(255, 169, 220, 245)
$face      = [System.Drawing.Color]::FromArgb(255, 255, 244, 232)
$faceLine  = [System.Drawing.Color]::FromArgb(255, 243, 223, 204)
$ink       = [System.Drawing.Color]::FromArgb(255, 43, 51, 80)
$blush     = [System.Drawing.Color]::FromArgb(140, 255, 190, 160)
$mouthCol  = [System.Drawing.Color]::FromArgb(255, 240, 138, 110)
$starCol   = [System.Drawing.Color]::FromArgb(255, 255, 198, 77)

# ---- headband ----
$bandPen = New-Object System.Drawing.Pen($blue, (S 20))
$bandPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$bandPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$bandRect = New-Object System.Drawing.RectangleF((S 52), (S 72), (S 152), (S 152))
$g.DrawArc($bandPen, $bandRect, 195, 150)

# ---- face ----
$faceBrush = New-Object System.Drawing.SolidBrush($face)
$faceRect = New-Object System.Drawing.RectangleF((S 54), (S 64), (S 148), (S 148))
$g.FillEllipse($faceBrush, $faceRect)
$facePen = New-Object System.Drawing.Pen($faceLine, (S 2))
$g.DrawEllipse($facePen, $faceRect)

# ---- earcups ----
function Add-Round($gp, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $d = $r * 2
  $gp.AddArc($x, $y, $d, $d, 180, 90)
  $gp.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $gp.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $gp.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $gp.CloseFigure()
}
$cupBrush = New-Object System.Drawing.SolidBrush($blue)
foreach ($cx in @(30, 190)) {
  $cp = New-Object System.Drawing.Drawing2D.GraphicsPath
  Add-Round $cp (S $cx) (S 112) (S 36) (S 66) (S 17)
  $g.FillPath($cupBrush, $cp)
  $cp.Dispose()
}
$cupHi = New-Object System.Drawing.SolidBrush($blueLight)
foreach ($cx in @(38, 198)) {
  $cp = New-Object System.Drawing.Drawing2D.GraphicsPath
  Add-Round $cp (S $cx) (S 126) (S 10) (S 26) (S 5)
  $g.FillPath($cupHi, $cp)
  $cp.Dispose()
}

# ---- eyes ----
$eyeBrush = New-Object System.Drawing.SolidBrush($ink)
$eyeWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.FillEllipse($eyeBrush, (S 92), (S 118), (S 28), (S 34))
$g.FillEllipse($eyeBrush, (S 136), (S 118), (S 28), (S 34))
$g.FillEllipse($eyeWhite, (S 99), (S 124), (S 10), (S 10))
$g.FillEllipse($eyeWhite, (S 143), (S 124), (S 10), (S 10))
$g.FillEllipse($eyeWhite, (S 104), (S 140), (S 5), (S 5))
$g.FillEllipse($eyeWhite, (S 148), (S 140), (S 5), (S 5))

# ---- blush ----
$blushBrush = New-Object System.Drawing.SolidBrush($blush)
$g.FillEllipse($blushBrush, (S 74), (S 158), (S 34), (S 16))
$g.FillEllipse($blushBrush, (S 148), (S 158), (S 34), (S 16))

# ---- mouth ----
$mouthPen = New-Object System.Drawing.Pen($mouthCol, (S 3.5))
$mouthPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$mouthPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($mouthPen, (New-Object System.Drawing.RectangleF((S 116), (S 156), (S 26), (S 20))), 20, 140)

# ---- sparkle (five point star) ----
$starBrush = New-Object System.Drawing.SolidBrush($starCol)
$cxStar = [single](S 216)
$cyStar = [single](S 46)
$rOut = [single](S 15)
$rIn = [single](S 6.5)
$pts = New-Object 'System.Drawing.PointF[]' 10
for ($i = 0; $i -lt 10; $i++) {
  $ang = [math]::PI / 5 * $i - [math]::PI / 2
  $rr = if ($i % 2 -eq 0) { $rOut } else { $rIn }
  $pts[$i] = New-Object System.Drawing.PointF(($cxStar + $rr * [math]::Cos($ang)), ($cyStar + $rr * [math]::Sin($ang)))
}
$g.FillPolygon($starBrush, $pts)

$bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
if ($Preview) {
  $big = New-Object System.Drawing.Bitmap(($Size * 2), ($Size * 2))
  $g2 = [System.Drawing.Graphics]::FromImage($big)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g2.DrawImage($bmp, 0, 0, ($Size * 2), ($Size * 2))
  $big.Save(($Path -replace '\.png$', '-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
  $g2.Dispose()
  $big.Dispose()
}
$g.Dispose()
$bmp.Dispose()
"wrote $Path"
