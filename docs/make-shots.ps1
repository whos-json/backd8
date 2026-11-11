# Renders the README screenshots from the REAL backd8 window (not a mock).
#   powershell -STA -ExecutionPolicy Bypass -File docs\make-shots.ps1
# Safe by construction: a private git config and settings file (your real ones are never touched), demo projects on a temporary virtual
# drive, a local bare repository as the fake GitHub (no network), the window is drawn off-screen (nothing appears on your desktop).
param([string]$ImgDir = (Join-Path $PSScriptRoot 'images'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) "backd8-shots-$PID"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $work | Out-Null
$env:GIT_CONFIG_GLOBAL = Join-Path $work 'fake.gitconfig'; Set-Content $env:GIT_CONFIG_GLOBAL "[user]`n`tname = Sim User`n`temail = sim@example.com`n[init]`n`tdefaultBranch = main`n[protocol `"file`"]`n`tallow = always`n" -Encoding ascii
$env:BACKDATE_CONFIG = Join-Path $work 'config.json'; $env:BACKD8_UI_STATE = Join-Path $work 'ui.json'; $env:GIT_TERMINAL_PROMPT = '0'
$origins = @(git config --global --list --show-origin 2>&1 | ForEach-Object { ("$_" -split "`t")[0] } | Sort-Object -Unique)
if (@($origins | Where-Object { $_ -notmatch [regex]::Escape((Split-Path $env:GIT_CONFIG_GLOBAL -Leaf)) }).Count) { throw "ISOLATION GUARD: git sees $($origins -join ', ')" }

# 100% scale: make this process DPI-unaware BEFORE WPF loads, so layout and capture are exactly 96 dpi (the live app is drawn bilevel)
Add-Type -Namespace Win -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);'
[void][Win.Dpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-1))

