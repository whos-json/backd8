# make-art.ps1 - regenerates every pixel-art asset in assets\art\ (and docs\art-sheet.png)
# Windows PowerShell 5.1, System.Drawing only, no network. All art is original.
# Every sprite is drawn on a tiny grid (one char per pixel), then saved with per-cell
# rectangles at an integer scale (nearest neighbour, no anti-aliasing).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ArtDir  = Join-Path $PSScriptRoot 'art'
$DocsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs'
New-Item -ItemType Directory -Force -Path $ArtDir  | Out-Null
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null
$script:Errs = @()

# ---------------------------------------------------------------- palette (one letter per colour; '.' = transparent)
$Pal = @{
    'K' = 0x000000; 'W' = 0xFFFFFF; 'L' = 0xDFDFDF; 'G' = 0xC0C0C0; 'D' = 0x808080; 'N' = 0x000080
    'Y' = 0xFFFF00; 'O' = 0x808000; 'R' = 0xFF0000; 'Q' = 0x800000; 'E' = 0x008000; 'U' = 0x00FF00
    'B' = 0x0000FF; 'C' = 0x00FFFF; 'Z' = 0x008080; 'M' = 0xFF00FF; 'P' = 0x800080; 'T' = 0x40A0A0
}

# ---------------------------------------------------------------- grid primitives
function New-Grid($w, $h) {
    $p = New-Object 'char[]' ($w * $h)
    for ($i = 0; $i -lt $p.Length; $i++) { $p[$i] = '.' }
    return @{ W = $w; H = $h; P = $p }
}
function Cell($g, $x, $y) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $g.W -or $y -ge $g.H) { return [char]'.' }
    return $g.P[$y * $g.W + $x]
}
function Put($g, $x, $y, $c) {
    $x = [int]$x; $y = [int]$y
    if ($x -ge 0 -and $y -ge 0 -and $x -lt $g.W -and $y -lt $g.H) { $g.P[$y * $g.W + $x] = [char]$c }
}
function Rect($g, $x, $y, $w, $h, $c) {
    for ($j = 0; $j -lt $h; $j++) { for ($i = 0; $i -lt $w; $i++) { Put $g ($x + $i) ($y + $j) $c } }
}
function Disc($g, $cx, $cy, $r, $c) {
    for ($y = [int][math]::Floor($cy - $r); $y -le [int][math]::Ceiling($cy + $r); $y++) {
        for ($x = [int][math]::Floor($cx - $r); $x -le [int][math]::Ceiling($cx + $r); $x++) {
            if ((($x - $cx) * ($x - $cx) + ($y - $cy) * ($y - $cy)) -le ($r * $r)) { Put $g $x $y $c }
        }
    }
}
function Ellipse($g, $cx, $cy, $rx, $ry, $c) {
    for ($y = [int][math]::Floor($cy - $ry); $y -le [int][math]::Ceiling($cy + $ry); $y++) {
        for ($x = [int][math]::Floor($cx - $rx); $x -le [int][math]::Ceiling($cx + $rx); $x++) {
            if (((($x - $cx) / $rx) * (($x - $cx) / $rx) + (($y - $cy) / $ry) * (($y - $cy) / $ry)) -le 1) { Put $g $x $y $c }
        }
    }
}
# thick segment (odd t on integer coords, even t on .5 coords)
function Seg($g, $x0, $y0, $x1, $y1, $t, $c) {
    $half = $t / 2.0 - 0.001
    $dx = $x1 - $x0; $dy = $y1 - $y0; $len2 = $dx * $dx + $dy * $dy
    for ($y = [int][math]::Floor([math]::Min($y0, $y1) - $half - 1); $y -le [int][math]::Ceiling([math]::Max($y0, $y1) + $half + 1); $y++) {
        for ($x = [int][math]::Floor([math]::Min($x0, $x1) - $half - 1); $x -le [int][math]::Ceiling([math]::Max($x0, $x1) + $half + 1); $x++) {
            if ($len2 -eq 0) { $u = 0 } else { $u = (($x - $x0) * $dx + ($y - $y0) * $dy) / $len2; if ($u -lt 0) { $u = 0 }; if ($u -gt 1) { $u = 1 } }
            $px = $x0 + $u * $dx; $py = $y0 + $u * $dy
            if ([math]::Sqrt(($x - $px) * ($x - $px) + ($y - $py) * ($y - $py)) -le $half) { Put $g $x $y $c }
        }
    }
}
function Poly($g, $pts, $c) {
    $n = $pts.Count
    for ($y = 0; $y -lt $g.H; $y++) {
        for ($x = 0; $x -lt $g.W; $x++) {
            $in = $false; $j = $n - 1
            for ($i = 0; $i -lt $n; $i++) {
                $xi = $pts[$i][0]; $yi = $pts[$i][1]; $xj = $pts[$j][0]; $yj = $pts[$j][1]
                if (($yi -gt $y) -ne ($yj -gt $y)) {
                    if ($x -lt (($xj - $xi) * ($y - $yi) / ($yj - $yi) + $xi)) { $in = -not $in }
                }
                $j = $i
            }
            if ($in) { Put $g $x $y $c }
        }
    }
}
function Blit($dst, $src, $x, $y) {
    for ($j = 0; $j -lt $src.H; $j++) { for ($i = 0; $i -lt $src.W; $i++) {
        $c = $src.P[$j * $src.W + $i]
        if ($c -ne '.') { Put $dst ($x + $i) ($y + $j) $c }
    } }
}
# 1px black outline around every opaque pixel (4-neighbourhood)
function Outline($g, $c = 'K') {
    $src = $g.P.Clone()
    for ($y = 0; $y -lt $g.H; $y++) { for ($x = 0; $x -lt $g.W; $x++) {
        if ($src[$y * $g.W + $x] -eq '.') {
            $hit = $false
            if ($x -gt 0 -and $src[$y * $g.W + $x - 1] -ne '.') { $hit = $true }
            if ($x -lt $g.W - 1 -and $src[$y * $g.W + $x + 1] -ne '.') { $hit = $true }
            if ($y -gt 0 -and $src[($y - 1) * $g.W + $x] -ne '.') { $hit = $true }
            if ($y -lt $g.H - 1 -and $src[($y + 1) * $g.W + $x] -ne '.') { $hit = $true }
            if ($hit) { $g.P[$y * $g.W + $x] = [char]$c }
        }
    } }
}
# light from top-left: edge pixels facing up/left get hi, facing down/right get lo. map: colour -> @(hi, lo)
function Shade($g, $map) {
    $src = $g.P.Clone()
    for ($y = 0; $y -lt $g.H; $y++) { for ($x = 0; $x -lt $g.W; $x++) {
        $c = [string]$src[$y * $g.W + $x]
        if ($c -ne '.' -and $map.Contains($c)) {
            $up = ($y -eq 0) -or ($src[($y - 1) * $g.W + $x] -eq '.')
            $lf = ($x -eq 0) -or ($src[$y * $g.W + $x - 1] -eq '.')
            $dn = ($y -eq $g.H - 1) -or ($src[($y + 1) * $g.W + $x] -eq '.')
            $rt = ($x -eq $g.W - 1) -or ($src[$y * $g.W + $x + 1] -eq '.')
            $hi = $map[$c][0]; $lo = $map[$c][1]
            if (($up -or $lf) -and $hi) { $g.P[$y * $g.W + $x] = [char]$hi }
            elseif (($dn -or $rt) -and $lo) { $g.P[$y * $g.W + $x] = [char]$lo }
        }
    } }
}
$ShadeAll = @{ 'Y' = @('W', 'O'); 'G' = @('W', 'D'); 'E' = @('U', $null); 'R' = @($null, 'Q'); 'B' = @('C', 'N'); 'W' = @($null, 'G'); 'L' = @('W', 'D') }

