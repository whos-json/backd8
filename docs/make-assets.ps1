# Regenerates docs\images\logo.png and docs\images\banner.png in a Windows 98 Setup-wizard style
# (pure System.Drawing, no external files, no network).  Run: powershell -ExecutionPolicy Bypass -File docs\make-assets.ps1
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'images'; New-Item -ItemType Directory -Force $out | Out-Null
function C([string]$hex) { $h = $hex.TrimStart('#'); [Drawing.Color]::FromArgb(255, [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)) }
function Fill($g, [string]$hex, $x, $y, $w, $h) { $b = New-Object Drawing.SolidBrush (C $hex); $g.FillRectangle($b, [int]$x, [int]$y, [int]$w, [int]$h); $b.Dispose() }
function Line($g, [string]$hex, $x1, $y1, $x2, $y2) { $p = New-Object Drawing.Pen (C $hex), 1; $g.DrawLine($p, [int]$x1, [int]$y1, [int]$x2, [int]$y2); $p.Dispose() }
function Raised($g, $x, $y, $w, $h) {   # classic 3D raised edge: white/light top-left, gray/black bottom-right
  Fill $g '#C0C0C0' $x $y $w $h
  Line $g '#FFFFFF' $x $y ($x + $w - 2) $y; Line $g '#FFFFFF' $x $y $x ($y + $h - 2)
  Line $g '#DFDFDF' ($x + 1) ($y + 1) ($x + $w - 3) ($y + 1); Line $g '#DFDFDF' ($x + 1) ($y + 1) ($x + 1) ($y + $h - 3)
  Line $g '#808080' ($x + 1) ($y + $h - 2) ($x + $w - 2) ($y + $h - 2); Line $g '#808080' ($x + $w - 2) ($y + 1) ($x + $w - 2) ($y + $h - 2)
  Line $g '#000000' $x ($y + $h - 1) ($x + $w - 1) ($y + $h - 1); Line $g '#000000' ($x + $w - 1) $y ($x + $w - 1) ($y + $h - 1)
}
function Sunken($g, $x, $y, $w, $h, [string]$face = '#FFFFFF') {
  Fill $g $face $x $y $w $h
  Line $g '#808080' $x $y ($x + $w - 2) $y; Line $g '#808080' $x $y $x ($y + $h - 2)
  Line $g '#000000' ($x + 1) ($y + 1) ($x + $w - 3) ($y + 1); Line $g '#000000' ($x + 1) ($y + 1) ($x + 1) ($y + $h - 3)
  Line $g '#FFFFFF' ($x + 1) ($y + $h - 1) ($x + $w - 1) ($y + $h - 1); Line $g '#FFFFFF' ($x + $w - 1) ($y + 1) ($x + $w - 1) ($y + $h - 1)
  Line $g '#DFDFDF' ($x + 2) ($y + $h - 2) ($x + $w - 2) ($y + $h - 2); Line $g '#DFDFDF' ($x + $w - 2) ($y + 2) ($x + $w - 2) ($y + $h - 2)
}
# 32x32 pixel-art PC (monitor showing a commit graph + a floppy), drawn at 1px per cell then scaled
function Draw-PC($g, [int]$ox, [int]$oy, [int]$s) {
  function P($x, $y, $w, $h, $hex) { Fill $g $hex ($ox + $x * $s) ($oy + $y * $s) ($w * $s) ($h * $s) }
  P 3 2 22 18 '#000000'; P 4 3 20 16 '#DCD8C8'; P 4 3 20 1 '#FFFFFF'; P 4 3 1 16 '#FFFFFF'; P 23 3 1 16 '#808080'; P 4 18 20 1 '#808080'
  P 6 5 16 11 '#000000'; P 7 6 14 9 '#000080'
  P 8 11 12 1 '#00FFFF'; P 8 9 2 2 '#FFFF00'; P 12 9 2 2 '#FFFF00'; P 16 9 2 2 '#FFFF00'; P 10 10 2 1 '#FFFFFF'; P 14 10 2 1 '#FFFFFF'
  P 10 20 8 2 '#B8B4A4'; P 7 22 14 3 '#DCD8C8'; P 7 22 14 1 '#FFFFFF'; P 7 24 14 1 '#808080'; P 7 22 14 3 '#DCD8C8'
  P 8 23 6 1 '#000000'
  P 22 21 8 8 '#000040'; P 23 22 6 3 '#C0C0C0'; P 25 22 2 3 '#000040'; P 23 26 6 3 '#FFFFFF'; P 24 27 3 1 '#808080'
}

