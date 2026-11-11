# Regenerates the README / product-shot pictures in docs\images from the REAL app, on fake sample data only:
#   hero.png  feature-edit.png  feature-github.png  feature-signin.png  feature-welcome.png  social.png  screenshots-sheet.png
# Run (one command):  powershell -ExecutionPolicy Bypass -File docs\make-hero.ps1
# Options:  -Gui <path to gui.ps1>   -Out <folder>   -Work <scratch folder>   -Only hero,social   -Shadow solid|dither|none   -KeepWork
#
# How it works: the app's own gui.ps1 is dot-sourced with -NoShow (no window is ever shown; windows are placed off-screen), driven into each
# state through its own functions against throw-away git repositories (fake author "Sim User", local bare "GitHub", no network), rendered with
# WPF RenderTargetBitmap at the exact size the composition needs, then composed with System.Drawing following the framing rules in
# docs\DESIGN.md section 7 (Stageshow framing): coloured stage, hero inset on the sides and running off the bottom through filler only,
# one gutter, a satellite straddling the hero's left edge over the black sidebar, hard Win98-style edges and shadows (no blur).
# It never touches the real config.json or the real ~/.gitconfig: git and backd8 are pointed at files inside -Work first, and the script
# refuses to run if git still reports the real global config.
param(
  [string]$Gui = '',
  [string]$Out = '',
  [string]$Work = '',
  [string[]]$Only = @(),
  [ValidateSet('solid', 'dither', 'none')][string]$Shadow = 'dither',
  [switch]$KeepWork
)
$ErrorActionPreference = 'Stop'
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
Add-Type -AssemblyName System.Drawing, PresentationCore, PresentationFramework, WindowsBase

# ------------------------------------------------------------------ paths
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $PSScriptRoot 'images' }
if (-not $Work) { $Work = Join-Path ([IO.Path]::GetTempPath()) 'backd8-hero' }
if (-not $Gui) { $Gui = Join-Path $repoRoot 'gui.ps1' }
if (-not (Test-Path -LiteralPath $Gui)) { throw "gui.ps1 not found: $Gui" }
if ((Get-Content -LiteralPath $Gui -Raw) -notmatch 'Show-WfState') { throw "This make-hero.ps1 drives the workflow-model build of the app (Show-WfState); $Gui is an older build. Pass -Gui <path of the new gui.ps1>." }
New-Item -ItemType Directory -Force $Out | Out-Null
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force $Work, "$Work\raw" | Out-Null
$Work = (Resolve-Path $Work).Path
$Out = (Resolve-Path $Out).Path
$assetsDir = Join-Path (Split-Path -Parent $Gui) 'assets'
if (-not (Test-Path $assetsDir)) { $assetsDir = Join-Path $repoRoot 'assets' }