function Rows($name, $rows, $w, $h) {
    $g = New-Grid $w $h
    if ($rows.Count -ne $h) { $script:Errs += "$name has $($rows.Count) rows, expected $h" }
    for ($y = 0; $y -lt [math]::Min($h, $rows.Count); $y++) {
        $r = $rows[$y]
        if ($r.Length -ne $w) { $script:Errs += "$name row $y has length $($r.Length), expected $w"; $r = $r.PadRight($w, '.').Substring(0, $w) }
        for ($x = 0; $x -lt $w; $x++) {
            $ch = [string]$r[$x]
            if ($ch -ne '.' -and -not $Pal.ContainsKey($ch)) { $script:Errs += "$name unknown char '$ch'"; $ch = '.' }
            $g.P[$y * $w + $x] = [char]$ch
        }
    }
    return $g
}

# ---------------------------------------------------------------- saving (per-cell rectangles, integer scale)
$script:Brushes = @{}
function Get-Brush($c) {
    $k = [string]$c
    if (-not $script:Brushes.ContainsKey($k)) {
        $v = $Pal[$k]
        $script:Brushes[$k] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255)))
    }
    return $script:Brushes[$k]
}
function Paint-Grid($gr, $g, $scale, $ox, $oy) {
    for ($y = 0; $y -lt $g.H; $y++) { for ($x = 0; $x -lt $g.W; $x++) {
        $c = $g.P[$y * $g.W + $x]
        if ($c -ne '.') { $gr.FillRectangle((Get-Brush $c), ($ox + $x) * $scale, ($oy + $y) * $scale, $scale, $scale) }
    } }
}
function Save-Grid($g, $path, $scale, $canvasW = 0, $canvasH = 0, $ox = 0, $oy = 0, $bg = $null) {
    if (-not $canvasW) { $canvasW = $g.W * $scale }
    if (-not $canvasH) { $canvasH = $g.H * $scale }
    $bmp = New-Object System.Drawing.Bitmap $canvasW, $canvasH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.SmoothingMode = 'None'; $gr.InterpolationMode = 'NearestNeighbor'; $gr.PixelOffsetMode = 'None'; $gr.CompositingQuality = 'AssumeLinear'
    if ($bg) { $gr.Clear([System.Drawing.ColorTranslator]::FromHtml($bg)) } else { $gr.Clear([System.Drawing.Color]::Transparent) }
    Paint-Grid $gr $g $scale $ox $oy
    $gr.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# ================================================================ SPRITE LIBRARY
# ---- ASCII icons, 16x16
$IconRows = [ordered]@{}
$IconRows['folder'] = @(
'................',
'..KKKKK.........',
'.KWWWWWK........',
'.KWYYYYYKKKKKKK.',
'.KWYYYYYYYYYYYK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KYOOOOOOOOOOOK.',
'..KKKKKKKKKKKKK.',
'................',
'................')
$IconRows['folder-open'] = @(
'................',
'..KKKKK.........',
'.KOOOOOK........',
'.KOOOOOKKKKKKKK.',
'.KOOOOOOOOOOOOK.',
'.KOOOOOOOOOOOOK.',
'.KOKKKKKKKKKKKKK',
'.KOKWWWWWWWWWWYK',
'.KOKYYYYYYYYYYYK',
'KOKYYYYYYYYYYYOK',
'KOKYYYYYYYYYYYOK',
'KKYYYYYYYYYYYYOK',
'KYYYYYYYYYYYYYOK',
'KKKKKKKKKKKKKKKK',
'................',
'................')
$IconRows['document'] = @(
'................',
'...KKKKKKK......',
'...KWWWWWKK.....',
'...KWWWWWKLK....',
'...KWWWWWKKKK...',
'...KWWWWWWWWK...',
'...KWDDDDDDWK...',
'...KWWWWWWWWK...',
'...KWDDDDDDWK...',
'...KWWWWWWWWK...',
'...KWDDDDDDWK...',
'...KWWWWWWWWK...',
'...KWDDDDWWWK...',
'...KKKKKKKKKK...',
'................',
'................')
$IconRows['clock'] = @(
'.....KKKKKK.....',
'...KKWWWWWWKK...',
'..KWWWWWWWWWWK..',
'.KWWWWWKWWWWWDK.',
'.KWWWWWKWWWWWDK.',
'KWWWWWWKWWWWWWDK',
'KWWWWWWKWWWWWWDK',
'KWWWWWWKKKKWWWDK',
'KWWWWWWWWWWWWWDK',
'KWWWWWWWWWWWWWDK',
'.KWWWWWWWWWWWDK.',
'.KWWWWWWWWWWDDK.',
'..KWWWWWWWDDDK..',
'...KKDDDDDDKK...',
'.....KKKKKK.....',
'................')
$IconRows['key'] = @(
'................',
'................',
'................',
'..KKKK..........',
'.KWYYYK.........',
'KYYYYYYKKKKKKKK.',
'KYYKKYYYYYYYYYYK',
'KYYKKYYYYYYYYYYK',
'KYYYYYYKKKKYYKKK',
'.KYYYYK..KYYK...',
'..KKKK...KKKK...',
'................',
'................',
'................',
'................',
'................')
$IconRows['lock'] = @(
'.....KKKKKK.....',
'....KWGGGGDK....',
'...KWGKKKKGDK...',
'...KGK....KDK...',
'...KGK....KDK...',
'...KGK....KDK...',
'.KKKKKKKKKKKKKK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYKKYYYYOK.',
'.KWYYYYKKYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KWYYYYYYYYYYOK.',
'.KYOOOOOOOOOOOK.',
'.KKKKKKKKKKKKKK.',
'................')
$IconRows['floppy'] = @(
'KKKKKKKKKKKKK...',
'KNNNNNNNNNNNNK..',
'KNNGGGGGGGGNNNK.',
'KNNGGGGDDGGNNNNK',
'KNNGGGGDDGGNNNNK',
'KNNGGGGGGGGNNNNK',
'KNNNNNNNNNNNNNNK',
'KNWWWWWWWWWWWWNK',
'KNWWWWWWWWWWWWNK',
'KNWDDDDDDDDDWWNK',
'KNWWWWWWWWWWWWNK',
'KNWDDDDDDWWWWWNK',
'KNWWWWWWWWWWWWNK',
'KNWWWWWWWWWWWWNK',
'KNNNNNNNNNNNNNNK',
'KKKKKKKKKKKKKKKK')
$IconRows['cloud'] = @(
'................',
'................',
'................',
'......KKKK......',
'.....KWWWWK.KK..',
'....KWWWWWWKWWK.',
'...KWWWWWWWWWWWK',
'.KKWWWWWWWWWWWWK',
'KWWWWWWWWWWWWWWK',
'KWWWWWWWWWWWWWGK',
'KWWWWWWWWWWWWGGK',
'.KGGGGGGGGGGGGK.',
'..KKKKKKKKKKKK..',
'................',
'................',
'................')
$IconRows['trash'] = @(
'................',
'......KKKK......',
'.....KGGGGK.....',
'..KKKKKKKKKKKK..',
'..KWWGGGGGGGDK..',
'..KKKKKKKKKKKK..',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KWGDGGDGDK...',
'...KKKKKKKKKK...',
'................',
'................')
$IconRows['calendar'] = @(
'....KK....KK....',
'.KKKKKKKKKKKKKK.',
'.KRRRRRRRRRRRRK.',
'.KRRRRRRRRRRRRK.',
'.KKKKKKKKKKKKKK.',
'.KWWWWWWWWWWWDK.',
'.KWBBWBBWBBWWDK.',
'.KWBBWBBWBBWWDK.',
'.KWWWWWWWWWWWDK.',
'.KWBBWBBWBBWWDK.',
'.KWBBWBBWBBWWDK.',
'.KWWWWWWWWWWWDK.',
'.KWBBWBBWRRWWDK.',
'.KWBBWBBWRRWWDK.',
'.KKKKKKKKKKKKKK.',
'................')
$IconRows['github-cat'] = @(
'..K..........K..',
'..KK........KK..',
'..KKK......KKK..',
'..KKKKKKKKKKKK..',
'..KKKKKKKKKKKK..',
'..KKGGKKKKGGKK..',
'..KKKKKKKKKKKK..',
'..KKKKKDDKKKKK..',
'...KKKKKKKKKK...',
'...KKKKKKKKKKKK.',
'...KKKKKKKKKKKKK',
'...KKKKKKKKKKKKK',
'...KKKKKKKKKKKK.',
'...KKK.KKK.KKK..',
'...KK..KK..KK...',
'................')
$UndoRows = @(
'................',
'....K...........',
'...KBK..........',
'..KBBBKKKKKKK...',
'.KBBBBBBBBBBBK..',
'KBBBBBBBBBBBBBK.',
'.KBBBBKKKKKBBBK.',
'..KBBK.....KBBK.',
'...KK......KBBK.',
'...........KBBK.',
'..........KBBBK.',
'....KKKKKKBBBK..',
'...KBBBBBBBBK...',
'....KKKKKKKK....',
'................',
'................')
$GlyphRows = [ordered]@{}
$GlyphRows['dot-green'] = @('..KKKK..', '.KUUEEK.', 'KUUEEEEK', 'KUEEEEEK', 'KEEEEEEK', 'KEEEEEEK', '.KEEEEK.', '..KKKK..')
$GlyphRows['dot-gray']  = @('..KKKK..', '.KWWGGK.', 'KWWGGGGK', 'KWGGGGGK', 'KGGGGGGK', 'KGGGGGDK', '.KGGDDK.', '..KKKK..')
$GlyphRows['merge']     = @('.BB..BB.', '.BB..BB.', '.K....K.', '..K..K..', '...KK...', '...KK...', '...BB...', '...BB...')
$GlyphRows['warning']   = @('....K...', '...KYK..', '..KYKYK.', '..KYKYK.', '.KYYKYYK', '.KYYYYYK', '.KYYKYYK', '.KKKKKKK')
$GlyphRows['lock']      = @('..KKKK..', '.K....K.', '.K....K.', 'KKKKKKKK', 'KWYYYYYK', 'KYYKKYYK', 'KYYYKYYK', 'KKKKKKKK')

# ---- procedural 16x16 icons
$LandUnits = @( @(0.08,0.20,0.32,0.24), @(0.20,0.42,0.16,0.12), @(0.30,0.56,0.16,0.30), @(0.54,0.16,0.22,0.16), @(0.50,0.36,0.22,0.30), @(0.74,0.22,0.22,0.24) )
function G-Globe($d) {
    $g = New-Grid $d $d; $c = ($d - 1) / 2.0; $r = ($d - 2) / 2.0 - 0.1; $s = $d - 2
    Disc $g $c $c $r 'B'
    foreach ($l in $LandUnits) {
        $x0 = [int][math]::Round(1 + $l[0] * $s); $y0 = [int][math]::Round(1 + $l[1] * $s)
        $w = [math]::Max(1, [int][math]::Round($l[2] * $s)); $h = [math]::Max(1, [int][math]::Round($l[3] * $s))
        for ($j = $y0; $j -lt $y0 + $h; $j++) { for ($i = $x0; $i -lt $x0 + $w; $i++) { if ((Cell $g $i $j) -eq 'B') { Put $g $i $j 'E' } } }
    }
    for ($y = 0; $y -lt $d; $y++) { for ($x = 0; $x -lt $d; $x++) {
        if ((Cell $g $x $y) -eq 'B') {
            $hx = $x - ($c - 0.45 * $r); $hy = $y - ($c - 0.45 * $r)
            if ([math]::Sqrt($hx * $hx + $hy * $hy) -lt (0.2 * $r + 0.3)) { Put $g $x $y 'C' }
            elseif ([math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c)) -gt ($r - 0.9) -and (($x - $c) + ($y - $c)) -gt 0.3 * $r) { Put $g $x $y 'N' }
        }
    } }
    Outline $g
    return $g
}
function G-Check() {
    $g = New-Grid 16 16; Disc $g 7.5 7.5 6.9 'E'; Shade $g @{ 'E' = @('U', $null) }
    Seg $g 4.5 7.5 6.5 9.5 2.2 'W'; Seg $g 6.5 9.5 11.5 4.5 2.2 'W'
    Outline $g; return $g
}
function G-Error() {
    $g = New-Grid 16 16; Disc $g 7.5 7.5 6.9 'R'; Shade $g @{ 'R' = @($null, 'Q') }
    Seg $g 5 5 10 10 2.3 'W'; Seg $g 10 5 5 10 2.3 'W'
    Outline $g; return $g
}
function G-Info() {
    $g = New-Grid 16 16; Disc $g 7.5 7.5 6.9 'B'; Shade $g @{ 'B' = @('C', 'N') }
    Rect $g 7 3 2 2 'W'; Rect $g 6 6 3 1 'W'; Rect $g 7 7 2 4 'W'; Rect $g 6 11 4 1 'W'
    Outline $g; return $g
}
function G-Warning() {
    $g = New-Grid 16 16
    Poly $g @(@(7.5, 1.2), @(14.6, 13.6), @(0.4, 13.6)) 'Y'
    Shade $g @{ 'Y' = @('W', 'O') }
    Rect $g 7 5 2 5 'K'; Rect $g 7 11 2 2 'K'
    Outline $g; return $g
}
function G-Question() {
    $g = New-Grid 16 16
    Rect $g 1 1 14 11 'W'; Put $g 1 1 '.'; Put $g 14 1 '.'; Put $g 1 11 '.'; Put $g 14 11 '.'
    Poly $g @(@(3, 11), @(3, 14.4), @(8, 11)) 'W'
    Shade $g @{ 'W' = @($null, 'G') }
    $q = @('.BBB.', 'B...B', '....B', '..BB.', '..B..', '.....', '..B..')
    for ($j = 0; $j -lt 7; $j++) { for ($i = 0; $i -lt 5; $i++) { if ($q[$j][$i] -ne '.') { Put $g (5 + $i) (2 + $j) 'B' } } }
    Outline $g; return $g
}
function ArcArrow($g, $cx, $cy, $r, $th, $aH, $sweep, $hl, $hw, $c) {
    $sign = 1; if ($sweep -lt 0) { $sign = -1 }; $abs = [math]::Abs($sweep)
    for ($y = 0; $y -lt $g.H; $y++) { for ($x = 0; $x -lt $g.W; $x++) {
        $dx = $x - $cx; $dy = $y - $cy; $d = [math]::Sqrt($dx * $dx + $dy * $dy)
        if ([math]::Abs($d - $r) -le $th / 2.0) {
            $ang = [math]::Atan2(-$dy, $dx) * 180 / [math]::PI
            $t = (($ang - $aH) * $sign) % 360; if ($t -lt 0) { $t += 360 }
            if ($t -le $abs) { Put $g $x $y $c }
        }
    } }
    $a = $aH * [math]::PI / 180; $ca = [math]::Cos($a); $sa = [math]::Sin($a)
    $bx = $cx + $r * $ca; $by = $cy - $r * $sa
    if ($sign -gt 0) { $dx = $sa; $dy = $ca } else { $dx = -$sa; $dy = -$ca }
    $bx -= $dx * 0.8; $by -= $dy * 0.8
    Poly $g @(@(($bx + $ca * $hw), ($by - $sa * $hw)), @(($bx - $ca * $hw), ($by + $sa * $hw)), @(($bx + $dx * $hl), ($by + $dy * $hl))) $c
}
function G-Undo() {
    $g = New-Grid 16 16
    ArcArrow $g 8.2 8.6 4.4 2.6 170 (-250) 4.2 3.0 'B'
    Shade $g @{ 'B' = @('C', 'N') }; Outline $g; return $g
}
function G-Refresh() {
    $g = New-Grid 16 16
    ArcArrow $g 7.5 7.5 4.6 2.4 25 125 3.6 2.7 'E'
    ArcArrow $g 7.5 7.5 4.6 2.4 205 125 3.6 2.7 'E'
    Shade $g @{ 'E' = @('U', $null) }; Outline $g; return $g
}
function G-Branch() {
    $g = New-Grid 16 16
    Seg $g 3.5 3.5 3.5 12.5 2 'B'; Seg $g 12.5 3.5 12.5 6 2 'B'; Seg $g 12.5 6.5 4 10.5 2 'B'
    Disc $g 3.5 3.5 2.7 'Y'; Disc $g 3.5 12.5 2.7 'Y'; Disc $g 12.5 3.5 2.7 'Y'
    Outline $g; return $g
}
function G-User() {
    $g = New-Grid 16 16
    Disc $g 7.5 4.3 3.3 'Y'
    $b = New-Grid 16 16; Ellipse $b 7.5 14.6 6.4 5.6 'B'
    for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 16; $x++) { if ($y -lt 9 -or $y -gt 14) { Put $b $x $y '.' } } }
    Blit $g $b 0 0
    Shade $g @{ 'Y' = @('W', 'O'); 'B' = @('C', 'N') }; Outline $g; return $g
}
function G-Gear() {
    $g = New-Grid 16 16
    for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 16; $x++) {
        $dx = $x - 7.5; $dy = $y - 7.5; $r = [math]::Sqrt($dx * $dx + $dy * $dy); $th = [math]::Atan2($dy, $dx)
        $tooth = ([math]::Abs([math]::Cos(4 * $th)) -gt 0.55 -and $r -le 6.7)
        if (($r -le 4.9 -or $tooth) -and $r -gt 2.0) { Put $g $x $y 'G' }
    } }
    Shade $g @{ 'G' = @('L', 'D') }; Outline $g; return $g
}
function G-Help() {
    $g = New-Grid 16 16
    for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 16; $x++) {
        $dx = $x - 7.5; $dy = $y - 7.5; $r = [math]::Sqrt($dx * $dx + $dy * $dy)
        if ($r -le 6.9 -and $r -gt 3.0) {
            $a = [math]::Atan2($dy, $dx) * 180 / [math]::PI + 45 + 360
            if (([int][math]::Floor($a / 90)) % 2 -eq 0) { Put $g $x $y 'R' } else { Put $g $x $y 'W' }
        }
    } }
    Shade $g @{ 'R' = @($null, 'Q'); 'W' = @($null, 'G') }; Outline $g; return $g
}
function G-DocNew($doc) {
    $g = New-Grid 16 16; Blit $g $doc (-2) 0
    $s = New-Grid 7 7
    $sp = @('..Y..', '.YWY.', 'YWWWY', '.YWY.', '..Y..')
    for ($j = 0; $j -lt 5; $j++) { for ($i = 0; $i -lt 5; $i++) { if ($sp[$j][$i] -ne '.') { Put $s (1 + $i) (1 + $j) $sp[$j][$i] } } }
    Outline $s; Blit $g $s 9 0
    return $g
}
function G-Pencil($cells, $hw) {
    $n = $cells + 3; $g = New-Grid $n $n
    $x0 = 1; $y0 = $cells + 1; $L = $cells * 1.4142
    for ($y = 0; $y -lt $n; $y++) { for ($x = 0; $x -lt $n; $x++) {
        $u = (($x - $x0) - ($y - $y0)) / 1.4142; $v = (($x - $x0) + ($y - $y0)) / 1.4142; $t = $u / $L
        if ($t -lt -0.02 -or $t -gt 1.0) { continue }
        $w = $hw; if ($t -lt 0.3) { $w = [math]::Max(0.3, $hw * ($t / 0.3)) }
        if ([math]::Abs($v) -gt $w) { continue }
        if ($t -lt 0.1) { $c = 'K' } elseif ($t -lt 0.3) { $c = 'L' }
        elseif ($t -lt 0.78) { if ($v -gt $hw * 0.35) { $c = 'O' } else { $c = 'Y' } }
        elseif ($t -lt 0.88) { $c = 'G' } else { $c = 'R' }
        Put $g $x $y $c
    } }
    return $g
}
function G-PencilGlyph() {
    $g = New-Grid 8 8
    $p = G-Pencil 5 0.95; Outline $p
    Blit $g $p 0 0
    return $g
}

