# =============================================================================
# My Train — app icon generator
#
# Draws the icon programmatically (GDI+) at every platform size and writes them
# into android/, ios/, web/ and windows/. Re-runnable: tweak the geometry
# constants below and re-run to regenerate every asset consistently.
#
#   powershell -ExecutionPolicy Bypass -File tool\generate_app_icon.ps1
#
# DESIGN
#   Mark   : head-on train front (rounded-top body, two windows, headlight,
#            two bogies) in solid white — the same silhouette as the in-app
#            brand mark (Icons.train_rounded), so the launcher icon and the
#            header logo read as the same thing.
#   Ground : GlassTheme.accent — violet #8B5CF6 (top-left) to indigo #6366F1
#            (bottom-right), identical to the app's primary buttons.
#   Detail : deliberately only 5 shapes. Anything finer turns to mush at the
#            48px mdpi launcher size, which is the size that decides whether a
#            user spots the app instantly.
# =============================================================================

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ---- brand ----------------------------------------------------------------
$violet = [System.Drawing.Color]::FromArgb(255, 0x8B, 0x5C, 0xF6)
$indigo = [System.Drawing.Color]::FromArgb(255, 0x63, 0x66, 0xF1)

# Geometry on a 1024 grid (scaled per output size).
#
# Deliberately a train FRONT with ONE wide windshield and TWO headlights. An
# earlier pass used two square windows plus a centred bar, which at icon size
# read as a robot face (two eyes + a mouth) rather than a train.
$GRID = 1024.0
$bodyX = 306.0; $bodyY = 214.0; $bodyW = 412.0; $bodyH = 496.0
$bodyTopR = 186.0; $bodyBotR = 58.0
# Single cab windscreen.
$winX = 364.0; $winY = 316.0; $winW = 296.0; $winH = 150.0; $winR = 52.0
# Two headlights low on the nose.
$lampW = 104.0; $lampH = 48.0; $lampR = 24.0; $lampY = 552.0
$lampInset = 36.0
# Track beneath: two bars, wider then narrower, which grounds the mark and
# reads as rails/motion.
$rail1Y = 754.0; $rail1H = 44.0; $rail1Pad = -26.0
$rail2Y = 826.0; $rail2H = 40.0; $rail2Pad = 58.0
$railR = 22.0

function New-RoundedPath {
  param([double]$x, [double]$y, [double]$w, [double]$h, [double]$rTop, [double]$rBot)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $rt = [Math]::Min($rTop, [Math]::Min($w, $h) / 2)
  $rb = [Math]::Min($rBot, [Math]::Min($w, $h) / 2)
  # top-left, top-right, bottom-right, bottom-left
  $p.AddArc($x, $y, $rt * 2, $rt * 2, 180, 90)
  $p.AddArc($x + $w - $rt * 2, $y, $rt * 2, $rt * 2, 270, 90)
  $p.AddArc($x + $w - $rb * 2, $y + $h - $rb * 2, $rb * 2, $rb * 2, 0, 90)
  $p.AddArc($x, $y + $h - $rb * 2, $rb * 2, $rb * 2, 90, 90)
  $p.CloseFigure()
  return $p
}

