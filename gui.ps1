# backd8 interactive window. Launch via BackD8.exe or: powershell -STA -File gui.ps1
# -SelfTest builds the form and drives its handlers without showing it (used by tests\uat.ps1).
param([switch]$SelfTest)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. "$PSScriptRoot\lib.ps1"
[Windows.Forms.Application]::EnableVisualStyles()
$script:Confirm = -not $SelfTest

function Fail($ex) { if ($SelfTest) { throw $ex }; [void][Windows.Forms.MessageBox]::Show($ex.Exception.Message, 'backd8', 'OK', 'Warning') }
function Lbl($t, $x, $y, $w = 300) { $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.Location = "$x,$y"; $l.Size = "$w,20"; $l }
function Btn($t, $x, $y, $w, $h = 28) { $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.Location = "$x,$y"; $b.Size = "$w,$h"; $b }
function Picker($x, $y) {
  $p = New-Object Windows.Forms.DateTimePicker; $p.Format = 'Custom'; $p.CustomFormat = 'yyyy-MM-dd  HH:mm'
  $p.MaxDate = Get-Date; $p.Value = (Get-Date).AddYears(-1); $p.Location = "$x,$y"; $p.Size = '170,24'; $p
}

$f = New-Object Windows.Forms.Form
$f.Text = 'backd8 - backdate git commits'; $f.Size = '660,560'; $f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9)

# status banner
$banner = New-Object Windows.Forms.Label; $banner.Location = '12,12'; $banner.Size = '620,44'; $banner.TextAlign = 'MiddleLeft'
$banner.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold); $banner.Padding = '10,0,0,0'
$bInstall = Btn 'Install hook' 12 64 150; $bToggle = Btn 'Turn ON' 172 64 150

# default date
$g1 = New-Object Windows.Forms.GroupBox; $g1.Text = 'Default start date (repos not listed below)'; $g1.Location = '12,104'; $g1.Size = '620,64'
$pDef = Picker 14 26; $bDef = Btn 'Apply default' 196 24 120
$lDef = Lbl '' 330 28 280
$g1.Controls.AddRange(@($pDef, $bDef, $lDef))

# repos
$g2 = New-Object Windows.Forms.GroupBox; $g2.Text = 'Repositories (each has its own clock: start, then +1-6 h per commit)'; $g2.Location = '12,178'; $g2.Size = '620,290'
$lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.MultiSelect = $false
$lv.Location = '12,24'; $lv.Size = '596,180'
[void]$lv.Columns.Add('Repository', 300); [void]$lv.Columns.Add('Start', 140); [void]$lv.Columns.Add('Next commit dated', 140)
$pRepo = Picker 12 216; $bAdd = Btn 'Add repo...' 196 214 110; $bUpd = Btn 'Set date on selected' 312 214 150; $bRem = Btn 'Remove selected' 468 214 140
$hint = Lbl 'Pick a date, then Add a folder or update the selected row (resets its clock).' 12 252 596
$g2.Controls.AddRange(@($lv, $pRepo, $bAdd, $bUpd, $bRem, $hint))

$warn = Lbl 'While ON, EVERY commit on this PC (any repo, any app) is rewritten with these dates. Turn OFF for real work.' 12 478 620
$warn.ForeColor = 'DarkRed'
$f.Controls.AddRange(@($banner, $bInstall, $bToggle, $g1, $g2, $warn))

function Refresh {
  $s = Get-Status; $c = $s.Config
  if (-not $s.Installed) { $banner.Text = 'Hook NOT installed - nothing will be backdated'; $banner.BackColor = 'Gainsboro' }
  elseif ($s.Enabled)    { $banner.Text = 'Backdating is ON'; $banner.BackColor = 'LightSalmon' }
  else                   { $banner.Text = 'Hook installed, backdating is OFF'; $banner.BackColor = 'Honeydew' }
  $bInstall.Text = if ($s.Installed) { 'Uninstall hook' } else { 'Install hook' }
  $bToggle.Text = if ($s.Enabled) { 'Turn OFF' } else { 'Turn ON' }; $bToggle.Enabled = $s.Installed
  $lDef.Text = if ($c.default.start) { "Current: $(([datetime]$c.default.start).ToString('yyyy-MM-dd HH:mm'))" } else { 'Current: not set' }
  $lv.Items.Clear()
  foreach ($r in @($c.repos)) {
    $it = New-Object Windows.Forms.ListViewItem($r.path)
    [void]$it.SubItems.Add(([datetime]$r.start).ToString('yyyy-MM-dd HH:mm'))
    [void]$it.SubItems.Add($(if ($r.next) { ([datetime]$r.next).ToString('yyyy-MM-dd HH:mm') } else { '(next commit = start)' }))
    [void]$lv.Items.Add($it)
  }
}

function Do-Install {
  try {
    if ((Get-Status).Installed) { [void](Uninstall-Hooks) }
    else {
      try { Install-Hooks } catch {
        if ($script:Confirm -and $_.Exception.Message -like '*already set*' -and
            [Windows.Forms.MessageBox]::Show("$($_.Exception.Message)`n`nReplace it?", 'backd8', 'YesNo', 'Warning') -eq 'Yes') { Install-Hooks -Force }
        else { throw }
      }
    }
  } catch { Fail $_ }; Refresh
}
function Do-Toggle {
  try {
    $on = -not (Get-Status).Enabled
    if ($on -and $script:Confirm -and [Windows.Forms.MessageBox]::Show("Turn ON?`nEvery commit on this PC will be backdated until you turn it OFF.", 'backd8', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Enabled $on
  } catch { Fail $_ }; Refresh
}
function Do-Default { try { Set-StartDate '*' $pDef.Value } catch { Fail $_ }; Refresh }
function Do-Add([string]$path) {
  try {
    if (-not $path) { $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -ne 'OK') { return }; $path = $d.SelectedPath }
    Set-StartDate $path $pRepo.Value
  } catch { Fail $_ }; Refresh
}
function Do-Update { if ($lv.SelectedItems.Count) { try { Set-StartDate $lv.SelectedItems[0].Text $pRepo.Value } catch { Fail $_ }; Refresh } }
function Do-Remove { if ($lv.SelectedItems.Count) { try { Remove-Repo $lv.SelectedItems[0].Text } catch { Fail $_ }; Refresh } }

$bInstall.Add_Click({ Do-Install }); $bToggle.Add_Click({ Do-Toggle }); $bDef.Add_Click({ Do-Default })
$bAdd.Add_Click({ Do-Add }); $bUpd.Add_Click({ Do-Update }); $bRem.Add_Click({ Do-Remove })
$lv.Add_SelectedIndexChanged({ if ($lv.SelectedItems.Count) { $pRepo.Value = [datetime]$lv.SelectedItems[0].SubItems[1].Text } })

Refresh
if ($SelfTest) {
  # drive the same handlers the buttons call; uat.ps1 inspects the resulting config
  Do-Install; Do-Default; Do-Add $env:BACKD8_TEST_REPO; Do-Toggle
  $lv.Items[0].Selected = $true; Do-Update; Do-Toggle; Do-Remove; Do-Install
  "selftest-ok rows=$($lv.Items.Count)"; return
}
try { [void]$f.ShowDialog() } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'backd8 crashed') }