# ---- larger parts for the page illustrations
function Bevel($g, $x, $y, $w, $h, $body, $hi = 'W', $lo = 'D') {
    Rect $g $x $y $w $h 'K'; Rect $g ($x + 1) ($y + 1) ($w - 2) ($h - 2) $body
    Rect $g ($x + 1) ($y + 1) ($w - 2) 1 $hi; Rect $g ($x + 1) ($y + 1) 1 ($h - 2) $hi
    Rect $g ($x + $w - 2) ($y + 1) 1 ($h - 2) $lo; Rect $g ($x + 1) ($y + $h - 2) ($w - 2) 1 $lo
}
function Draw-PC($g, $x, $y, $screen) {
    Bevel $g $x $y 24 20 'L'
    Rect $g ($x + 3) ($y + 3) 18 14 'K'; Rect $g ($x + 4) ($y + 4) 16 12 $screen
    Put $g ($x + 19) ($y + 18) 'U'
    Rect $g ($x + 7) ($y + 20) 10 3 'K'; Rect $g ($x + 8) ($y + 20) 8 2 'L'; Rect $g ($x + 15) ($y + 20) 1 2 'D'
    Bevel $g ($x + 2) ($y + 22) 20 4 'L'
    Rect $g ($x + 5) ($y + 24) 6 1 'K'
}
function G-Notepad() {
    $g = New-Grid 20 27
    Bevel $g 0 3 20 24 'W' 'W' 'D'
    Rect $g 1 4 18 4 'B'; Rect $g 1 4 18 1 'C'
    for ($i = 0; $i -lt 4; $i++) { Rect $g (3 + 4 * $i) 0 2 5 'K'; Put $g (3 + 4 * $i) 1 'D' }
    $len = @(14, 11, 14, 8, 12)
    for ($i = 0; $i -lt 5; $i++) { Rect $g 3 (12 + 3 * $i) $len[$i] 1 'B' }
    return $g
}
function G-Lock($w, $h) {
    $g = New-Grid ($w + 2) ($h + 2); $cx = ($w - 1) / 2.0 + 1; $a = ($w - 6) / 2.0
    Disc $g $cx (1 + $a) $a 'G'; Rect $g (1 + 3) (1 + $a) ($w - 6) 5 'G'
    Disc $g $cx (1 + $a) ($a - 3) '.'; Rect $g (1 + 6) (1 + $a) ($w - 12) 5 '.'
    $top = [int](1 + $h * 0.42)
    Rect $g 1 $top $w ($h + 1 - $top) 'Y'
    Shade $g @{ 'Y' = @('W', 'O'); 'G' = @('W', 'D') }
    $ky = $top + [int](($h + 1 - $top) / 2) - 1
    Disc $g $cx $ky 2 'K'; Rect $g ([int]$cx) ($ky + 1) 2 4 'K'
    Outline $g; return $g
}
function G-Key($len) {
    $g = New-Grid ($len + 2) 12
    Disc $g 5 5 4.6 'Y'; Disc $g 5 5 1.8 '.'
    Rect $g 9 4 ($len - 8) 3 'Y'; Rect $g ($len - 8) 7 2 3 'Y'; Rect $g ($len - 4) 7 2 2 'Y'
    Shade $g @{ 'Y' = @('W', 'O') }; Outline $g; return $g
}
function G-Arrow($up, $len, $c) {
    $g = New-Grid 13 ($len + 2); $oy = 1
    if ($up) {
        Rect $g 4 ($oy + 6) 5 ($len - 6) $c
        for ($j = 0; $j -lt 6; $j++) { Rect $g (6 - $j) ($oy + $j) (1 + 2 * $j) 1 $c }
    } else {
        Rect $g 4 $oy 5 ($len - 6) $c
        for ($j = 0; $j -lt 6; $j++) { Rect $g (1 + $j) ($oy + $len - 6 + $j) (11 - 2 * $j) 1 $c }
    }
    Shade $g $ShadeAll; Outline $g; return $g
}
function G-Folder($w, $h, $open, $paper) {
    $g = New-Grid ($w + 2) ($h + 2); $ox = 1; $oy = 1; $tab = [int]($w * 0.4)
    if (-not $open) {
        Rect $g $ox $oy $tab 4 'Y'; Rect $g $ox ($oy + 3) $w ($h - 3) 'Y'
        Shade $g @{ 'Y' = @('W', 'O') }
        Rect $g ($ox + 1) ($oy + 3) ($w - 2) 1 'W'
        Rect $g ($ox + 1) ($oy + $tab) 1 1 'Y'
    } else {
        Rect $g $ox $oy $tab 4 'O'; Rect $g $ox ($oy + 3) $w ($h - 3) 'O'
        if ($paper) {
            Rect $g ($ox + 3) ($oy + 4) ($w - 9) 6 'W'
            Rect $g ($ox + 5) ($oy + 6) ($w - 13) 1 'D'; Rect $g ($ox + 5) ($oy + 8) ($w - 16) 1 'D'
        }
        Seg $g ($ox + 4) ($oy + 7) ($ox + $w - 1) ($oy + 7) 1 'K'
        Poly $g @(@(($ox + 5), ($oy + 8)), @(($ox + $w - 1), ($oy + 8)), @(($ox + $w - 5), ($oy + $h - 1)), @($ox, ($oy + $h - 1))) 'Y'
        Seg $g ($ox + 5) ($oy + 8) ($ox + $w - 1) ($oy + 8) 1 'W'
        Seg $g ($ox + $w - 5) ($oy + $h - 1) ($ox) ($oy + $h - 1) 1 'O'
    }
    Outline $g; return $g
}
function G-Clock($d) {
    $S = $d + 2; $cc = ($S - 1) / 2; $g = New-Grid $S $S; $rb = $d / 2.0 - 0.1
    Disc $g $cc $cc $rb 'G'; Disc $g $cc $cc ($rb - 2) 'W'
    Shade $g @{ 'G' = @('W', 'D') }
    $rt = $rb - 3.6
    for ($k = 0; $k -lt 12; $k++) {
        $a = $k * [math]::PI / 6
        $px = $cc + [int][math]::Round($rt * [math]::Sin($a)); $py = $cc - [int][math]::Round($rt * [math]::Cos($a))
        Put $g $px $py 'K'
        if ($k % 3 -eq 0) { $px2 = $cc + [int][math]::Round(($rt - 1) * [math]::Sin($a)); $py2 = $cc - [int][math]::Round(($rt - 1) * [math]::Cos($a)); Put $g $px2 $py2 'K' }
    }
    Seg $g $cc $cc $cc ($cc - [int]($rb - 4)) 1 'K'
    Seg $g $cc $cc ($cc + [int]($rb * 0.45)) $cc 1 'K'
    Put $g $cc $cc 'R'
    Outline $g; return $g
}
function Sparkle() {
    $s = New-Grid 5 5; $sp = @('..Y..', '.YWY.', 'YWWWY', '.YWY.', '..Y..')
    for ($j = 0; $j -lt 5; $j++) { for ($i = 0; $i -lt 5; $i++) { if ($sp[$j][$i] -ne '.') { Put $s $i $j $sp[$j][$i] } } }
    return $s
}
function Shadow($s, $cx, $cy, $rx) { Ellipse $s $cx $cy $rx 2 'Z' }