# Renders one icon.
#   -Rounded : squircle-ish corners with transparent outside (Android legacy, web)
#   -FullBleed: square, fully opaque (iOS — which forbids alpha — and maskable)
#   -GlyphOnly: transparent ground, glyph inset for Android adaptive foreground
function Render-Icon {
  param(
    [int]$Size,
    [string]$Path,
    [ValidateSet('Rounded', 'FullBleed', 'GlyphOnly', 'GroundOnly')]
    [string]$Mode = 'Rounded',
    # Fraction of the canvas the mark occupies. Adaptive foregrounds must stay
    # inside the launcher's safe zone or the mask crops the train's nose off.
    [double]$MarkScale = 1.0
  )

  $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 0)),
    (New-Object System.Drawing.PointF([float]$Size, [float]$Size)),
    $violet, $indigo)
  # GDI+ gradient brushes TILE past their end point by default, which drew a
  # hard seam across the icon where the ramp restarted. Clamp holds the end
  # colour instead.
  $grad.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY

  # ---- ground ----
  if ($Mode -ne 'GlyphOnly') {
    if ($Mode -eq 'Rounded') {
      # ~22.5% radius reads as an iOS squircle at every size.
      $r = $Size * 0.225
      $bg = New-RoundedPath 0 0 $Size $Size $r $r
      $g.FillPath($grad, $bg)
      $bg.Dispose()
    } else {
      $g.FillRectangle($grad, 0, 0, $Size, $Size)
    }

    # Specular sheen: a soft light wash over the top-left, giving the flat
    # gradient the same glassy lift the in-app surfaces have. Kept very low
    # alpha so it never turns into visible banding when downscaled.
    # Spans the FULL height: a shorter ramp ended mid-canvas and tiled, which is
    # what produced the visible horizontal band.
    $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      (New-Object System.Drawing.PointF(0, 0)),
      (New-Object System.Drawing.PointF(0, [float]$Size)),
      [System.Drawing.Color]::FromArgb(54, 255, 255, 255),
      [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $sheen.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY
    if ($Mode -eq 'Rounded') {
      $r = $Size * 0.225
      $bg2 = New-RoundedPath 0 0 $Size $Size $r $r
      $g.FillPath($sheen, $bg2)
      $bg2.Dispose()
    } else {
      $g.FillRectangle($sheen, 0, 0, $Size, $Size)
    }
    $sheen.Dispose()
  }

  if ($Mode -eq 'GroundOnly') {
    $g.Dispose(); $grad.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return
  }

  # ---- mark ----
  # Scale the 1024-grid geometry to this canvas, then shrink about the centre by
  # MarkScale.
  $k = $Size / $GRID
  $state = $g.Save()
  $g.TranslateTransform([float]($Size / 2), [float]($Size / 2))
  $g.ScaleTransform([float]($k * $MarkScale), [float]($k * $MarkScale))
  $g.TranslateTransform([float](-$GRID / 2), [float](-$GRID / 2))

  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

  # Body
  $body = New-RoundedPath $bodyX $bodyY $bodyW $bodyH $bodyTopR $bodyBotR
  $g.FillPath($white, $body)
  $body.Dispose()

  # Rails below the nose.
  $r1 = New-RoundedPath ($bodyX - $rail1Pad) $rail1Y ($bodyW + $rail1Pad * 2) $rail1H $railR $railR
  $r2 = New-RoundedPath ($bodyX + $rail2Pad) $rail2Y ($bodyW - $rail2Pad * 2) $rail2H $railR $railR
  $g.FillPath($white, $r1); $g.FillPath($white, $r2)
  $r1.Dispose(); $r2.Dispose()

  # Cutouts. Painted with a gradient matched to the FULL canvas (in untransformed
  # space) so the windows read as holes punched through to the ground, not as
  # separate coloured shapes.
  $inv = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 0)),
    (New-Object System.Drawing.PointF([float]$GRID, [float]$GRID)),
    $violet, $indigo)
  $inv.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY

  # One wide windscreen.
  $win = New-RoundedPath $winX $winY $winW $winH $winR $winR
  $g.FillPath($inv, $win)
  $win.Dispose()

  # Two headlights.
  $l1 = New-RoundedPath ($bodyX + $lampInset) $lampY $lampW $lampH $lampR $lampR
  $l2 = New-RoundedPath ($bodyX + $bodyW - $lampInset - $lampW) $lampY $lampW $lampH $lampR $lampR
  $g.FillPath($inv, $l1); $g.FillPath($inv, $l2)
  $l1.Dispose(); $l2.Dispose()

  $inv.Dispose()
  $white.Dispose()
  $g.Restore($state)

  $g.Dispose(); $grad.Dispose()

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output ("  {0,-58} {1}x{1}" -f $Path.Replace("$root\", ''), $Size)
}

Write-Output '=== master ==='
Render-Icon -Size 1024 -Path "$root\assets\branding\appicon_master_1024.png" -Mode Rounded
Render-Icon -Size 1024 -Path "$root\assets\branding\appicon_master_square_1024.png" -Mode FullBleed

Write-Output '=== android legacy mipmaps ==='
$android = "$root\android\app\src\main\res"
@{ 'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96; 'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192 }.GetEnumerator() | ForEach-Object {
  Render-Icon -Size $_.Value -Path "$android\$($_.Key)\ic_launcher.png" -Mode Rounded
}

Write-Output '=== android adaptive (foreground inset to the safe zone) ==='
# 432px canvas is the adaptive-icon standard; the launcher may crop to a circle,
# so the mark occupies ~58% of the canvas.
Render-Icon -Size 432 -Path "$android\mipmap-xxxhdpi\ic_launcher_foreground.png" -Mode GlyphOnly -MarkScale 0.58
Render-Icon -Size 432 -Path "$android\mipmap-xxxhdpi\ic_launcher_background.png" -Mode GroundOnly

Write-Output '=== ios (square, opaque — iOS masks its own corners) ==='
$ios = "$root\ios\Runner\Assets.xcassets\AppIcon.appiconset"
@{
  'Icon-App-20x20@1x' = 20; 'Icon-App-20x20@2x' = 40; 'Icon-App-20x20@3x' = 60
  'Icon-App-29x29@1x' = 29; 'Icon-App-29x29@2x' = 58; 'Icon-App-29x29@3x' = 87
  'Icon-App-40x40@1x' = 40; 'Icon-App-40x40@2x' = 80; 'Icon-App-40x40@3x' = 120
  'Icon-App-60x60@2x' = 120; 'Icon-App-60x60@3x' = 180
  'Icon-App-76x76@1x' = 76; 'Icon-App-76x76@2x' = 152
  'Icon-App-83.5x83.5@2x' = 167
  'Icon-App-1024x1024@1x' = 1024
}.GetEnumerator() | ForEach-Object {
  Render-Icon -Size $_.Value -Path "$ios\$($_.Key).png" -Mode FullBleed
}

Write-Output '=== web ==='
Render-Icon -Size 192 -Path "$root\web\icons\Icon-192.png" -Mode Rounded
Render-Icon -Size 512 -Path "$root\web\icons\Icon-512.png" -Mode Rounded
# Maskable: full bleed with the mark inside the safe zone.
Render-Icon -Size 192 -Path "$root\web\icons\Icon-maskable-192.png" -Mode FullBleed -MarkScale 0.62
Render-Icon -Size 512 -Path "$root\web\icons\Icon-maskable-512.png" -Mode FullBleed -MarkScale 0.62
Render-Icon -Size 32 -Path "$root\web\favicon.png" -Mode Rounded

Write-Output '=== windows .ico (multi-size, PNG-encoded frames) ==='
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$tmp = Join-Path $env:TEMP 'mytrain_ico'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
$frames = @()
foreach ($s in $icoSizes) {
  $p = Join-Path $tmp "$s.png"
  Render-Icon -Size $s -Path $p -Mode Rounded
  $frames += , @{ size = $s; bytes = [System.IO.File]::ReadAllBytes($p) }
}
$icoPath = "$root\windows\runner\resources\app_icon.ico"
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)                    # reserved
$bw.Write([UInt16]1)                    # type: icon
$bw.Write([UInt16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
  $dim = if ($f.size -ge 256) { 0 } else { $f.size }
  $bw.Write([Byte]$dim); $bw.Write([Byte]$dim)
  $bw.Write([Byte]0); $bw.Write([Byte]0)      # palette, reserved
  $bw.Write([UInt16]1); $bw.Write([UInt16]32) # planes, bpp
  $bw.Write([UInt32]$f.bytes.Length)
  $bw.Write([UInt32]$offset)
  $offset += $f.bytes.Length
}
foreach ($f in $frames) { $bw.Write($f.bytes) }
$bw.Flush(); $bw.Close(); $fs.Close()
Remove-Item $tmp -Recurse -Force
Write-Output ("  windows\runner\resources\app_icon.ico  ({0} frames)" -f $frames.Count)

Write-Output ''
Write-Output 'Done.'