# ------------------------------------------------------------------ isolation guard (FIRST, before any git call)
$env:GIT_CONFIG_GLOBAL = "$Work\gitconfig"
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:BACKDATE_CONFIG = "$Work\config.json"
$env:BACKD8_UI_STATE = "$Work\ui.json"
$env:GIT_TERMINAL_PROMPT = '0'
Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Value "[user]`n`tname = Sim User`n`temail = sim@example.com`n[init]`n`tdefaultBranch = main`n" -Encoding ascii
function Norm-Origin([string]$s) { ($s -replace '^file:', '' -replace '"', '' -replace '/', '\' -replace '\\+', '\').Trim().ToLowerInvariant() }
$origins = @(git config --global --list --show-origin 2>&1 | ForEach-Object { Norm-Origin ("$_" -split "`t")[0] } | Sort-Object -Unique)
$bad = @($origins | Where-Object { $_ -ne (Norm-Origin $env:GIT_CONFIG_GLOBAL) })
if (-not $origins.Count -or $bad.Count) { throw "ISOLATION GUARD: git global config is not the scratch file: $($origins -join ', ')" }
$env:GIT_AUTHOR_NAME = 'Sim User'; $env:GIT_AUTHOR_EMAIL = 'sim@example.com'; $env:GIT_COMMITTER_NAME = 'Sim User'; $env:GIT_COMMITTER_EMAIL = 'sim@example.com'

$FakeRoot = 'C:\Users\you\Projects'
$FakeUrl = 'https://github.com/sim-user/portfolio.git'
$script:Failures = @()
function Want([string]$n) { (-not $Only.Count) -or ($Only -contains $n) -or ($Only -contains ($n -replace '\.png$', '')) }
function Say([string]$m) { Write-Host $m }

# ------------------------------------------------------------------ fixtures (all local, fake data)
function G { $o = & git @args 2>&1; if ($LASTEXITCODE) { throw "git $($args -join ' ') failed: $o" }; $o }
function Commit([string]$repo, [string]$msg, [datetime]$when) { $iso = $when.ToString('s'); $env:GIT_AUTHOR_DATE = $iso; $env:GIT_COMMITTER_DATE = $iso; try { G -C $repo commit --allow-empty -q -m $msg | Out-Null } finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue } }
function New-Fixtures {
  $remote = "$Work\remotes\portfolio.git"; New-Item -ItemType Directory -Force "$Work\remotes", "$Work\scenarios" | Out-Null
  $base = "$Work\base\portfolio"; New-Item -ItemType Directory -Force $base | Out-Null
  G init -q -b main $base | Out-Null
  $t = (Get-Date).AddDays(-42).Date.AddHours(9).AddMinutes(14); $i = 0
  foreach ($s in 'Start the portfolio site', 'Add the home page layout', 'Add navigation bar', 'Style the hero section', 'Add project cards', 'Fix broken link in the footer', 'Add contact page', 'Improve mobile layout', 'Update the project descriptions', 'Add dark mode toggle', 'Fix typo on the about page', 'Compress images for faster loading') {
    $t = $t.AddHours(20 + ($i * 7 % 23)); Commit $base $s $t; $i++
  }
  G init -q --bare $remote | Out-Null
  G -C $base remote add origin $remote | Out-Null; G -C $base push -q -u origin main | Out-Null
  foreach ($n in 'portfolio', 'InventoryApp', 'blog-theme') { New-Item -ItemType Directory -Force "$Work\scenarios\recent\Projects\$n" | Out-Null }
}
# every scenario is a fresh clone of the fake GitHub plus a small recipe, so states can be entered any number of times
$Recipes = @{
  express = { param($p) Set-Content "$p\about.html" '<h1>About me</h1>'; New-Item -ItemType Directory "$p\styles" | Out-Null; Set-Content "$p\styles\theme.css" 'body { margin: 0 }'; Set-Content "$p\.env" 'MAIL_API_KEY=example' }
  edit    = { param($p) }
  replace = { param($p) G -C $p reset -q --soft HEAD~2 | Out-Null; Commit $p 'Update project descriptions and compress images' (Get-Date).AddDays(-3).Date.AddHours(18) }
  signin  = { param($p) Commit $p 'Add footer links' (Get-Date).AddDays(-1).Date.AddHours(20).AddMinutes(41) }
  insync  = { param($p) }
}
function Reset-Scenario([string]$name) {
  $d = "$Work\scenarios\$name"; if (Test-Path $d) { Remove-Item -Recurse -Force $d }
  New-Item -ItemType Directory -Force "$d\Projects" | Out-Null
  $p = "$d\Projects\portfolio"
  G clone -q "$Work\remotes\portfolio.git" $p | Out-Null
  G -C $p remote set-url origin $FakeUrl | Out-Null
  & $Recipes[$name] $p
}
Say 'fixtures...'; New-Fixtures
function Path-Of([string]$scenario) { "$Work\scenarios\$scenario\Projects\portfolio" }

# ------------------------------------------------------------------ load the app (no window is shown)
Set-Location (Split-Path -Parent $Gui)
. $Gui -NoShow
if (-not (Get-Command Show-WfState -ErrorAction SilentlyContinue)) { throw 'The app did not load (Show-WfState missing).' }
function Pump { 1..4 | ForEach-Object { DoEvents; Start-Sleep -Milliseconds 30 } }
function Prep($w) {
  $w.WindowStartupLocation = 'Manual'; $w.Left = -32000; $w.Top = -32000; $w.ShowActivated = $false; $w.ShowInTaskbar = $false
  if (-not $w.IsVisible) { $w.Show() }
  1..6 | ForEach-Object { DoEvents; Start-Sleep -Milliseconds 40 }; $w.UpdateLayout()
}

# fake paths on screen: every text the user could see that holds a scratch path is rewritten to C:\Users\you\Projects, then scanned for leaks
$scratchRx = '(?i)' + [regex]::Escape($Work) + '\\scenarios\\[^\\]+\\Projects'
function Each-Text($root, [scriptblock]$fn) {
  $stack = New-Object Collections.Generic.Stack[object]; $stack.Push($root)
  while ($stack.Count) {
    $o = $stack.Pop(); if ($null -eq $o) { continue }
    if ($o -is [Windows.Controls.TextBlock]) { & $fn $o; foreach ($i in $o.Inlines) { if ($i -is [Windows.Documents.Run]) { & $fn $i } } }
    elseif ($o -is [Windows.Controls.TextBox]) { & $fn $o }
    elseif ($o -is [Windows.Controls.ContentControl] -and $o.Content -is [string]) { & $fn $o }
    if ($o -is [Windows.DependencyObject]) {
      $n = 0; try { $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($o) } catch {}
      for ($k = 0; $k -lt $n; $k++) { $stack.Push([Windows.Media.VisualTreeHelper]::GetChild($o, $k)) }
      if ($n -eq 0 -and $o -is [Windows.FrameworkElement]) { foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($o)) { if ($c -is [Windows.DependencyObject]) { $stack.Push($c) } } }
    }
  }
}
function Get-Txt($o) { if ($o -is [Windows.Controls.ContentControl]) { [string]$o.Content } else { [string]$o.Text } }
function Set-Txt($o, [string]$v) { if ($o -is [Windows.Controls.ContentControl]) { $o.Content = $v } else { $o.Text = $v } }
function Scrub($root) {
  Each-Text $root {
    param($o) $t = Get-Txt $o
    if ($t -and $t -match [regex]::Escape($Work)) { $n = [regex]::Replace($t, $scratchRx, $FakeRoot.Replace('$', '$$')); $n = $n.Replace($Work, 'C:\Users\you'); if ($n -ne $t) { Set-Txt $o $n } }
  }
}
function Assert-NoLeaks($root, [string]$what) {
  $needles = @($env:USERNAME, $env:COMPUTERNAME, $env:USERPROFILE, $Work) | Where-Object { $_ -and $_.Length -gt 2 }
  Each-Text $root {
    param($o) $t = Get-Txt $o
    foreach ($nd in $needles) { if ($t -and $t.IndexOf($nd, [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "PRIVACY: '$nd' appears on screen in $what : $t" } }
  }
}

# window -> PNG (1:1, no scaling)
function Render-Win($w, [string]$file, [string]$what = '') {
  Scrub $w.Content; Assert-NoLeaks $w.Content $what
  $el = $w.Content; $cw = [int][math]::Ceiling($el.ActualWidth); $ch = [int][math]::Ceiling($el.ActualHeight)
  $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
  $vb = New-Object Windows.Media.VisualBrush($el); $vb.Stretch = 'None'; $vb.AlignmentX = 'Left'; $vb.AlignmentY = 'Top'
  $dc.DrawRectangle($vb, $null, (New-Object Windows.Rect(0, 0, $cw, $ch))); $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($cw, $ch, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($dv)
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($file); try { $enc.Save($fs) } finally { $fs.Close() }
  [pscustomobject]@{ File = $file; W = $cw; H = $ch }
}
# the main window at an exact size; returns where the page's footer (status bar + button row) starts, so the stage edge can fall above it
function Render-Main([string]$file, [int]$W, [int]$H, [int]$VisibleH = 0, [int]$Above = 78) {
  $f.WindowState = 'Normal'; $f.MinWidth = 0; $f.MinHeight = 0
  for ($pass = 0; $pass -lt 3; $pass++) {
    $f.Width = $W; $f.Height = $H; Prep $f; Pump; $f.UpdateLayout()
    $navTop = [double]$btnNext.TranslatePoint((New-Object Windows.Point(0, 0)), $f.Content).Y
    $cut = [int]($navTop - $Above)
    if (-not $VisibleH -or $cut -eq $VisibleH) { break }
    $H = $H + ($VisibleH - $cut)
  }
  $r = Render-Win $f $file 'main window'; $r | Add-Member Cut $(if ($VisibleH) { $VisibleH } else { $r.H }) -PassThru
}

# message boxes: the app's own Ask() window, captured instead of shown
function Capture-Msg([scriptblock]$Call, [string]$file, [int]$Width = 400, [switch]$Tick) {
  $script:AskCap = @{ File = $file; Width = $Width; Tick = [bool]$Tick; Result = $null }
  $script:AskCapture = {
    param($w, $def, $cancel)
    $c = $script:AskCap; $w.Width = $c.Width
    if ($c.Tick) { $st = New-Object Collections.Generic.Stack[object]; $st.Push($w.Content); while ($st.Count) { $o = $st.Pop(); if ($o -is [Windows.Controls.CheckBox]) { $o.IsChecked = $true; if ($o.Content -is [string]) { $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $o.Content; $tb.TextWrapping = 'Wrap'; $tb.FontWeight = $o.FontWeight; $o.Content = $tb } }; if ($o -is [Windows.DependencyObject]) { $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($o); for ($k = 0; $k -lt $n; $k++) { $st.Push([Windows.Media.VisualTreeHelper]::GetChild($o, $k)) } } } }
    Prep $w; Pump
    $c.Result = Render-Win $w $c.File 'message box'; $w.Close(); $cancel
  }
  try { & $Call | Out-Null } finally { $script:AskCapture = $null }
  $r = $script:AskCap.Result; if (-not $r) { throw 'message box was not captured' }; $r
}

# a small Win98 status card ("receipt") built from the app's own resources, fonts and bevels
function Capture-Card([string]$title, [string]$detail, [string]$icon, [string]$file, [int]$Width = 270) {
  $w = New-Object Windows.Window; $w.WindowStyle = 'None'; $w.ResizeMode = 'NoResize'; $w.SizeToContent = 'Height'; $w.Width = $Width; $w.ShowInTaskbar = $false
  $w.FontFamily = $script:FontUi; $w.FontSize = $script:BodySize; $w.UseLayoutRounding = $true; $w.SnapsToDevicePixels = $true
  [Windows.Media.TextOptions]::SetTextFormattingMode($w, 'Display'); [Windows.Media.TextOptions]::SetTextRenderingMode($w, 'Aliased'); [Windows.Media.TextOptions]::SetTextHintingMode($w, 'Fixed'); [Windows.Media.RenderOptions]::SetEdgeMode($w, 'Aliased')
  $w.Resources.MergedDictionaries.Add($script:Res); $w.SetResourceReference([Windows.Window]::BackgroundProperty, 'Face'); $w.SetResourceReference([Windows.Window]::ForegroundProperty, 'Text')
  $x = (BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}') + '<Border x:Name="body" Padding="12,10,12,10"/>' + $script:BvClose
  $x = $x -replace '^<Border ', '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" '
  $root = [Windows.Markup.XamlReader]::Parse($x); $w.Content = $root
  $g = New-Object Windows.Controls.Grid; foreach ($cw in 'Auto', '*') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cw; $g.ColumnDefinitions.Add($cd) }
  $ic = New-Icon $icon 28; $ic.VerticalAlignment = 'Top'; $ic.Margin = '0,1,12,0'; [Windows.Controls.Grid]::SetColumn($ic, 0); [void]$g.Children.Add($ic)
  $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
  [void]$sp.Children.Add((New-Tb $title 11 'Text' 'Bold')); $d = New-Tb $detail 11 'Text'; $d.Margin = '0,3,0,0'; [void]$sp.Children.Add($d)
  [void]$g.Children.Add($sp); $root.FindName('body').Child = $g
  Prep $w; Pump
  $r = Render-Win $w $file "card '$title'"; $w.Close(); $r
}

# ------------------------------------------------------------------ states of the app (each one = a page of the wizard, on fake data)
$signed = [pscustomobject]@{ GitInstalled = $true; Url = $FakeUrl; Transport = 'https'; CanPush = $true; Advice = @() }
$notSigned = [pscustomobject]@{ GitInstalled = $true; Url = $FakeUrl; Transport = 'https'; CanPush = $false; Advice = @() }
$twoAccounts = [pscustomobject]@{ GitInstalled = $true; Url = $FakeUrl; Transport = 'https'; CanPush = $false; NeedsAccountChoice = $true; Accounts = @('sim-user', 'sim-work'); Advice = @() }
function Open-Scenario([string]$name, $access = $signed) {
  Reset-Scenario $name; Reset-ELoaded; Pump
  Open-Folder (Path-Of $name) -NoFetch -NoAccess; Pump
  if ($access) { Set-EAccess $access $false } ; Pump
}
$States = [ordered]@{
  welcome = {
    $recent = @('portfolio', 'InventoryApp', 'blog-theme') | ForEach-Object { "$Work\scenarios\recent\Projects\$_" }
    Set-Content -LiteralPath $env:BACKD8_UI_STATE -Value (ConvertTo-Json @{ recent = @($recent) }) -Encoding utf8
    Reset-ELoaded; Refresh-Wf; Pump
  }
  express = {
    Open-Scenario 'express'
    $script:eAction = 'express'; $nMsg.Text = 'Add the about page and theme styles'; Set-NewWhen 'week'; Update-EUi; Pump
  }
  edit = {
    Open-Scenario 'edit'
    # a first edit really applied, so a backup exists ("Undo last edit" is live), then two new edits waiting
    $c0 = $script:eCommits | Where-Object { $_.Subject -eq 'Compress images for faster loading' } | Select-Object -First 1
    [void](Set-CommitEdits $script:eFolder @{ $c0.Sha = @{ message = 'Compress images for faster page loads' } })
    Do-ELoad $script:eFolder -NoAccess; Set-EAccess $signed $false
    $script:eSub = 'edit'; Show-WfState; Pump
    $cs = $script:eCommits
    $c1 = $cs | Where-Object { $_.Subject -eq 'Fix typo on the about page' } | Select-Object -First 1
    $c2 = $cs | Where-Object { $_.Subject -eq 'Add project cards' } | Select-Object -First 1
    Do-ESelect $c1.Sha; $eMsg.Text = 'Fix typo on the About page'; Do-EStage
    Do-ESelect $c2.Sha; $ePick.Value = $c2.Date.AddDays(-9); Do-EStage
    $script:eFilling = $true; foreach ($it in $lbHist.Items) { $it.IsSelected = ($it.Tag -eq $c2.Sha) }; $script:eFilling = $false
    $script:eSub = 'edit'; Show-WfState; Update-EUi; Pump
  }
  github = {
    Open-Scenario 'replace'; Pump
  }
  signin = {
    Open-Scenario 'signin' $twoAccounts; Pump
  }
  finish = {
    Open-Scenario 'insync'; Go-Page 5; Update-EUi; Pump
  }
}
function Enter-State([string]$name) { & $States[$name]; Say "  state $name -> $($script:eWf.State) (page $($script:wizPage))" }

# ------------------------------------------------------------------ GDI+ composition
function C([string]$hex) { $h = $hex.TrimStart('#'); [Drawing.Color]::FromArgb(255, [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)) }
$StageHex = '#3A3A9C'
function Load-Bmp([string]$file) {
  $img = [Drawing.Image]::FromFile($file); try { $b = New-Object Drawing.Bitmap $img.Width, $img.Height, ([Drawing.Imaging.PixelFormat]::Format24bppRgb); $g = [Drawing.Graphics]::FromImage($b); $g.DrawImage($img, 0, 0, $img.Width, $img.Height); $g.Dispose(); $b } finally { $img.Dispose() }
}
function New-Canvas([int]$w, [int]$h) {
  $b = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format24bppRgb); $g = [Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'None'; $g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'; $g.CompositingQuality = 'AssumeLinear'
  $br = New-Object Drawing.SolidBrush (C $StageHex); $g.FillRectangle($br, 0, 0, $w, $h); $br.Dispose()
  [pscustomobject]@{ Bmp = $b; G = $g; W = $w; H = $h }
}
function Fill-Rect($cv, [string]$hex, $x, $y, $w, $h) { $br = New-Object Drawing.SolidBrush (C $hex); $cv.G.FillRectangle($br, [int]$x, [int]$y, [int]$w, [int]$h); $br.Dispose() }
# the hard Win98 shadow: a solid (or 50% dithered) copy of the silhouette, offset down-right, then a 1px black edge on the object itself
function Draw-Lifted($cv, $bmp, [int]$x, [int]$y, [int]$srcH, [int]$off, [string]$shadowHex) {
  $w = $bmp.Width
  if ($Shadow -ne 'none' -and $off -gt 0) {
    if ($Shadow -eq 'solid') { Fill-Rect $cv $shadowHex ($x + $off) ($y + $off) $w $srcH }
    else {
      $col = C $shadowHex
      foreach ($pass in 0, 1) {
        if ($pass -eq 0) { $xs = ($x + $w); $xe = $x + $w + $off - 1; $ys = $y + $off; $ye = $y + $srcH + $off - 1 } else { $xs = $x + $off; $xe = $x + $w - 1; $ys = $y + $srcH; $ye = $y + $srcH + $off - 1 }
        for ($px = $xs; $px -le $xe; $px++) { for ($py = $ys; $py -le $ye; $py++) { if ((($px + $py) % 2) -eq 0 -and $px -ge 0 -and $py -ge 0 -and $px -lt $cv.W -and $py -lt $cv.H) { $cv.Bmp.SetPixel($px, $py, $col) } } }
      }
    }
  }
  $cv.G.DrawImage($bmp, (New-Object Drawing.Rectangle($x, $y, $w, $srcH)), (New-Object Drawing.Rectangle(0, 0, $w, $srcH)), [Drawing.GraphicsUnit]::Pixel)
  $pen = New-Object Drawing.Pen ([Drawing.Color]::Black), 1; $cv.G.DrawRectangle($pen, $x - 1, $y - 1, $w + 1, $srcH + 1); $pen.Dispose()
}
function Save-Image($img, [string]$file) { $ms = New-Object IO.MemoryStream; try { $img.Save($ms, [Drawing.Imaging.ImageFormat]::Png); [IO.File]::WriteAllBytes($file, $ms.ToArray()) } finally { $ms.Dispose() } }
function Save-Png($cv, [string]$file) {
  $bmp = $cv.Bmp; $cv.G.Dispose()
  $w = $bmp.Width; $h = $bmp.Height
  $rect = New-Object Drawing.Rectangle(0, 0, $w, $h); $d = $bmp.LockBits($rect, 'ReadOnly', [Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $buf = New-Object byte[] ($d.Stride * $h); [Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length); $stride = $d.Stride; $bmp.UnlockBits($d)
  $map = New-Object 'Collections.Generic.Dictionary[int,int]'; $pal = New-Object 'Collections.Generic.List[int]'; $ok = $true
  $idx = New-Object byte[] ($w * $h)
  for ($y = 0; $y -lt $h -and $ok; $y++) {
    $o = $y * $stride
    for ($x = 0; $x -lt $w; $x++) {
      $k = ([int]$buf[$o + $x * 3 + 2] -shl 16) -bor ([int]$buf[$o + $x * 3 + 1] -shl 8) -bor [int]$buf[$o + $x * 3]
      $i = 0; if (-not $map.TryGetValue($k, [ref]$i)) { if ($pal.Count -ge 256) { $ok = $false; break }; $i = $pal.Count; $map[$k] = $i; $pal.Add($k) }
      $idx[$y * $w + $x] = [byte]$i
    }
  }
  if ($ok) {
    $b8 = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format8bppIndexed)
    $cp = $b8.Palette; for ($i = 0; $i -lt $pal.Count; $i++) { $k = $pal[$i]; $cp.Entries[$i] = [Drawing.Color]::FromArgb(255, ($k -shr 16) -band 255, ($k -shr 8) -band 255, $k -band 255) }; $b8.Palette = $cp
    $d8 = $b8.LockBits($rect, 'WriteOnly', [Drawing.Imaging.PixelFormat]::Format8bppIndexed)
    for ($y = 0; $y -lt $h; $y++) { [Runtime.InteropServices.Marshal]::Copy($idx, $y * $w, [IntPtr]($d8.Scan0.ToInt64() + $y * $d8.Stride), $w) }
    $b8.UnlockBits($d8); Save-Image $b8 $file; $b8.Dispose()
  } else { Save-Image $bmp $file }
  $bmp.Dispose()
  $len = (Get-Item $file).Length; Say ("  wrote {0}  {1}x{2}  {3:N0} KB{4}" -f (Split-Path $file -Leaf), $w, $h, ($len / 1KB), $(if ($ok) { "  (palette $($pal.Count))" } else { '' }))
  if ($len -gt 400KB) { $script:Failures += "$(Split-Path $file -Leaf) is $([int]($len/1KB)) KB (> 400 KB)" }
}

# ------------------------------------------------------------------ the stage layout
# One gutter G. The hero (the app window) is inset G from the top and right and G + (the satellite's outside part) from the left, and runs off the
# bottom: the stage edge falls through filler only (the app window is rendered tall enough that the status bar and button row lie below the cut).
# The satellite straddles the hero's left edge over the black sidebar; its top is placed automatically below the last real content it would cover.
Add-Type -TypeDefinition @'
public static class HeroScan {
  // first row below the last "content" row in columns x0..x1-1, scanning up from yMax; a column's filler colour = the pixel at its yMax row
  public static int FreeTop(byte[] buf, int stride, int x0, int x1, int yMax, int yMin) {
    int worst = yMin;
    for (int x = x0; x < x1; x++) {
      int o = x * 3; int bb = buf[yMax * stride + o], bg = buf[yMax * stride + o + 1], br = buf[yMax * stride + o + 2];
      for (int y = yMax; y >= yMin; y--) { int p = y * stride + o; if (buf[p] != bb || buf[p + 1] != bg || buf[p + 2] != br) { if (y + 1 > worst) worst = y + 1; break; } }
    }
    return worst;
  }
  // 1 for every row whose pixels across columns x0..x1-1 are (almost) one flat colour = a gap between lines, not a glyph
  public static byte[] CleanRows(byte[] buf, int stride, int x0, int x1, int height, int tol) {
    byte[] res = new byte[height];
    for (int y = 0; y < height; y++) {
      int bad = 0; int rb = buf[y * stride + x0 * 3], rg = buf[y * stride + x0 * 3 + 1], rr = buf[y * stride + x0 * 3 + 2];
      for (int x = x0; x < x1; x++) { int p = y * stride + x * 3; if (buf[p] != rb || buf[p + 1] != rg || buf[p + 2] != rr) bad++; }
      res[y] = (byte)(bad <= tol ? 1 : 0);
    }
    return res;
  }
  // (older helper) a row r is a clean cut when the rows r-half .. r+half-1 are (almost) one flat colour across columns x0..x1-1 (a gap between lines of text, not through a glyph)
  public static int CleanCut(byte[] buf, int stride, int x0, int x1, int yFrom, int yTo, int half, int tol, int height) {
    for (int r = yFrom; r <= yTo; r++) {
      bool ok = true;
      for (int y = r - half; y < r + half && ok; y++) {
        if (y < 0 || y >= height) { ok = false; break; }
        int bad = 0; int rb = buf[y * stride + x0 * 3], rg = buf[y * stride + x0 * 3 + 1], rr = buf[y * stride + x0 * 3 + 2];
        for (int x = x0; x < x1; x++) { int p = y * stride + x * 3; if (buf[p] != rb || buf[p + 1] != rg || buf[p + 2] != rr) bad++; }
        if (bad > tol) ok = false;
      }
      if (ok) return r;
    }
    return -1;
  }
}
'@
function Get-Pixels($bmp) {
  $rect = New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height); $d = $bmp.LockBits($rect, 'ReadOnly', [Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $buf = New-Object byte[] ($d.Stride * $bmp.Height); [Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length); $stride = $d.Stride; $bmp.UnlockBits($d)
  @{ Buf = $buf; Stride = $stride }
}
function Free-Top($bmp, [int]$x0, [int]$x1, [int]$yMax, [int]$yMin = 60) { $p = Get-Pixels $bmp; [HeroScan]::FreeTop($p.Buf, $p.Stride, $x0, [math]::Min($x1, $bmp.Width), $yMax, $yMin) }
# best row in [yFrom, yTo] to end the hero: at least 3 clean rows below it (no glyph sliced) and as many clean rows above it as possible (up to $Want), so no text hugs the stage edge
function Clean-Cut($bmp, [int]$x0, [int]$x1, [int]$yFrom, [int]$yTo, [int]$Want = 16) {
  $p = Get-Pixels $bmp; $rows = [HeroScan]::CleanRows($p.Buf, $p.Stride, $x0, $x1, $bmp.Height, 14); $yTo = [math]::Min($yTo, $bmp.Height - 4)
  $best = -1; $bestAbove = -1
  for ($r = $yFrom; $r -le $yTo; $r++) {
    if (-not ($rows[$r] -and $rows[$r + 1] -and $rows[$r + 2])) { continue }
    $above = 0; while ($above -lt $Want -and ($r - 1 - $above) -ge 0 -and $rows[$r - 1 - $above]) { $above++ }
    if ($above -gt $bestAbove) { $best = $r; $bestAbove = $above }
    if ($above -ge $Want) { break }
  }
  [pscustomobject]@{ Row = $best; Above = $bestAbove }
}
$script:Report = @()
# $Flex: the stage may grow by up to this many pixels so the bottom edge falls in a gap between lines of text instead of through a glyph (0 = fixed stage height)
function Compose-Stage([string]$name, [int]$W, [int]$H, [string]$state, $sat, [int]$G = 40, [int]$Gap = 24, [int]$Flex = 0) {
  $outside = if ($sat) { [int]$sat.Out } else { 0 }
  $L = $G + $outside; $heroW = $W - $L - $G; $vis = $H - $G
  Enter-State $state
  $hero = Render-Main "$Work\raw\$name-hero.png" $heroW ($vis + $Flex + 134) ($vis + $Flex)
  $hb = Load-Bmp $hero.File
  $cx0 = [int]($heroW * 0.4); try { $cx0 = [int]($artHost.TranslatePoint((New-Object Windows.Point(0, 0)), $f.Content).X + $artHost.ActualWidth + 24) } catch { }
  $cc = Clean-Cut $hb $cx0 ($heroW - 70) $vis ($vis + $Flex); $cut = $cc.Row
  if ($cut -lt 0) { $cut = $vis; $script:Report += "$name : NOTE the bottom edge cuts through text (no clean gap within $Flex px)" }
  elseif ($cut -ne $vis -and -not $Flex) { $script:Report += "$name : NOTE the bottom edge cuts through text; a clean gap is $($cut - $vis) px lower (stage height is fixed)"; $cut = $vis }
  elseif ($cc.Above -lt 10) { $script:Report += "$name : NOTE text ends only $($cc.Above) px above the stage edge (no roomier gap within $Flex px)" }
  $H = $G + $cut; $vis = $cut
  $cv = New-Canvas $W $H
  Draw-Lifted $cv $hb $L $G $vis 4 '#000000'
  if ($sat) {
    $satB = Load-Bmp (& $sat.Make "$Work\raw\$name-sat.png")
    $free = Free-Top $hb 0 ($satB.Width - $outside) ($vis - 3)
    $sy = $free + $Gap; $sx = $L - $outside
    $bottomGap = $H - ($G + $sy + $satB.Height)
    $script:Report += "$name : stage ${W}x$H, hero ${heroW}px wide, satellite $($satB.Width)x$($satB.Height) at ($sx,$($G + $sy)) covers hero content down to y=$free, gap below it $bottomGap px (gutter $G)"
    if ($bottomGap -lt [int]($G * 0.75)) { $script:Failures += "$name : satellite is too low (only $bottomGap px above the stage edge, gutter is $G): make the stage taller or the satellite shorter" }
    Draw-Lifted $cv $satB $sx ($G + $sy) $satB.Height 3 '#000000'; $satB.Dispose()
  } else { $script:Report += "$name : stage ${W}x$H, hero ${heroW}px wide, gutter $G on three sides" }
  $hb.Dispose()
  Save-Png $cv "$Out\$name.png"
}
function Save-Fail([string]$what, $err) { $script:Failures += "$what : $($err.Exception.Message)"; Write-Warning "$what FAILED: $($err.Exception.Message)`n$($err.ScriptStackTrace)" }

# retro text (the app's own pixel font) for the social card and the sheet captions
$script:Fonts = New-Object Drawing.Text.PrivateFontCollection
foreach ($fn in 'DotGothic16-Regular.ttf') { $p = Join-Path $assetsDir "fonts\$fn"; if (Test-Path $p) { $script:Fonts.AddFontFile($p) } }
function Get-PixelFont([float]$px) { if ($script:Fonts.Families.Count) { New-Object Drawing.Font($script:Fonts.Families[0], $px, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel) } else { New-Object Drawing.Font('Tahoma', $px, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel) } }
function Draw-Text($cv, [string]$text, $font, [string]$hex, [int]$x, [int]$y, [int]$shadow = 0, [string]$hint = 'SingleBitPerPixelGridFit') {
  $cv.G.TextRenderingHint = $hint
  if ($shadow) { $b = New-Object Drawing.SolidBrush ([Drawing.Color]::Black); $cv.G.DrawString($text, $font, $b, [single]($x + $shadow), [single]($y + $shadow), [Drawing.StringFormat]::GenericTypographic); $b.Dispose() }
  $b = New-Object Drawing.SolidBrush (C $hex); $cv.G.DrawString($text, $font, $b, [single]$x, [single]$y, [Drawing.StringFormat]::GenericTypographic); $b.Dispose()
}

# ------------------------------------------------------------------ the images
$FeatW = 1200; $FeatH = 760
if (Want 'hero.png') {
  Say 'hero.png'
  try {
    Compose-Stage 'hero' 1280 640 'express' @{
      Out = 120
      Make = { param($f) (Capture-Msg { Ask 'backd8 Setup' 'Publish to GitHub?' "2 files are saved as one commit, dated 1 week ago, and sent to github.com/sim-user/portfolio." @('Publish', 'Cancel') 0 'question' } $f 400).File }
    }
  } catch { Save-Fail 'hero.png' $_ }
}
if (Want 'feature-edit.png') {
  Say 'feature-edit.png'
  try {
    Compose-Stage 'feature-edit' $FeatW $FeatH 'edit' @{
      Out = 100
      Make = { param($f) (Capture-Card 'Undo available' "Your last edit is backed up on this PC.`nUndo last edit puts it back." 'clock' $f 250).File }
    } -Flex 56
  } catch { Save-Fail 'feature-edit.png' $_ }
}
if (Want 'feature-github.png') {
  Say 'feature-github.png'
  try {
    Compose-Stage 'feature-github' $FeatW $FeatH 'github' @{
      Out = 160
      Make = { param($f) (Capture-Msg {
            Ask "backd8 Setup - replace GitHub's version" "Replace GitHub's version of 'main'?" "GitHub still has an older version of this branch. If you continue, GitHub's 2 old commits are REPLACED (deleted there) and your 1 commit takes their place." @("Replace GitHub's version", 'Cancel') 1 'error' '' -1 0 'I understand GitHub will lose the old version of this branch' } $f 440 -Tick).File }
    } -Flex 56
  } catch { Save-Fail 'feature-github.png' $_ }
}
if (Want 'feature-signin.png') {
  Say 'feature-signin.png'
  try { Compose-Stage 'feature-signin' $FeatW $FeatH 'signin' $null 100 -Flex 56 } catch { Save-Fail 'feature-signin.png' $_ }
}
if (Want 'feature-welcome.png') {
  Say 'feature-welcome.png'
  try { Compose-Stage 'feature-welcome' $FeatW $FeatH 'welcome' $null 100 -Flex 56 } catch { Save-Fail 'feature-welcome.png' $_ }
}

# social card 1200x630: copy beside the hero (corner layout): logo + wordmark + one line on the left, the Express page on the right, running off the bottom
if (Want 'social.png') {
  Say 'social.png'
  try {
    $W = 1200; $H = 630; $G = 40; $heroW = 860; $L = $W - $G - $heroW; $vis = $H - $G
    Enter-State 'express'
    $hb = Load-Bmp (Render-Main "$Work\raw\social-hero.png" $heroW ($vis + 134) $vis).File
    $cv = New-Canvas $W $H
    Draw-Lifted $cv $hb $L $G $vis 4 '#000000'; $hb.Dispose()
    $logoFile = Join-Path $PSScriptRoot 'images\logo.png'
    $lines = @('Choose a folder.', 'Edit the dates.', 'Publish to GitHub.')
    $fW = New-Object Drawing.Font('Arial', 62, ([Drawing.FontStyle]::Bold -bor [Drawing.FontStyle]::Italic), [Drawing.GraphicsUnit]::Pixel)
    $fT = Get-PixelFont 24
    $logoH = 0; if (Test-Path $logoFile) { $logoH = 128 }
    $blockH = $(if ($logoH) { $logoH + 24 } else { 0 }) + 68 + 18 + $lines.Count * 32
    $y = [int](($H - $blockH) / 2) - 8; $x = $G
    if ($logoH) {
      $lg0 = Load-Bmp $logoFile; $lg = New-Object Drawing.Bitmap 128, 128, ([Drawing.Imaging.PixelFormat]::Format24bppRgb); $lgg = [Drawing.Graphics]::FromImage($lg); $lgg.InterpolationMode = 'NearestNeighbor'; $lgg.PixelOffsetMode = 'Half'; $lgg.DrawImage($lg0, 0, 0, 128, 128); $lgg.Dispose(); $lg0.Dispose(); Draw-Lifted $cv $lg $x $y 128 4 '#000000'; $lg.Dispose()
      $y += 128 + 24
    }
    Draw-Text $cv 'backd8' $fW '#FFFFFF' $x $y 4 'AntiAliasGridFit'
    $y += 68 + 18
    foreach ($ln in $lines) { Draw-Text $cv $ln $fT '#FFFFFF' ($x + 2) $y 2; $y += 32 }
    Save-Png $cv "$Out\social.png"
  } catch { Save-Fail 'social.png' $_ }
}

# the sheet: every page of the wizard at half size, captioned
if (Want 'screenshots-sheet.png') {
  Say 'screenshots-sheet.png'
  try {
    $pages = @(@('welcome', 'Choose your project'), @('express', 'Save your changes'), @('edit', 'Change an older commit'), @('signin', 'Pick a GitHub account'), @('github', 'Replace GitHub''s old version'), @('finish', 'Everything is published'))
    $cw = 480; $ch = 360; $gut = 32; $cap = 34
    $sheetW = 3 * $cw + 4 * $gut; $sheetH = 2 * ($ch + $cap) + 3 * $gut
    $cv = New-Canvas $sheetW $sheetH; $fC = Get-PixelFont 16; $i = 0
    foreach ($pg in $pages) {
      Enter-State $pg[0]
      $r = Render-Main "$Work\raw\sheet-$($pg[0]).png" 960 720
      $full = Load-Bmp $r.File
      $small = New-Object Drawing.Bitmap $cw, $ch, ([Drawing.Imaging.PixelFormat]::Format24bppRgb); $sg = [Drawing.Graphics]::FromImage($small); $sg.InterpolationMode = 'HighQualityBicubic'; $sg.PixelOffsetMode = 'Half'; $sg.DrawImage($full, 0, 0, $cw, $ch); $sg.Dispose(); $full.Dispose()
      $col = $i % 3; $row = [math]::Floor($i / 3)
      $x = $gut + $col * ($cw + $gut); $y = $gut + $row * ($ch + $cap + $gut)
      Draw-Lifted $cv $small $x $y $ch 3 '#000000'; $small.Dispose()
      $tw = [int]($cv.G.MeasureString($pg[1], $fC, 2000, [Drawing.StringFormat]::GenericTypographic).Width)
      Draw-Text $cv $pg[1] $fC '#FFFFFF' ($x + [int](($cw - $tw) / 2)) ($y + $ch + 12) 0
      $i++
    }
    Save-Png $cv "$Out\screenshots-sheet.png"
  } catch { Save-Fail 'screenshots-sheet.png' $_ }
}

# markdown to paste into the README
if (-not $Only.Count -or (Want 'README-hero-snippet')) {
  $snip = @'
<!-- generated by docs\make-hero.ps1 - paste into README.md (paths are relative to the repository root) -->

<p align="center">
  <img src="docs/images/hero.png" width="830" alt="backd8 Setup: the 'Save your changes' page of the Windows 98 Setup-style wizard, with a 'Publish to GitHub?' message box over its sidebar">
</p>

## What it looks like

<table>
  <tr>
    <td width="50%"><img src="docs/images/feature-welcome.png" alt="First run: choose the folder that holds your project, or pick a recent one"><br><sub><b>1. Choose a folder</b> - pick the project (or drop it on the window).</sub></td>
    <td width="50%"><img src="docs/images/feature-edit.png" alt="The history editor with two edits waiting and an 'Undo available' note"><br><sub><b>2. Edit the dates</b> - change older commits; every edit can be undone.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/feature-signin.png" alt="Which GitHub account? Choose one of the accounts saved on this PC"><br><sub><b>3. Sign in once</b> - backd8 never stores a password or token.</sub></td>
    <td width="50%"><img src="docs/images/feature-github.png" alt="Replace GitHub's old version: a confirmation that names exactly what will be replaced"><br><sub><b>4. Publish to GitHub</b> - replacing the old version always asks first, by name.</sub></td>
  </tr>
</table>

<details>
<summary>All pages at a glance</summary>

<img src="docs/images/screenshots-sheet.png" width="830" alt="All pages of the backd8 Setup wizard: choose a project, save your changes, change an older commit, pick a GitHub account, replace GitHub's old version, done">

</details>

<!-- social preview (GitHub > Settings > Social preview, 1200x630): docs/images/social.png -->
'@
  Set-Content -LiteralPath "$Out\README-hero-snippet.md" -Value $snip -Encoding utf8
  Say '  wrote README-hero-snippet.md'
}

if ($script:Report.Count) { Say ''; $script:Report | ForEach-Object { Say "  $_" } }
if ($Failures.Count) { Write-Warning ("PROBLEMS:`n  " + ($Failures -join "`n  ")); exit 1 }
Say 'done'