# ================================================================ PAGE ILLUSTRATIONS (35x57 grid, x4 = 140x228 on a 140x230 teal canvas)
$Scenes = [ordered]@{}
$Scenes['art-choose-folder'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 14
    Draw-PC $s 5 2 'N'
    Rect $s 9 6 14 10 'G'; Rect $s 9 6 14 2 'B'; Rect $s 10 6 1 1 'W'
    Rect $s 11 10 6 5 'Y'; Rect $s 11 9 3 1 'Y'; Rect $s 11 10 6 1 'W'
    Blit $s (G-Folder 28 22 $true $true) 3 31
    Blit $s (Sparkle) 29 28; Blit $s (Sparkle) 0 28
    return $s }
$Scenes['art-save-changes'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 13
    Blit $s (G-Notepad) 3 2
    $p = G-Pencil 12 1.9; Outline $p; Blit $s $p 15 15
    Blit $s $IconG['floppy'] 9 36
    Blit $s (Sparkle) 28 38; Blit $s (Sparkle) 2 33
    Rect $s 17 30 1 1 'W'; Rect $s 17 32 1 1 'W'; Rect $s 17 34 1 1 'W'
    return $s }
$Scenes['art-signin'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 12
    Blit $s (G-Lock 20 20) 1 1
    $k = G-Key 26; Blit $s $k 4 25
    Blit $s (G-Globe 19) 8 38
    Blit $s (Sparkle) 28 4
    return $s }