# ---------------- logo 512 (pixel-art PC on the Setup teal) ----------------
$bmp = New-Object Drawing.Bitmap 512, 512; $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'None'; $g.PixelOffsetMode = 'Half'
Fill $g '#3A3A9C' 0 0 512 512
Raised $g 24 24 464 464
Fill $g '#000080' 28 28 456 36
Sunken $g 40 80 432 392 '#40A0A0'
Draw-PC $g 80 100 11
$f = New-Object Drawing.Font 'Arial', 22, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$g.TextRenderingHint = 'AntiAlias'; $g.DrawString('backd8 Setup', $f, [Drawing.Brushes]::White, 40, 33)
$bmp.Save("$out\logo.png", [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

# ---------------- banner 1280x400: the wizard ----------------
$bmp = New-Object Drawing.Bitmap 1280, 400; $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'None'; $g.PixelOffsetMode = 'Half'; $g.TextRenderingHint = 'AntiAliasGridFit'
Fill $g '#3A3A9C' 0 0 1280 400
Fill $g '#000000' 0 0 1280 56
Fill $g '#000000' 0 0 250 400
$fT = New-Object Drawing.Font 'Arial', 34, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$fT2 = New-Object Drawing.Font 'Arial', 34, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
$g.DrawString('backd8', $fT, [Drawing.Brushes]::White, 270, 7); $g.DrawString('Setup', $fT2, [Drawing.Brushes]::White, 412, 7)
$fs = New-Object Drawing.Font 'Tahoma', 13, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
$fsb = New-Object Drawing.Font 'Tahoma', 13, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$yellow = New-Object Drawing.SolidBrush (C '#FFFF00')
$steps = @('Choose your project', 'Change dates and messages', 'Sign in to GitHub', 'Publish to GitHub')
$y = 76
for ($i = 0; $i -lt 4; $i++) {
  Fill $g $(if ($i -eq 3) { '#FFFF00' } else { '#FFFFFF' }) 14 ($y + 2) 14 14
  if ($i -eq 3) { $g.DrawString($steps[$i], $fsb, $yellow, 36, $y) } else { $g.DrawString($steps[$i], $fs, [Drawing.Brushes]::White, 36, $y) }
  $y += 36
}
Line $g '#FFFFFF' 12 232 238 232
$g.DrawString("Select Publish to send your`nproject to GitHub. Pick`nwhether to keep or replace`nGitHub's version.", $fs, [Drawing.Brushes]::White, 12, 244)
$fl = New-Object Drawing.Font 'Arial', 40, ([Drawing.FontStyle]::Bold -bor [Drawing.FontStyle]::Italic), ([Drawing.GraphicsUnit]::Pixel)
$g.DrawString('backd8', $fl, [Drawing.Brushes]::White, 12, 340)
# dialog
Raised $g 300 76 940 300
Fill $g '#000080' 304 80 932 20
$fd = New-Object Drawing.Font 'Arial', 15, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$sz = $g.MeasureString('backd8 Setup Wizard', $fd); $g.DrawString('backd8 Setup Wizard', $fd, [Drawing.Brushes]::White, 770 - $sz.Width / 2, 81)
Sunken $g 316 116 230 244 '#40A0A0'
Draw-PC $g 334 150 6
$fh = New-Object Drawing.Font 'Arial', 24, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Publish to GitHub', $fh, [Drawing.Brushes]::Black, 572, 116)
$g.DrawString("Choose what GitHub should do with the old copy of your changed commits, then click Next.", $fs, [Drawing.Brushes]::Black, 572, 156)
# radios
function Radio($x, $y, $on, $title, $desc) {
  $g.FillEllipse([Drawing.Brushes]::White, $x, $y, 13, 13); $p = New-Object Drawing.Pen (C '#808080'), 1; $g.DrawArc($p, $x, $y, 12, 12, 135, 180); $p2 = New-Object Drawing.Pen (C '#000000'), 1; $g.DrawArc($p2, $x + 1, $y + 1, 10, 10, 135, 180)
  $p3 = New-Object Drawing.Pen (C '#FFFFFF'), 1; $g.DrawArc($p3, $x, $y, 12, 12, 315, 180)
  if ($on) { $g.FillEllipse([Drawing.Brushes]::Black, $x + 4, $y + 4, 5, 5) }
  Fill $g '#000000' ($x + 28) ($y - 4) 30 28; Fill $g '#C0C0C0' ($x + 32) ($y) 22 6; Fill $g '#808080' ($x + 32) ($y + 10) 22 6
  $g.DrawString($title, $fs, [Drawing.Brushes]::Black, $x + 70, $y - 1); $g.DrawString($desc, $fs, [Drawing.Brushes]::Black, $x + 210, $y - 1)
}
Radio 580 200 $true 'Keep it' "GitHub keeps its current copy.`nYour edits stay on this computer."
Radio 580 248 $false 'Replace it' "GitHub gets your edited commits.`nThe old ones disappear there."
Line $g '#808080' 566 322 1224 322; Line $g '#FFFFFF' 566 323 1224 323
function Btn($x, $label, $def) { Raised $g $x 334 80 28; if ($def) { $pp = New-Object Drawing.Pen (C '#000000'), 1; $g.DrawRectangle($pp, $x - 1, 333, 81, 29) }; $s = $g.MeasureString($label, $fs); $g.DrawString($label, $fs, [Drawing.Brushes]::Black, $x + 40 - $s.Width / 2, 342) }
Btn 960 '< Back' $false; Btn 1050 'Next >' $true; Btn 1140 'Cancel' $false
$bmp.Save("$out\banner.png", [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
"wrote $out\logo.png and $out\banner.png"