# a short fake drive letter so no real user name or long temp path shows up in the pictures
$drive = $null; foreach ($l in 'P', 'Q', 'R', 'S', 'T', 'U') { if (-not (Test-Path "${l}:\")) { $drive = "${l}:"; break } }
if (-not $drive) { throw 'no free drive letter for the demo projects' }
New-Item -ItemType Directory (Join-Path $work 'demo') | Out-Null; & subst.exe $drive (Join-Path $work 'demo') | Out-Null
try {
  $PD = "$drive\Projects"; $RD = "$drive\remotes"; New-Item -ItemType Directory $PD, $RD | Out-Null
  function Run-Git { param([string]$Repo, [string[]]$A) & git -C $Repo @A 2>&1 | Out-Null }
  function New-Demo([string]$name, [string[]]$subjects, [int]$daysBack) {
    $p = "$PD\$name"; New-Item -ItemType Directory $p | Out-Null; Run-Git $p @('init', '-q', '-b', 'main'); Run-Git $p @('config', 'user.name', 'Sim User'); Run-Git $p @('config', 'user.email', 'sim@example.com')
    $t = (Get-Date).AddDays(-$daysBack).Date.AddHours(9).AddMinutes(14); $i = 0
    foreach ($s in $subjects) { $t = $t.AddHours(20 + (($i * 7) % 23)); $iso = $t.ToString('s'); $env:GIT_AUTHOR_DATE = $iso; $env:GIT_COMMITTER_DATE = $iso; Set-Content "$p\f$i.txt" "$s"; Run-Git $p @('add', '-A'); Run-Git $p @('commit', '-q', '-m', $s); $i++ }
    Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    $bare = "$RD\sim-user\$name.git"; New-Item -ItemType Directory (Split-Path $bare) -Force | Out-Null; Run-Git $PD @('init', '-q', '--bare', '-b', 'main', $bare)
    Run-Git $p @('remote', 'add', 'origin', $bare); Run-Git $p @('push', '-q', '-u', 'origin', 'main'); $p
  }
  $pf = New-Demo 'portfolio' @('Start the portfolio site', 'Add the home page layout', 'Add navigation bar', 'Style the hero section', 'Add project cards', 'Fix broken link in the footer', 'Add contact page', 'Improve mobile layout', 'Update the project descriptions', 'Add dark mode toggle', 'Fix typo on the about page', 'Compress images for faster loading') 42
  $blog = New-Demo 'blog' @('Set up the blog', 'Write the first post', 'Add an RSS feed', 'Fix the date format') 20
  $notes = New-Demo 'notes' @('Start the notes app','Add a note list','Add search','Fix empty-state text','Add tags','Add export to markdown','Improve keyboard shortcuts','Add settings page') 30
  $studio = New-Demo 'studio' @('Start the studio site','Add the gallery','Add the booking form') 12
  $cv = New-Demo 'resume-site' @('Create the resume page', 'Add the skills section', 'Add contact details') 15
  # blog: a teammate published a commit that exists nowhere here
  $other = "$PD\blog-teammate"; Run-Git $PD @('clone', '-q', "$RD\sim-user\blog.git", $other); Run-Git $other @('config', 'user.name', 'Bob Carter'); Run-Git $other @('config', 'user.email', 'bob@example.com')
  Set-Content "$other\bob.txt" 'bob'; Run-Git $other @('add', '-A'); Run-Git $other @('commit', '-q', '-m', 'Add a comments section'); Run-Git $other @('push', '-q', 'origin', 'main')
  # resume-site: one commit that is only on this computer
  Set-Content "$cv\g.txt" 'new'; Run-Git $cv @('add', '-A'); Run-Git $cv @('commit', '-q', '-m', 'Add a projects section')
  # recent projects for the first picture
  ConvertTo-Json -InputObject @{ recent = @($pf, $blog, $cv) } | Set-Content $env:BACKD8_UI_STATE -Encoding utf8

  # ---- the real window
  . (Join-Path $root 'gui.ps1') -NoShow
  $f.Width = 800; $f.Height = 600; $f.WindowStartupLocation = 'Manual'; $f.Left = -32000; $f.Top = -32000; $f.ShowActivated = $false; $f.ShowInTaskbar = $false
  $f.Show()
  function Pump { 1..6 | ForEach-Object { DoEvents; Start-Sleep -Milliseconds 40 }; $f.UpdateLayout() }
  New-Item -ItemType Directory $ImgDir -Force | Out-Null
  $written = @()
  function Snap([string]$name) {
    Pump; $w = [int][math]::Ceiling($f.ActualWidth); $h = [int][math]::Ceiling($f.ActualHeight)
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($f)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $ImgDir "$name.png")); $enc.Save($fs); $fs.Close(); $script:written += "$name.png ($w x $h)"
  }
  $yes = { $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = "$($script:eWf.Facts.Url)"; Transport = 'local'; CanPush = $true; Advice = @(); Accounts = @('sim-user'); NeedsAccountChoice = $false; Problem = $null; AccountInUse = 'sim-user' }; $script:eWf.Facts.Access = 'Yes'; Update-EAccessLabel; Show-WfState }

  # 01 choose a folder (first run: the recent list)
  Reset-ELoaded; Fill-Recent; Show-WfState; Snap '01-choose-folder'
  # 02 changes: write what you changed
  Set-Content "$pf\about.html" '<h1>About me</h1>'; New-Item -ItemType Directory "$pf\styles" | Out-Null; Set-Content "$pf\styles\theme.css" 'body{}'; Set-Content "$pf\.env" 'MAIL_API_KEY=example'
  Open-Folder $pf -NoFetch -NoAccess; & $yes
  $nMsg.Text = 'Add the about page and theme styles'; Update-EUi; Snap '02-changes'
  # 03 ready to publish (committed here, not on GitHub yet)
  Remove-Item "$pf\.env" -Force; $nMsg.Text = 'Add the about page and theme styles'; [void](Do-ENewCommit); & $yes; Snap '03-ready-to-publish'
  # 06 published (complete)
  $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = "$RD\sim-user\portfolio.git"; Transport = 'local'; CanPush = $true; Advice = @(); Accounts = @(); NeedsAccountChoice = $false; Problem = $null }
  Run-Plan; if ($script:wizPage -ne 5) { Show-Finish @(@{ Id = 'publish'; Text = 'Send your commits to GitHub' }) }; Snap '06-published'
  # 04 edit history: several commits, two waiting edits
  Do-ELoad $pf -NoAccess -NoFetch; $script:eSub = 'edit'; Show-WfState
  $cs = @($script:eCommits); $c1 = $cs | Where-Object { $_.Subject -eq 'Fix typo on the about page' } | Select-Object -First 1; $c2 = $cs | Where-Object { $_.Subject -eq 'Add project cards' } | Select-Object -First 1
  Do-ESelect $c1.Sha; $eMsg.Text = 'Fix typo on the About page'; Do-EStage; Do-ESelect $c2.Sha; $ePick.Value = $c2.Date.AddDays(-9); Do-EStage
  $script:eFilling = $true; foreach ($it in $lbHist.Items) { $it.IsSelected = ($it.Tag -eq $c2.Sha) }; $script:eFilling = $false; Update-EUi
  try { $lbHist.ScrollIntoView(($lbHist.Items | Where-Object { $_.Tag -eq $c2.Sha } | Select-Object -First 1)) } catch { }
  Snap '04-edit-history'
  # 07 replace GitHub's old version (an edited commit was already published)
  Do-ESelect $c1.Sha; [void](Do-EApply); & $yes; Snap '07-needs-replace'
  # 05 dates: spread several commits
  Open-Folder $notes -NoAccess -NoFetch; & $yes; $script:eSub = 'edit'; Show-WfState
  $script:eSelShas = @(); $script:eFilling = $false
  $k = 0; foreach ($it in @($lbHist.Items)) { if ($k -lt 3 -and $it.Tag) { $it.IsSelected = $true; $k++ } }
  Do-ESelect; $mPick.Value = (Get-Date).AddDays(-40); Update-EMulti; Update-EUi; Snap '05-dates'
  $script:eSub = ''
  # extra: GitHub has someone else's work (NeedsSync) and sign-in
  Open-Folder $blog -NoAccess -NoFetch; Do-ELoad $blog -NoAccess -Fetch; & $yes; Snap '07b-needs-sync'
  Open-Folder $cv -NoAccess -NoFetch; $script:eWf.Facts.Access = 'NotSignedIn'
  $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'https://github.com/sim-user/resume-site.git'; Transport = 'https'; CanPush = $false; Advice = @('Press "Sign in to GitHub": your browser opens once and Windows remembers you.'); Accounts = @(); NeedsAccountChoice = $false; Problem = $null }
  Update-EAccessLabel; Show-WfState; Snap '08-sign-in'

  # hero: the "ready to publish" page on the violet-blue backdrop with a soft shadow
  $script:eSub = ''; Set-Content "$studio\gallery2.html" 'x'; Open-Folder $studio -NoAccess -NoFetch; $nMsg.Text = 'Add the hero image'; [void](Do-ENewCommit); & $yes
  Pump; $w = [int]$f.ActualWidth; $h = [int]$f.ActualHeight
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($f)
  $grid = New-Object Windows.Controls.Grid; $grid.Width = $w + 160; $grid.Height = $h + 140; $grid.Background = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#3A3A9C'))
  $img = New-Object Windows.Controls.Image; $img.Source = $rtb; $img.Width = $w; $img.Height = $h; $img.HorizontalAlignment = 'Center'; $img.VerticalAlignment = 'Center'
  [Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'NearestNeighbor')
  $sh = New-Object Windows.Media.Effects.DropShadowEffect; $sh.BlurRadius = 36; $sh.ShadowDepth = 12; $sh.Direction = 300; $sh.Opacity = 0.55; $sh.Color = [Windows.Media.Colors]::Black; $img.Effect = $sh
  $grid.Children.Add($img) | Out-Null; $grid.Measure((New-Object Windows.Size($grid.Width, $grid.Height))); $grid.Arrange((New-Object Windows.Rect(0, 0, $grid.Width, $grid.Height))); $grid.UpdateLayout()
  $hr = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$grid.Width, [int]$grid.Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $hr.Render($grid)
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($hr)); $fs = [IO.File]::Create((Join-Path $ImgDir 'hero.png')); $enc.Save($fs); $fs.Close(); $written += "hero.png ($([int]$grid.Width) x $([int]$grid.Height))"

  # the names README.md already uses
  foreach ($m in @(@('01-choose-folder', 'gui-main-on'), @('04-edit-history', 'gui-main-off'), @('02-changes', 'gui-editor'), @('07-needs-replace', 'gui-editor-diverged'), @('01-choose-folder', 'gui-welcome'), @('02-changes', 'gui-express'), @('03-ready-to-publish', 'gui-publish'))) { Copy-Item (Join-Path $ImgDir "$($m[0]).png") (Join-Path $ImgDir "$($m[1]).png") -Force; $written += "$($m[1]).png (copy of $($m[0]))" }
  $written
} finally {
  & subst.exe $drive /D 2>&1 | Out-Null
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}