$Scenes['art-publish'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 12
    Blit $s $IconG['floppy'] 9 1
    Blit $s (G-Arrow $false 15 'E') 11 19
    Blit $s (G-Globe 21) 7 35
    Blit $s (Sparkle) 28 6
    return $s }
$Scenes['art-sync'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 10
    Draw-PC $s 5 1 'N'
    Rect $s 9 5 14 2 'C'; Rect $s 9 8 9 1 'W'; Rect $s 9 10 12 1 'W'; Rect $s 9 12 7 1 'W'
    Blit $s (G-Arrow $false 12 'E') 3 28
    Blit $s (G-Arrow $true 12 'B') 19 28
    Blit $s (G-Globe 17) 9 40
    return $s }
$Scenes['art-edit-history'] = {
    $s = New-Grid 35 57
    Blit $s (G-Clock 23) 5 0
    $tl = New-Grid 14 32
    Rect $tl 6 0 2 32 'D'
    foreach ($yy in 5, 16, 27) { Disc $tl 6.5 $yy 3.3 'Y' }
    Disc $tl 6.5 27 3.3 'U'
    Shade $tl @{ 'Y' = @('W', 'O'); 'U' = @('W', 'E') }
    Outline $tl
    Blit $s $tl 2 25
    foreach ($yy in 27, 38, 49) {
        Rect $s 13 ($yy - 1) 18 3 'W'; Rect $s 13 ($yy + 1) 18 1 'D'; Rect $s 13 ($yy - 1) 18 1 'W'
        Rect $s 14 ($yy) 12 1 'D'
    }
    Rect $s 14 49 6 1 'B'
    return $s }
$Scenes['art-success'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 14
    Draw-PC $s 5 2 'N'
    Seg $s 9 11 12 14 1 'U'; Seg $s 12 14 19 6 1 'U'; Seg $s 9 10 12 13 1 'U'; Seg $s 12 13 19 5 1 'U'
    $c = New-Grid 30 24
    Seg $c 4 11 11 18 5 'E'; Seg $c 11 18 25 4 5 'E'
    Shade $c $ShadeAll; Outline $c
    Blit $s $c 2 31
    Blit $s (Sparkle) 28 29; Blit $s (Sparkle) 0 31
    return $s }
$Scenes['art-warning'] = {
    $s = New-Grid 35 57
    Shadow $s 17 40 14
    $t = New-Grid 35 34
    Poly $t @(@(17, 1.5), @(33.5, 29.5), @(0.5, 29.5)) 'Y'
    Shade $t @{ 'Y' = @('W', 'O') }
    Rect $t 15 10 5 11 'K'; Rect $t 15 23 5 4 'K'
    Outline $t
    Blit $s $t 0 7
    Blit $s (Sparkle) 28 2; Blit $s (Sparkle) 1 45
    return $s }
$Scenes['art-error'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 14
    Draw-PC $s 5 2 'B'
    Rect $s 8 6 12 1 'W'; Rect $s 8 8 8 1 'W'; Rect $s 8 10 10 1 'W'; Rect $s 8 13 5 1 'W'
    $x = New-Grid 26 26
    Seg $x 4 4 21 21 6 'R'; Seg $x 21 4 4 21 6 'R'
    Shade $x $ShadeAll; Outline $x
    Blit $s $x 4 29
    return $s }
$Scenes['art-empty'] = {
    $s = New-Grid 35 57
    Shadow $s 17 46 14
    Blit $s (G-Folder 30 24 $true $false) 2 20
    foreach ($p in @(@(6, 10), @(16, 6), @(27, 12))) { Put $s $p[0] $p[1] 'W'; Put $s ($p[0] + 1) $p[1] 'W' }
    foreach ($p in @(@(11, 12), @(22, 9))) { Put $s $p[0] $p[1] 'D' }
    return $s }
$Scenes['art-untrusted'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 11
    $sh = New-Grid 31 34
    $outer = @(@(0, 2), @(15, 0), @(30, 2), @(30, 17), @(24, 25), @(15, 32), @(6, 25), @(0, 17))
    Poly $sh $outer 'G'
    $in = @(); foreach ($p in $outer) { $in += , @((15 + ($p[0] - 15) * 0.76), (16 + ($p[1] - 16) * 0.76)) }
    Poly $sh $in 'B'
    Shade $sh @{ 'G' = @('W', 'D'); 'B' = @($null, 'N') }
    Rect $sh 13 8 5 11 'Y'; Rect $sh 13 21 5 4 'Y'
    Outline $sh
    Blit $s $sh 2 1
    Blit $s (G-Lock 12 13) 11 40
    return $s }
$Scenes['art-offline'] = {
    $s = New-Grid 35 57
    Shadow $s 17 55 12
    Blit $s (G-Globe 23) 6 8
    $n = New-Grid 33 33
    Disc $n 16 16 15.4 'R'; Disc $n 16 16 11.4 '.'
    Seg $n 7 7 25 25 4 'R'
    Shade $n @{ 'R' = @($null, 'Q') }; Outline $n
    Blit $s $n 1 3
    Blit $s $IconG['floppy'] 9 39
    return $s }
$Scenes['art-undo'] = {
    $s = New-Grid 35 57
    Shadow $s 17 53 13
    Blit $s (G-Clock 19) 7 17
    $a = New-Grid 35 40
    ArcArrow $a 17 20 14.2 3.6 165 (-245) 6 4.6 'B'
    Shade $a @{ 'B' = @('C', 'N') }; Outline $a
    Blit $s $a 0 8
    return $s }

# ================================================================ BUILD
$IconG = [ordered]@{}
foreach ($k in $IconRows.Keys) { $IconG[$k] = Rows "icon-$k" $IconRows[$k] 16 16 }
$IconG['globe']      = G-Globe 16
$IconG['check']      = G-Check
$IconG['warning']    = G-Warning
$IconG['info']       = G-Info
$IconG['error']      = G-Error
$IconG['question']   = G-Question
$IconG['undo']       = Rows 'icon-undo' $UndoRows 16 16
$IconG['branch']     = G-Branch
$IconG['user']       = G-User
$IconG['refresh']    = G-Refresh
$IconG['settings']   = G-Gear
$IconG['help']       = G-Help
$IconG['document-new'] = G-DocNew $IconG['document']

$IconOrder = 'folder', 'folder-open', 'document', 'document-new', 'clock', 'globe', 'key', 'lock', 'floppy', 'cloud', 'check', 'warning', 'info', 'error', 'question', 'trash', 'undo', 'branch', 'user', 'calendar', 'refresh', 'github-cat', 'settings', 'help'

$GlyphG = [ordered]@{}
foreach ($k in $GlyphRows.Keys) { $GlyphG[$k] = Rows "glyph-$k" $GlyphRows[$k] 8 8 }
$GlyphG['pencil'] = G-PencilGlyph
$GlyphOrder = 'dot-green', 'dot-gray', 'pencil', 'merge', 'warning', 'lock'

$files = New-Object System.Collections.ArrayList
foreach ($k in $Scenes.Keys) {
    $s = & $Scenes[$k]
    $p = Join-Path $ArtDir "$k.png"
    Save-Grid $s $p 4 140 230 0 1 '#40A0A0'
    [void]$files.Add(@($p, '140x230', 'page illustration (35x57 grid x4, teal #40A0A0 canvas)'))
}
foreach ($k in $IconOrder) {
    $g = $IconG[$k]
    $p1 = Join-Path $ArtDir "icon-$k.png"; $p2 = Join-Path $ArtDir "icon-$k-32.png"
    Save-Grid $g $p1 1; Save-Grid $g $p2 2
    [void]$files.Add(@($p1, '16x16', 'icon, native pixels, transparent')); [void]$files.Add(@($p2, '32x32', 'icon, 2x nearest-neighbour of the 16x16'))
}
foreach ($k in $GlyphOrder) {
    $g = $GlyphG[$k]
    $p1 = Join-Path $ArtDir "glyph-$k.png"; $p2 = Join-Path $ArtDir "glyph-$k-16.png"
    Save-Grid $g $p1 1; Save-Grid $g $p2 2
    [void]$files.Add(@($p1, '8x8', 'list-row glyph, native pixels, transparent')); [void]$files.Add(@($p2, '16x16', 'list-row glyph, 2x nearest-neighbour of the 8x8'))
}

# ================================================================ CONTACT SHEET
function Draw-Img($gr, $path, $x, $y, $scale) {
    $img = New-Object System.Drawing.Bitmap $path
    $gr.DrawImage($img, (New-Object System.Drawing.Rectangle $x, $y, ($img.Width * $scale), ($img.Height * $scale)), 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $img.Dispose()
}
function Sunken($gr, $x, $y, $w, $h, $fill) {
    $gr.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($fill))), $x, $y, $w, $h)
    $gr.FillRectangle((Get-Brush 'D'), $x - 1, $y - 1, $w + 1, 1); $gr.FillRectangle((Get-Brush 'D'), $x - 1, $y - 1, 1, $h + 1)
    $gr.FillRectangle((Get-Brush 'W'), $x - 1, $y + $h, $w + 2, 1); $gr.FillRectangle((Get-Brush 'W'), $x + $w, $y - 1, 1, $h + 2)
}
$sheetW = 1090; $cols1 = 7; $cols2 = 10
$rows1 = [math]::Ceiling($Scenes.Count / $cols1); $rows2 = [math]::Ceiling($IconOrder.Count / $cols2)
$h1 = 250; $h2 = 130; $h3 = 130
$sheetH = 10 + 24 + 18 + $rows1 * $h1 + 18 + $rows2 * $h2 + 18 + $h3 + 10
$bmp = New-Object System.Drawing.Bitmap $sheetW, $sheetH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gr = [System.Drawing.Graphics]::FromImage($bmp)
$gr.SmoothingMode = 'None'; $gr.InterpolationMode = 'NearestNeighbor'; $gr.PixelOffsetMode = 'Half'; $gr.TextRenderingHint = 'SingleBitPerPixelGridFit'
$gr.Clear([System.Drawing.ColorTranslator]::FromHtml('#C0C0C0'))
$fb = New-Object System.Drawing.Font 'Arial', 13, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fs = New-Object System.Drawing.Font 'Arial', 11, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$black = Get-Brush 'K'; $navy = Get-Brush 'N'
$sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'
$y = 10
$gr.DrawString('backd8 art sheet - generated by assets\make-art.ps1 (all original pixel art; light from top-left, 1px black outline, Win98 palette)', $fb, $black, 10, $y); $y += 24
$gr.DrawString('Page illustrations 140x230 (art-*.png)', $fb, $navy, 10, $y); $y += 18
$i = 0
foreach ($k in $Scenes.Keys) {
    $cx = 10 + ($i % $cols1) * 150; $cy = $y + [math]::Floor($i / $cols1) * $h1
    Sunken $gr $cx $cy 140 230 '#40A0A0'
    Draw-Img $gr (Join-Path $ArtDir "$k.png") $cx $cy 1
    $gr.DrawString($k.Substring(4), $fs, $black, (New-Object System.Drawing.RectangleF $cx, ($cy + 233), 140, 14), $sf)
    $i++
}
$y += $rows1 * $h1
$gr.DrawString('Icons 16x16 (icon-NAME.png) and 32x32 (icon-NAME-32.png) - shown at 4x, then 1x and 2x', $fb, $navy, 10, $y); $y += 18
$i = 0
foreach ($k in $IconOrder) {
    $cx = 10 + ($i % $cols2) * 107; $cy = $y + [math]::Floor($i / $cols2) * $h2
    Sunken $gr ($cx + 14) $cy 72 72 '#C0C0C0'
    Draw-Img $gr (Join-Path $ArtDir "icon-$k.png") ($cx + 18) ($cy + 4) 4
    Sunken $gr ($cx + 8) ($cy + 78) 20 20 '#FFFFFF'; Draw-Img $gr (Join-Path $ArtDir "icon-$k.png") ($cx + 10) ($cy + 80) 1
    Sunken $gr ($cx + 36) ($cy + 78) 36 36 '#FFFFFF'; Draw-Img $gr (Join-Path $ArtDir "icon-$k-32.png") ($cx + 38) ($cy + 80) 1
    $gr.DrawString($k, $fs, $black, (New-Object System.Drawing.RectangleF ($cx - 4), ($cy + 114), 107, 14), $sf)
    $i++
}
$y += $rows2 * $h2
$gr.DrawString('Glyphs 8x8 (glyph-NAME.png, glyph-NAME-16.png) - shown at 8x, then 1x and 2x', $fb, $navy, 10, $y); $y += 18
$i = 0
foreach ($k in $GlyphOrder) {
    $cx = 10 + $i * 107; $cy = $y
    Sunken $gr ($cx + 14) $cy 72 72 '#C0C0C0'
    Draw-Img $gr (Join-Path $ArtDir "glyph-$k.png") ($cx + 18) ($cy + 4) 8
    Sunken $gr ($cx + 8) ($cy + 78) 12 12 '#FFFFFF'; Draw-Img $gr (Join-Path $ArtDir "glyph-$k.png") ($cx + 10) ($cy + 80) 1
    Sunken $gr ($cx + 36) ($cy + 78) 20 20 '#FFFFFF'; Draw-Img $gr (Join-Path $ArtDir "glyph-$k-16.png") ($cx + 38) ($cy + 80) 1
    $gr.DrawString($k, $fs, $black, (New-Object System.Drawing.RectangleF ($cx - 4), ($cy + 100), 107, 14), $sf)
    $i++
}
$gr.Dispose()
$bmp.Save((Join-Path $DocsDir 'art-sheet.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# ================================================================ README
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('backd8 pixel art - generated by assets\make-art.ps1 (re-run it to regenerate everything here).')
[void]$sb.AppendLine('All art is original. Palette: Win98 16 colours + #DFDFDF + teal #40A0A0. Light from top-left, 1px black outline.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('LOADING (PowerShell + WPF):')
[void]$sb.AppendLine('  . "$PSScriptRoot\assets\art\load-art.ps1"')
[void]$sb.AppendLine('  $src = Get-ArtBitmap ''art-signin''          # frozen BitmapImage, name = file name without .png')
[void]$sb.AppendLine('  $img = New-ArtImage ''icon-folder-32''        # Image control with NearestNeighbor already set')
[void]$sb.AppendLine('If you put the BitmapImage in your own <Image>, you MUST set')
[void]$sb.AppendLine('  [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, ''NearestNeighbor'')')
[void]$sb.AppendLine('  (XAML: RenderOptions.BitmapScalingMode="NearestNeighbor", SnapsToDevicePixels="True", UseLayoutRounding="True")')
[void]$sb.AppendLine('otherwise WPF smooths the pixels. Display at native size or an integer multiple.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('FILES (all PNG, in this folder):')
foreach ($f in $files) { [void]$sb.AppendLine(('  {0,-28} {1,-8} {2}' -f (Split-Path $f[0] -Leaf), $f[1], $f[2])) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  load-art.ps1                 dot-sourceable loader (Get-ArtBitmap, New-ArtImage)')
[void]$sb.AppendLine('  ..\..\docs\art-sheet.png       contact sheet of everything')
Set-Content -Path (Join-Path $ArtDir 'README.txt') -Value $sb.ToString() -Encoding ASCII

if ($script:Errs.Count) { Write-Host 'SPRITE ERRORS:' -ForegroundColor Red; $script:Errs | ForEach-Object { Write-Host "  $_" } }
Write-Host ("Done: {0} PNGs in {1}; sheet {2}" -f $files.Count, $ArtDir, (Join-Path $DocsDir 'art-sheet.png'))







