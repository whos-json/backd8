# backd8 interactive window (WPF). Launch via BackD8.exe or: powershell -STA -File gui.ps1
# -SelfTest drives the handlers without showing anything (used by tests\uat.ps1); -NoShow builds the window and returns (screenshot harness).
# Keep this file ASCII (Windows PowerShell 5.1 reads BOM-less files as ANSI); icon glyphs are built with [char].
param([switch]$SelfTest, [switch]$NoShow)
# Last-resort error window (plain WPF, no styles needed): BackD8.exe hides the console, so a crash must never just vanish.
function Show-Fatal([string]$text) {
  try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    try { [IO.File]::AppendAllText((Join-Path ([IO.Path]::GetTempPath()) 'backd8-error.log'), "[$((Get-Date).ToString('s'))] $text`r`n") } catch {}
    $w = New-Object Windows.Window; $w.Title = 'backd8 - something went wrong'; $w.Width = 640; $w.SizeToContent = 'Height'; $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'; $w.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI'); $w.FontSize = 13
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '22'
    $h = New-Object Windows.Controls.TextBlock; $h.Text = 'Sorry - backd8 could not continue'; $h.FontSize = 19; $h.FontWeight = 'SemiBold'; $sp.Children.Add($h) | Out-Null
    $d = New-Object Windows.Controls.TextBlock; $d.Text = 'Your files and commits are safe: nothing is changed unless a button says so. Copy the details below if you want help.'; $d.TextWrapping = 'Wrap'; $d.Margin = '0,8,0,12'; $sp.Children.Add($d) | Out-Null
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $text; $tb.IsReadOnly = $true; $tb.Height = 170; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.TextWrapping = 'Wrap'; $sp.Children.Add($tb) | Out-Null
    $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.HorizontalAlignment = 'Right'; $r.Margin = '0,14,0,0'
    $cp = New-Object Windows.Controls.Button; $cp.Content = 'Copy details'; $cp.Padding = '16,6'; $cp.Margin = '0,0,8,0'; $ok = New-Object Windows.Controls.Button; $ok.Content = 'Close'; $ok.Padding = '16,6'; $ok.IsDefault = $true; $ok.IsCancel = $true
    $cp.Add_Click({ try { [Windows.Clipboard]::SetText($tb.Text) } catch {}; $cp.Content = 'Copied' }.GetNewClosure()); $ok.Add_Click({ $w.Close() }.GetNewClosure())
    $r.Children.Add($cp) | Out-Null; $r.Children.Add($ok) | Out-Null; $sp.Children.Add($r) | Out-Null; $w.Content = $sp; [void]$w.ShowDialog()
  } catch { }
}
if (-not ($SelfTest -or $NoShow)) { trap { Show-Fatal "$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"; exit 1 } }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
. "$PSScriptRoot\lib.ps1"
$script:Confirm = -not ($SelfTest -or $NoShow)
$script:AskCapture = $null; $script:ActiveOwner = $null

#region theme, resources, glyphs
function Get-IsDark {
  if ($env:BACKD8_THEME) { return ($env:BACKD8_THEME -eq 'dark') }
  try { return ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme -eq 0) } catch { return $false }
}
$script:Light = @{
  Bg = '#F3F3F3'; Card = '#FFFFFF'; CardBorder = '#E1E1E1'; Text = '#1B1B1B'; Muted = '#575757'; Accent = '#005FB8'; AccentHover = '#0F6CBD'; AccentPressed = '#004A93'; OnAccent = '#FFFFFF'
  BtnBg = '#FFFFFF'; BtnBorder = '#BDBDBD'; BtnHover = '#F0F0F0'; BtnPressed = '#E4E4E4'; InputBg = '#FFFFFF'; InputBorder = '#9A9A9A'; SelBg = '#E1EEFB'; SelBorder = '#9CC4EE'; SubtleHover = '#EAEAEA'
  OkBg = '#DFF6DD'; OkFg = '#0B5A0B'; WarnBg = '#FFF1C2'; WarnFg = '#5C3A00'; ErrBg = '#FDE7E9'; ErrFg = '#9F1F26'; InfoBg = '#E1EEFB'; InfoFg = '#0A3F78'; IdleBg = '#ECECEC'; IdleFg = '#3B3B3B'
  ScrollThumb = '#BDBDBD'; Danger = '#C42B1C'; DangerHover = '#AB2417'; DangerPressed = '#8F1D13'; Scrim = '#99000000'
}
$script:Dark = @{
  Bg = '#1C1C1C'; Card = '#292929'; CardBorder = '#3B3B3B'; Text = '#F5F5F5'; Muted = '#BDBDBD'; Accent = '#4CC2FF'; AccentHover = '#6BCDFF'; AccentPressed = '#3AA8E3'; OnAccent = '#00263D'
  BtnBg = '#363636'; BtnBorder = '#555555'; BtnHover = '#404040'; BtnPressed = '#2E2E2E'; InputBg = '#232323'; InputBorder = '#6A6A6A'; SelBg = '#1D3B55'; SelBorder = '#3D7FB5'; SubtleHover = '#383838'
  OkBg = '#0F3D1A'; OkFg = '#A6E8B0'; WarnBg = '#4A3A00'; WarnFg = '#FFDD7A'; ErrBg = '#4D1D21'; ErrFg = '#FFA6AC'; InfoBg = '#17344D'; InfoFg = '#A5D6FF'; IdleBg = '#3A3A3A'; IdleFg = '#E8E8E8'
  ScrollThumb = '#6E6E6E'; Danger = '#D13438'; DangerHover = '#E04A4E'; DangerPressed = '#B72A2E'; Scrim = '#B3000000'
}
function Hex([string]$h) { [Windows.Media.ColorConverter]::ConvertFromString($h) }
function Btn-Template([string]$bg, [string]$fg, [string]$bd, [string]$hover, [string]$pressed, [string]$radius = '8') {
@"
<Setter Property="Foreground" Value="{DynamicResource $fg}"/><Setter Property="Background" Value="{DynamicResource $bg}"/><Setter Property="BorderBrush" Value="{DynamicResource $bd}"/>
<Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="16,9"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Margin" Value="0,0,8,0"/>
<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
 <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="$radius" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True" TextElement.Foreground="{TemplateBinding Foreground}"/></Border>
 <ControlTemplate.Triggers>
  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource $hover}"/></Trigger>
  <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource $pressed}"/></Trigger>
  <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Text}"/><Setter TargetName="bd" Property="BorderThickness" Value="2"/></Trigger>
  <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.42"/></Trigger>
 </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
"@
}
$script:ResXaml = @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style x:Key="Btn" TargetType="Button">$(Btn-Template 'BtnBg' 'Text' 'BtnBorder' 'BtnHover' 'BtnPressed')</Style>
 <Style x:Key="PrimaryBtn" TargetType="Button">$(Btn-Template 'Accent' 'OnAccent' 'Accent' 'AccentHover' 'AccentPressed')</Style>
 <Style x:Key="DangerBtn" TargetType="Button">$(Btn-Template 'Danger' 'OnAccent' 'Danger' 'DangerHover' 'DangerPressed')</Style>
 <Style x:Key="GhostBtn" TargetType="Button">$(Btn-Template 'Card' 'Accent' 'Card' 'SubtleHover' 'BtnPressed')</Style>
 <Style x:Key="ChipBtn" TargetType="Button">$(Btn-Template 'BtnBg' 'Text' 'BtnBorder' 'BtnHover' 'BtnPressed' '15')</Style>
 <Style x:Key="ChipOnBtn" TargetType="Button">$(Btn-Template 'SelBg' 'Accent' 'SelBorder' 'SelBg' 'SelBg' '15')</Style>
 <Style x:Key="CardStyle" TargetType="Border"><Setter Property="Background" Value="{DynamicResource Card}"/><Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="12"/><Setter Property="Padding" Value="20"/></Style>
 <Style x:Key="Glyph" TargetType="TextBlock"><Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol"/><Setter Property="FontSize" Value="18"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
 <Style TargetType="TextBox"><Setter Property="Background" Value="{DynamicResource InputBg}"/><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,8"/>
  <Setter Property="CaretBrush" Value="{DynamicResource Text}"/><Setter Property="SelectionBrush" Value="{DynamicResource Accent}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
   <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" SnapsToDevicePixels="True">
    <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" Focusable="False" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="BorderThickness" Value="2"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
   <StackPanel Orientation="Horizontal" Background="Transparent">
    <Border x:Name="box" Width="20" Height="20" CornerRadius="5" BorderThickness="1.5" BorderBrush="{DynamicResource Muted}" Background="Transparent" VerticalAlignment="Top" Margin="0,1,10,0">
     <Path x:Name="tick" Data="M4,10 L8,14 L16,5" Stroke="{DynamicResource OnAccent}" StrokeThickness="2.2" Visibility="Collapsed" Stretch="Uniform" Margin="3"/></Border>
    <ContentPresenter VerticalAlignment="Center" RecognizesAccessKey="True"/></StackPanel>
   <ControlTemplate.Triggers>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="box" Property="Background" Value="{DynamicResource Accent}"/><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="tick" Property="Visibility" Value="Visible"/></Trigger>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
    <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="box" Property="BorderThickness" Value="3"/><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style x:Key="RowItem" TargetType="ListBoxItem"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
   <Border x:Name="bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="7" Padding="8,7" Margin="0,1">
    <ContentPresenter/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource SubtleHover}"/></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource SelBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource SelBorder}"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ToolTip"><Setter Property="Background" Value="{DynamicResource Card}"/><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/><Setter Property="Padding" Value="10,6"/><Setter Property="MaxWidth" Value="420"/>
  <Setter Property="ContentTemplate"><Setter.Value><DataTemplate><TextBlock Text="{Binding}" TextWrapping="Wrap"/></DataTemplate></Setter.Value></Setter></Style>
 <Style x:Key="ThumbStyle" TargetType="Thumb"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Thumb"><Border x:Name="tb" Background="{DynamicResource ScrollThumb}" CornerRadius="5" Margin="2"/>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="tb" Property="Background" Value="{DynamicResource Muted}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ScrollBar"><Setter Property="Background" Value="Transparent"/><Setter Property="Width" Value="13"/><Setter Property="MinWidth" Value="13"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="True">
    <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
    <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
    <Track.Thumb><Thumb Style="{StaticResource ThumbStyle}"/></Track.Thumb></Track></Grid></ControlTemplate></Setter.Value></Setter>
  <Style.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="MinWidth" Value="0"/><Setter Property="Height" Value="13"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="False">
    <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
    <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
    <Track.Thumb><Thumb Style="{StaticResource ThumbStyle}"/></Track.Thumb></Track></Grid></ControlTemplate></Setter.Value></Setter></Trigger></Style.Triggers></Style>
 <Style TargetType="ListBox"><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBox"><Border Background="{TemplateBinding Background}"><ScrollViewer Focusable="False" Padding="{TemplateBinding Padding}" HorizontalScrollBarVisibility="{TemplateBinding ScrollViewer.HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding ScrollViewer.VerticalScrollBarVisibility}"><ItemsPresenter/></ScrollViewer></Border></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ScrollViewer"><Setter Property="Background" Value="Transparent"/></Style>
 <Style TargetType="Hyperlink"><Setter Property="Foreground" Value="{DynamicResource Accent}"/></Style>
</ResourceDictionary>
"@
$script:Res = [Windows.Markup.XamlReader]::Parse($script:ResXaml)
function Apply-Theme([bool]$dark) {
  $p = if ($dark) { $script:Dark } else { $script:Light }
  foreach ($k in $p.Keys) { $br = New-Object Windows.Media.SolidColorBrush((Hex $p[$k])); $script:Res[$k] = $br.psobject.BaseObject }
  $script:IsDark = $dark
}
Apply-Theme (Get-IsDark)
if (-not [Windows.Application]::Current) { $script:App = New-Object Windows.Application; $script:App.ShutdownMode = 'OnMainWindowClose' } else { $script:App = [Windows.Application]::Current }
$script:App.Resources.MergedDictionaries.Add($script:Res)

# icon font: Segoe Fluent Icons (Win11) > Segoe MDL2 Assets (Win10); plain text fallback otherwise
$fonts = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { $_.Source })
$script:HasIcons = [bool]($fonts -contains 'Segoe Fluent Icons' -or $fonts -contains 'Segoe MDL2 Assets')
function IcoC([int]$code, [string]$fallback) { if ($script:HasIcons) { [string][char]$code } else { $fallback } }
$script:I = @{
  Check = IcoC 0xE73E ([string][char]0x2714); Warn = IcoC 0xE7BA ([string][char]0x26A0); Err = IcoC 0xEA39 ([string][char]0x2716); Info = IcoC 0xE946 'i'; Folder = IcoC 0xE8B7 'F'
  Edit = IcoC 0xE70F ([string][char]0x270E); Add = IcoC 0xE710 '+'; Cloud = IcoC 0xE753 'C'; Upload = IcoC 0xE898 '^'; Undo = IcoC 0xE7A7 '<'; Calendar = IcoC 0xE787 'D'; Search = IcoC 0xE721 'S'
  Settings = IcoC 0xE713 'G'; Help = IcoC 0xE897 '?'; Lock = IcoC 0xE72E 'L'; Circle = IcoC 0xEA3A ([string][char]0x25CB); Sync = IcoC 0xE895 'R'; Clock = IcoC 0xE121 'T'; Link = IcoC 0xE71B '@'
}
$script:G = @{ Dot = [string][char]0x00B7; Dash = [string][char]0x2013; Ell = [string][char]0x2026; Up = [string][char]0x25B2; Down = [string][char]0x25BC; Arrow = [string][char]0x2192; Edit = [string][char]0x270E; Ok = [string][char]0x2714; Warn = [string][char]0x26A0; Err = [string][char]0x2716; Off = [string][char]0x25CB; Info = [string][char]0x2139 }
#endregion

#region helpers
function Plural([int]$n, [string]$one, [string]$many) { if ($n -eq 1) { "$n $one" } else { "$n $many" } }
function Br([string]$key) { $script:Res[$key] }
function SetRes($el, $prop, [string]$key) { $el.SetResourceReference($prop, $key) }
function Set-Kind($b, [string]$kind) { $b.Style = $script:Res[$(switch ($kind) { 'primary' { 'PrimaryBtn' } 'danger' { 'DangerBtn' } 'ghost' { 'GhostBtn' } default { 'Btn' } })] }   # NB: never write .Tag here - the dialogs keep their button index in it
function New-Tb([string]$text, [double]$size = 13, [string]$fg = 'Text', [string]$weight = 'Normal', [bool]$wrap = $true) {
  $t = New-Object Windows.Controls.TextBlock; $t.Text = $text; $t.FontSize = $size; $t.FontWeight = $weight; if ($wrap) { $t.TextWrapping = 'Wrap' }
  SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) $fg; $t
}
function New-Glyph([string]$g, [double]$size = 18, [string]$fg = 'Text') { $t = New-Object Windows.Controls.TextBlock; $t.Style = $script:Res['Glyph']; $t.Text = $g; $t.FontSize = $size; SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) $fg; $t }
function New-Button([string]$text, [string]$kind = 'normal', [double]$minW = 0) { $b = New-Object Windows.Controls.Button; $b.Content = $text; Set-Kind $b $kind; if ($minW) { $b.MinWidth = $minW }; $b }
function Set-Chip($border, $icon, $text, [string]$kind, [string]$glyph, [string]$label) {
  $k = switch ($kind) { 'ok' { 'Ok' } 'warn' { 'Warn' } 'danger' { 'Err' } 'info' { 'Info' } default { 'Idle' } }
  SetRes $border ([Windows.Controls.Border]::BackgroundProperty) "${k}Bg"; SetRes $icon ([Windows.Controls.TextBlock]::ForegroundProperty) "${k}Fg"; SetRes $text ([Windows.Controls.TextBlock]::ForegroundProperty) "${k}Fg"
  $icon.Text = $glyph; $text.Text = $label
}
function DoEvents {
  $fr = New-Object Windows.Threading.DispatcherFrame
  $cb = [Windows.Threading.DispatcherOperationCallback]{ param($o) $o.Continue = $false; $null }
  [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, $cb, $fr)
  [Windows.Threading.Dispatcher]::PushFrame($fr)
}
function Acc($c, [string]$name, [string]$help = '') { [Windows.Automation.AutomationProperties]::SetName($c, $name); if ($help) { [Windows.Automation.AutomationProperties]::SetHelpText($c, $help) } }
function Tip($c, [string]$text) { $c.ToolTip = $text; [Windows.Controls.ToolTipService]::SetShowOnDisabled($c, $true) }

# date + time field with calendar popup. .Value reads/writes a [datetime] (seconds are kept while the minute text is untouched)
function New-Dt([datetime]$initial = (Get-Date)) {
  $o = [pscustomobject]@{ Panel = $null; Date = $null; Time = $null; Last = [datetime]::MinValue }
  $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
  $d = New-Object Windows.Controls.TextBox; $d.Width = 124; $d.Margin = '0,0,8,0'; $d.MaxLength = 10; Acc $d 'Date (year-month-day)'
  $t = New-Object Windows.Controls.TextBox; $t.Width = 76; $t.Margin = '0,0,8,0'; $t.MaxLength = 5; Acc $t 'Time (hours:minutes)'
  $cb = New-Button $script:I.Calendar 'normal'; $cb.Padding = '12,8'; $cb.Margin = '0'; $cb.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol'); Acc $cb 'Pick a date from a calendar'
  $pop = New-Object Windows.Controls.Primitives.Popup; $pop.PlacementTarget = $cb; $pop.Placement = 'Bottom'; $pop.StaysOpen = $false
  $cal = New-Object Windows.Controls.Calendar; $cal.DisplayDateEnd = (Get-Date).Date
  $bd = New-Object Windows.Controls.Border; $bd.Background = [Windows.Media.Brushes]::White; $bd.Padding = '6'; $bd.BorderBrush = [Windows.Media.Brushes]::Gray; $bd.BorderThickness = '1'; $bd.Child = $cal; $pop.Child = $bd
  $cb.Add_Click({ $pop.IsOpen = $true }.GetNewClosure())
  $cal.Add_SelectedDatesChanged({ if ($cal.SelectedDate) { $d.Text = $cal.SelectedDate.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $pop.IsOpen = $false } }.GetNewClosure())
  $sp.Children.Add($d) | Out-Null; $sp.Children.Add($t) | Out-Null; $sp.Children.Add($cb) | Out-Null
  $o.Panel = $sp; $o.Date = $d; $o.Time = $t
  $o | Add-Member -MemberType ScriptProperty -Name Value -Value {
      $dt = [datetime]::MinValue
      if ([datetime]::TryParseExact(("$($this.Date.Text.Trim()) $($this.Time.Text.Trim())"), 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$dt)) {
        $l = $this.Last; if ($l -ne [datetime]::MinValue) { $lm = $l.AddSeconds(-$l.Second).AddMilliseconds(-$l.Millisecond); if ([math]::Abs(($dt - $lm).TotalSeconds) -lt 1) { return $l } }
        return $dt
      }
      [datetime]::MinValue
    } -SecondValue {
      param($v) $v = [datetime]$v; $this.Last = $v
      $this.Date.Text = $v.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $this.Time.Text = $v.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
  $o | Add-Member -MemberType ScriptProperty -Name Valid -Value { [bool]($this.Value -ne [datetime]::MinValue) }
  $o.Value = $initial
  $o
}
# friendly dialogs: explicit verbs, safe default, counts and names. Returns the index of the clicked button (Esc = $Cancel).
function Ask([string]$Title, [string]$Heading, [string]$Body = '', [string[]]$Buttons = @('OK'), [int]$Default = 0, [string]$Icon = 'info', [string]$Details = '', [int]$Cancel = -1, [int]$Danger = -1, [string]$CheckText = '') {
  if ($Cancel -lt 0) { $Cancel = $Buttons.Count - 1 }
  $w = New-Object Windows.Window; $w.Title = $Title; $w.SizeToContent = 'Height'; $w.Width = 560; $w.ResizeMode = 'NoResize'; $w.WindowStartupLocation = 'CenterOwner'; $w.ShowInTaskbar = $false
  $w.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI'); $w.FontSize = 13; $w.UseLayoutRounding = $true
  $w.Resources.MergedDictionaries.Add($script:Res); SetRes $w ([Windows.Window]::BackgroundProperty) 'Bg'; SetRes $w ([Windows.Window]::ForegroundProperty) 'Text'
  if ($script:ActiveOwner -and $script:ActiveOwner.IsVisible) { $w.Owner = $script:ActiveOwner }
  $root = New-Object Windows.Controls.Grid; $root.Margin = '26,24,26,20'
  $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = 'Auto'; $root.ColumnDefinitions.Add($cd); $cd2 = New-Object Windows.Controls.ColumnDefinition; $root.ColumnDefinitions.Add($cd2)
  $ic = New-Object Windows.Controls.Border; $ic.Width = 44; $ic.Height = 44; $ic.CornerRadius = '22'; $ic.VerticalAlignment = 'Top'; $ic.Margin = '0,0,18,0'
  $it = New-Glyph '' 20; $it.HorizontalAlignment = 'Center'
  $kind = switch ($Icon) { 'error' { 'danger' } 'warn' { 'warn' } 'question' { 'info' } default { 'info' } }
  $gl = switch ($Icon) { 'error' { $script:I.Err } 'warn' { $script:I.Warn } 'question' { '?' } default { $script:I.Info } }
  $dummy = New-Object Windows.Controls.TextBlock; Set-Chip $ic $it $dummy $kind $gl ''; $ic.Child = $it
  [Windows.Controls.Grid]::SetColumn($ic, 0); $root.Children.Add($ic) | Out-Null
  $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
  $h = New-Tb $Heading 19 'Text' 'SemiBold'; $h.Margin = '0,0,0,10'; $sp.Children.Add($h) | Out-Null
  if ($Body) { $b = New-Tb $Body 13 'Text'; $b.LineHeight = 20; $sp.Children.Add($b) | Out-Null }
  if ($Details) { $tb = New-Object Windows.Controls.TextBox; $tb.IsReadOnly = $true; $tb.Text = $Details; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.Height = 110; $tb.Margin = '0,14,0,0'; $tb.TextWrapping = 'NoWrap'; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'; Acc $tb 'Details'; $sp.Children.Add($tb) | Out-Null }
  $chk = $null
  if ($CheckText) { $chk = New-Object Windows.Controls.CheckBox; $chk.Content = $CheckText; $chk.Margin = '0,16,0,0'; $chk.FontWeight = 'SemiBold'; $sp.Children.Add($chk) | Out-Null }
  $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,22,0,0'
  $script:askRes = $Cancel; $btns = @()
  for ($i = 0; $i -lt $Buttons.Count; $i++) {
    $bt = New-Button $Buttons[$i] 'normal' 100; $bt.Margin = '8,0,0,0'; $bt.Tag = $i; $bt.IsDefault = ($i -eq $Default); $bt.IsCancel = ($i -eq $Cancel)
    $row.Children.Add($bt) | Out-Null; $btns += $bt
  }
  foreach ($bt in $btns) { $idx = [int]$bt.Tag; $bt.Add_Click([Windows.RoutedEventHandler]{ param($s, $e) $script:askRes = [int]$s.Tag; $script:askWin.DialogResult = $true }) }
  $script:askWin = $w
  if ($Danger -ge 0) { Set-Kind $btns[$Danger] 'danger'; if ($chk) { $btns[$Danger].IsEnabled = $false; $script:askDanger = $btns[$Danger]; $chk.Add_Click({ $script:askDanger.IsEnabled = [bool]$this.IsChecked }) } }
  elseif ($Default -ne $Cancel) { Set-Kind $btns[$Default] 'primary' }
  $sp.Children.Add($row) | Out-Null; $root.Children.Add($sp) | Out-Null; $wrap = New-Object Windows.Controls.Grid; $wrap.Children.Add($root) | Out-Null; $w.Content = $wrap
  $w.Add_ContentRendered({ try { $btns | Where-Object { $_.IsDefault } | Select-Object -First 1 | ForEach-Object { [void]$_.Focus() } } catch {} })
  if ($script:AskCapture) { $r = & $script:AskCapture $w $Default $Cancel; return $r }
  $script:askRes = $Cancel
  [void]$w.ShowDialog()
  $script:askRes
}
# turns raw git/backd8 messages into: what happened + what to do next. The raw text stays visible under "Details".
function Explain-Error([string]$m) {
  $h = 'Something went wrong'; $n = 'The details below say what git answered. If it is unclear, copy them into a search engine or an issue.'
  switch -Wildcard ($m) {
    'Not a git repository*' { $h = "That folder isn't a git project"; $n = 'Choose the folder that contains your project, or any folder inside it.' }
    'Folder not found*' { $h = "That folder doesn't exist"; $n = 'Check the spelling, or use Browse to pick it. It may have been moved or deleted.' }
    'HEAD is detached*' { $h = "You're not on a branch right now"; $n = 'Switch to a branch first (for example: git switch main), then open the folder again.' }
    'A rebase, merge or cherry-pick*' { $h = 'Git is in the middle of another operation'; $n = 'Finish or abort the rebase / merge / cherry-pick in your usual git tool, then try again.' }
    'Start date must be in the past*' { $h = 'The date is in the future'; $n = 'backd8 can only give commits dates that have already passed. Pick an earlier date.' }
    'Date must be in the past*' { $h = 'The date is in the future'; $n = 'Pick a date and time that have already passed.' }
    'Timed out waiting*' { $h = 'Another backd8 window is busy'; $n = 'Wait a few seconds and try again.' }
    'git push failed*' { $h = 'GitHub did not accept the upload'; $n = 'Read the message below. Common causes: no internet, a protected branch, or someone uploaded newer commits first.' }
    'Git is not installed*' { $h = 'Git is not installed on this PC'; $n = 'Install Git for Windows (winget install --id Git.Git -e), then restart backd8.' }
    'Rewriting*failed*' { $h = 'Could not change the commits'; $n = 'Nothing was changed. Details below. For a shallow clone run: git fetch --unshallow' }
    'Cancelled*' { $h = 'Cancelled'; $n = 'The operation was stopped. Nothing was changed on GitHub.' }
    'Nothing to commit*' { $h = 'There is nothing to commit'; $n = 'No files have changed since the last commit.' }
    'Choose at least one file*' { $h = 'Pick at least one file'; $n = 'Tick the files that belong in this commit.' }
    'Write a commit message*' { $h = 'Write a message first'; $n = 'Describe in a few words what you changed.' }
    'Git does not know who you are*' { $h = 'Git needs your name and email'; $n = 'Fill in "Before we start" at the top of the window, or run the two git config commands shown below.' }
  }
  @{ Heading = $h; Next = $n }
}
function Show-Crash($err) {
  $m = if ($err -is [Management.Automation.ErrorRecord]) { "$($err.Exception.Message)`r`n$($err.ScriptStackTrace)" } else { "$err" }
  try { [IO.File]::AppendAllText((Join-Path ([IO.Path]::GetTempPath()) 'backd8-error.log'), "[$((Get-Date).ToString('s'))] $m`r`n") } catch {}
  if (-not $script:Confirm) { throw $err }
  try {
    $w = New-Object Windows.Window; $w.Title = 'backd8 - something went wrong'; $w.Width = 620; $w.SizeToContent = 'Height'; $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Resources.MergedDictionaries.Add($script:Res); SetRes $w ([Windows.Window]::BackgroundProperty) 'Bg'; $w.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI'); $w.FontSize = 13
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '24'
    $sp.Children.Add((New-Tb 'Sorry - backd8 hit a problem' 19 'Text' 'SemiBold')) | Out-Null
    $d = New-Tb 'Your files and commits are safe: nothing is changed unless a button says so. You can copy the details below and send them along.' 13 'Muted'; $d.Margin = '0,8,0,12'; $sp.Children.Add($d) | Out-Null
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $m; $tb.IsReadOnly = $true; $tb.Height = 160; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.TextWrapping = 'Wrap'; $sp.Children.Add($tb) | Out-Null
    $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.HorizontalAlignment = 'Right'; $r.Margin = '0,16,0,0'
    $cp = New-Button 'Copy details' 'normal' 120; $ok = New-Button 'Close' 'primary' 100; $ok.Margin = '8,0,0,0'; $ok.IsDefault = $true; $ok.IsCancel = $true
    $cp.Add_Click({ try { [Windows.Clipboard]::SetText($tb.Text) } catch {}; $this.Content = 'Copied' }.GetNewClosure()); $ok.Add_Click({ $w.Close() }.GetNewClosure())
    $r.Children.Add($cp) | Out-Null; $r.Children.Add($ok) | Out-Null; $sp.Children.Add($r) | Out-Null; $w.Content = $sp; [void]$w.ShowDialog()
  } catch { }
}
function Fail($ex) {
  $m = if ($ex -is [Management.Automation.ErrorRecord]) { $ex.Exception.Message } else { "$ex" }
  if (-not $script:Confirm) { throw $ex }
  $x = Explain-Error $m
  [void](Ask 'backd8' $x.Heading $x.Next @('OK') 0 'error' $m)
}

# persisted UI state (window size, last folder, notices) next to config.json - never in git
function Get-UiPath { if ($env:BACKD8_UI_STATE) { $env:BACKD8_UI_STATE } else { Join-Path (Split-Path (Get-CfgPath)) 'ui.json' } }
function Load-Ui { try { $x = Get-Content (Get-UiPath) -Raw -ErrorAction Stop | ConvertFrom-Json; if ($x) { return $x } } catch {}; [pscustomobject]@{} }
function Set-UiValue([string]$k, $v) { try { $u = Load-Ui; $h = @{}; foreach ($p in $u.PSObject.Properties) { $h[$p.Name] = $p.Value }; $h[$k] = $v; ConvertTo-Json -InputObject $h -Depth 4 | Set-Content (Get-UiPath) -Encoding utf8 } catch {} }
function Save-Ui($win, [string]$key, [string]$lastRepo = '') {
  try {
    $u = Load-Ui; $h = @{}; foreach ($p in $u.PSObject.Properties) { $h[$p.Name] = $p.Value }
    if ($win) { $b = $win.RestoreBounds; $h[$key] = @{ x = $b.X; y = $b.Y; w = $b.Width; h = $b.Height; max = ($win.WindowState -eq 'Maximized') } }
    if ($lastRepo) { $h['lastRepo'] = $lastRepo; $rec = @($lastRepo) + @($h['recent'] | Where-Object { $_ -and $_ -ne $lastRepo }); $h['recent'] = @($rec | Select-Object -First 8) }
    ConvertTo-Json -InputObject $h -Depth 4 | Set-Content (Get-UiPath) -Encoding utf8
  } catch {}
}
function Restore-Bounds($win, [string]$key) {
  try {
    $st = (Load-Ui).$key
    if ($st) {
      $vl = [Windows.SystemParameters]::VirtualScreenLeft; $vt = [Windows.SystemParameters]::VirtualScreenTop; $vw = [Windows.SystemParameters]::VirtualScreenWidth; $vh = [Windows.SystemParameters]::VirtualScreenHeight
      if ($st.x + 100 -lt ($vl + $vw) -and $st.y + 60 -lt ($vt + $vh) -and $st.x + $st.w -gt $vl + 100 -and $st.y -gt $vt - 10 -and $st.w -ge $win.MinWidth -and $st.h -ge $win.MinHeight) {
        $win.WindowStartupLocation = 'Manual'; $win.Left = $st.x; $win.Top = $st.y; $win.Width = $st.w; $win.Height = $st.h; if ($st.max) { $win.WindowState = 'Maximized' }
      }
    }
  } catch {}
  $wa = [Windows.SystemParameters]::WorkArea
  if ($win.Height -gt $wa.Height - 20) { $win.Height = $wa.Height - 20 }; if ($win.Width -gt $wa.Width - 20) { $win.Width = $wa.Width - 20 }
}
#endregion


#region the one window (XAML): steps bar, folder, history + editor, publish bar
$script:MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="win" Title="backd8 - fix your commits and publish to GitHub" Width="1140" Height="1020" MinWidth="960" MinHeight="620"
        Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        AllowDrop="True" UseLayoutRounding="True" SnapsToDevicePixels="True" WindowStartupLocation="CenterScreen">
 <Grid>
  <ScrollViewer x:Name="pageScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
  <Grid x:Name="scrollHost" MinHeight="940" Height="{Binding ViewportHeight, ElementName=pageScroll}">
  <Grid x:Name="rootGrid" Margin="28,16,28,16">
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

   <!-- header -->
   <Grid Grid.Row="0" Margin="0,0,0,12">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Border Width="46" Height="46" CornerRadius="13" Background="{DynamicResource Accent}" Margin="0,0,16,0"><TextBlock Text="b8" Foreground="{DynamicResource OnAccent}" FontSize="21" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
     <TextBlock Text="backd8" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Fix the dates and messages of your commits, then publish to GitHub." Foreground="{DynamicResource Muted}" Margin="0,1,0,0"/></StackPanel>
    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
     <Button x:Name="btnHelp" Content="_Help" Style="{DynamicResource GhostBtn}"/><Button x:Name="btnAdv" Content="A_dvanced" Style="{DynamicResource GhostBtn}" Margin="0"/></StackPanel>
   </Grid>

   <!-- the three steps -->
   <UniformGrid Grid.Row="1" Columns="3" Margin="0,0,0,10">
    <Border x:Name="st1" CornerRadius="12" BorderThickness="1.5" Padding="14,10" Margin="0,0,10,0"><StackPanel Orientation="Horizontal">
      <Border x:Name="st1d" Width="32" Height="32" CornerRadius="16"><TextBlock x:Name="st1n" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
      <StackPanel Margin="12,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="st1t" Text="Choose your project" FontWeight="SemiBold" FontSize="14"/><TextBlock x:Name="st1s" FontSize="12"/></StackPanel></StackPanel></Border>
    <Border x:Name="st2" CornerRadius="12" BorderThickness="1.5" Padding="14,10" Margin="0,0,10,0"><StackPanel Orientation="Horizontal">
      <Border x:Name="st2d" Width="32" Height="32" CornerRadius="16"><TextBlock x:Name="st2n" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
      <StackPanel Margin="12,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="st2t" Text="Change dates and messages" FontWeight="SemiBold" FontSize="14"/><TextBlock x:Name="st2s" FontSize="12"/></StackPanel></StackPanel></Border>
    <Border x:Name="st3" CornerRadius="12" BorderThickness="1.5" Padding="14,10" Margin="0"><StackPanel Orientation="Horizontal">
      <Border x:Name="st3d" Width="32" Height="32" CornerRadius="16"><TextBlock x:Name="st3n" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
      <StackPanel Margin="12,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="st3t" Text="Publish to GitHub" FontWeight="SemiBold" FontSize="14"/><TextBlock x:Name="st3s" FontSize="12"/></StackPanel></StackPanel></Border>
   </UniformGrid>

   <!-- folder -->
   <Border Grid.Row="2" Style="{DynamicResource CardStyle}" Padding="16,9" Margin="0,0,0,10">
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock x:Name="icoFolder" Style="{DynamicResource Glyph}" FontSize="22" Foreground="{DynamicResource Accent}" Margin="0,0,14,0"/>
     <Grid Grid.Column="1" Margin="0,0,12,0"><TextBox x:Name="tbPath" FontSize="14.5"/><TextBlock x:Name="phPath" Text="Paste the path of your project folder, or drop the folder on this window" Foreground="{DynamicResource Muted}" FontSize="14" IsHitTestVisible="False" Margin="12,0,0,0" VerticalAlignment="Center"/></Grid>
     <Button x:Name="btnRecent" Grid.Column="2" Content="Recent" Style="{DynamicResource Btn}"/>
     <Button x:Name="btnBrowse" Grid.Column="3" Content="_Browse..." Style="{DynamicResource PrimaryBtn}" Margin="0" MinWidth="120"/></Grid></Border>

   <!-- banners are added here by code -->
   <StackPanel x:Name="spBan" Grid.Row="3"/>

   <!-- work area -->
   <Grid x:Name="gMain" Grid.Row="4" Margin="0,0,0,10">
    <Border x:Name="pEmpty" Style="{DynamicResource CardStyle}" Padding="40">
     <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="640">
      <Border Width="72" Height="72" CornerRadius="36" Background="{DynamicResource InfoBg}" HorizontalAlignment="Center" Margin="0,0,0,18"><TextBlock x:Name="icoEmpty" Style="{DynamicResource Glyph}" FontSize="32" Foreground="{DynamicResource InfoFg}" HorizontalAlignment="Center"/></Border>
      <TextBlock Text="Start by choosing your project folder" FontSize="26" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
      <TextBlock Text="Any folder works - even one that is not on GitHub yet. backd8 shows its history, lets you change dates and messages, and publishes the result." Foreground="{DynamicResource Muted}" FontSize="14.5" TextAlignment="Center" TextWrapping="Wrap" Margin="0,10,0,22" LineHeight="22"/>
      <Button x:Name="btnEmptyBrowse" Content="_Choose a folder..." Style="{DynamicResource PrimaryBtn}" FontSize="15" FontWeight="SemiBold" Padding="26,13" HorizontalAlignment="Center" Margin="0"/>
      <TextBlock Text="You can also drop a folder on this window. Nothing changes until you press a button, and every edit can be undone." Foreground="{DynamicResource Muted}" FontSize="12.5" TextAlignment="Center" TextWrapping="Wrap" Margin="0,16,0,0"/></StackPanel></Border>

    <Border x:Name="pPlain" Style="{DynamicResource CardStyle}" Padding="40" Visibility="Collapsed">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="660">
      <Border Width="72" Height="72" CornerRadius="36" Background="{DynamicResource WarnBg}" HorizontalAlignment="Center" Margin="0,0,0,16"><TextBlock x:Name="icoPlain" Style="{DynamicResource Glyph}" FontSize="32" Foreground="{DynamicResource WarnFg}" HorizontalAlignment="Center"/></Border>
      <TextBlock Text="This folder isn't a git project yet" FontSize="26" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
      <TextBlock x:Name="wpFolder" Foreground="{DynamicResource Muted}" HorizontalAlignment="Center" Margin="0,6,0,14" TextWrapping="Wrap" TextAlignment="Center"/>
      <TextBlock Text="backd8 can turn it into one in a second. That adds a hidden .git folder inside it; your files are not changed. Afterwards you can save commits with any date you like and publish them to GitHub." Foreground="{DynamicResource Text}" FontSize="14" TextWrapping="Wrap" LineHeight="22" Margin="0,0,0,18"/>
      <TextBlock Text="Where should it be published? (optional - you can do this later)" FontWeight="SemiBold" Margin="0,0,0,6"/>
      <TextBlock Text="Create an empty repository at github.com/new, then paste its address here." Foreground="{DynamicResource Muted}" Margin="0,0,0,8"/>
      <Grid><TextBox x:Name="tbInit" FontSize="14"/><TextBlock x:Name="phInit" Text="https://github.com/you/my-project.git" Foreground="{DynamicResource Muted}" FontSize="14" IsHitTestVisible="False" Margin="12,0,0,0" VerticalAlignment="Center"/></Grid>
      <TextBlock x:Name="wpErr" Foreground="{DynamicResource ErrFg}" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/>
      <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
       <Button x:Name="bInit" Content="_Turn this folder into a project" Style="{DynamicResource PrimaryBtn}" FontSize="14.5" FontWeight="SemiBold" Padding="22,12"/>
       <Button x:Name="bInitNew" Content="Open github.com/new" Style="{DynamicResource Btn}" Padding="18,12" Margin="0"/></StackPanel></StackPanel></ScrollViewer></Border>

    <Grid x:Name="pProject" Visibility="Collapsed">
     <Grid.ColumnDefinitions><ColumnDefinition Width="5*" MinWidth="360"/><ColumnDefinition Width="12"/><ColumnDefinition Width="6*" MinWidth="420"/></Grid.ColumnDefinitions>
     <!-- left: history -->
     <Border Style="{DynamicResource CardStyle}" Padding="18,16">
      <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
       <Grid Margin="0,0,0,10"><TextBlock Text="Your project history" FontSize="18" FontWeight="SemiBold"/><TextBlock x:Name="tHistCount" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource Muted}"/></Grid>
       <Grid Grid.Row="1" Margin="0,0,0,8"><TextBox x:Name="tbFind" Padding="34,8,10,8"/><TextBlock x:Name="icoFind" Style="{DynamicResource Glyph}" FontSize="14" Foreground="{DynamicResource Muted}" IsHitTestVisible="False" Margin="12,0,0,0" HorizontalAlignment="Left"/>
        <TextBlock x:Name="phFind" Text="Search by message, author, date or ID" Foreground="{DynamicResource Muted}" IsHitTestVisible="False" Margin="34,0,0,0" VerticalAlignment="Center"/></Grid>
       <Grid Grid.Row="2" Margin="8,0,30,4"><Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="142"/><ColumnDefinition Width="*"/><ColumnDefinition Width="72"/></Grid.ColumnDefinitions>
        <Button x:Name="hSortDate" Grid.Column="1" Content="When" Style="{DynamicResource GhostBtn}" Padding="0,2" HorizontalAlignment="Left" Margin="0" FontSize="12" FontWeight="SemiBold"/>
        <Button x:Name="hSortMsg" Grid.Column="2" Content="What you saved (message)" Style="{DynamicResource GhostBtn}" Padding="0,2" HorizontalAlignment="Left" Margin="0" FontSize="12" FontWeight="SemiBold"/>
        <Button x:Name="hSortId" Grid.Column="3" Content="ID" Style="{DynamicResource GhostBtn}" Padding="0,2" HorizontalAlignment="Left" Margin="0" FontSize="12" FontWeight="SemiBold"/></Grid>
       <Grid Grid.Row="3"><ListBox x:Name="lbHist" SelectionMode="Extended" BorderThickness="0" Background="Transparent" ScrollViewer.HorizontalScrollBarVisibility="Disabled" Foreground="{DynamicResource Text}"/>
        <TextBlock x:Name="tbHistEmpty" Foreground="{DynamicResource Muted}" TextAlignment="Center" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="20" Visibility="Collapsed"/></Grid>
      </Grid></Border>
     <GridSplitter Grid.Column="1" Width="12" HorizontalAlignment="Stretch" Background="Transparent" ShowsPreview="False"/>
     <!-- right: details -->
     <Border Grid.Column="2" Style="{DynamicResource CardStyle}" Padding="22,18">
      <Grid>
       <StackPanel x:Name="vNone" VerticalAlignment="Center" HorizontalAlignment="Center" MaxWidth="360"><TextBlock x:Name="icoNone" Style="{DynamicResource Glyph}" FontSize="34" Foreground="{DynamicResource Muted}" HorizontalAlignment="Center" Margin="0,0,0,12"/>
        <TextBlock Text="Click a commit on the left to change its message or date." Foreground="{DynamicResource Muted}" FontSize="14.5" TextAlignment="Center" TextWrapping="Wrap"/></StackPanel>

       <Grid x:Name="vNew" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*" MinHeight="90"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Save your new work as a commit" FontSize="20" FontWeight="SemiBold"/>
        <Grid Grid.Row="1" Margin="0,12,0,6"><TextBlock Text="Which changed files go into it?" FontWeight="SemiBold" VerticalAlignment="Center"/>
         <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><TextBlock x:Name="nCount" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="0,0,12,0"/><Button x:Name="nAll" Content="All" Style="{DynamicResource GhostBtn}" Padding="10,4" Margin="0,0,4,0"/><Button x:Name="nNone" Content="None" Style="{DynamicResource GhostBtn}" Padding="10,4" Margin="0"/></StackPanel></Grid>
        <Border Grid.Row="2" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="8" Margin="0,0,0,12"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="spFiles" Margin="10,8"/></ScrollViewer></Border>
        <TextBlock Grid.Row="3" Text="What did you change? (this becomes the commit message)" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <Grid Grid.Row="4" Margin="0,0,0,12"><TextBox x:Name="nMsg" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="72" VerticalContentAlignment="Top"/><TextBlock x:Name="phNMsg" Text="For example: Add the login page" Foreground="{DynamicResource Muted}" IsHitTestVisible="False" Margin="12,10,0,0"/></Grid>
        <StackPanel Grid.Row="5" Margin="0,0,0,6"><TextBlock Text="Date of this commit" FontWeight="SemiBold" Margin="0,0,0,6"/>
         <WrapPanel x:Name="spWhen"/><StackPanel x:Name="nDtHost" Margin="0,8,0,0"/></StackPanel>
        <Grid Grid.Row="6" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
         <TextBlock x:Name="nHint" Foreground="{DynamicResource Muted}" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
         <Button x:Name="nBtn" Grid.Column="1" Content="_Commit these files" Style="{DynamicResource Btn}" Margin="0"/></Grid></Grid>

       <Grid x:Name="vCommit" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*" MinHeight="90"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock x:Name="eSelHead" Text="Change this commit" FontSize="20" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock x:Name="eSelSub" Grid.Row="1" Foreground="{DynamicResource Muted}" Margin="0,2,0,12" TextWrapping="Wrap"/>
        <Grid Grid.Row="2" Margin="0,0,0,12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
         <TextBlock Text="Message (the first line is the title)" FontWeight="SemiBold" Margin="0,0,0,6"/><TextBox x:Name="eMsg" Grid.Row="1" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top" FontFamily="Consolas" FontSize="13.5"/></Grid>
        <StackPanel Grid.Row="3" Margin="0,0,0,6"><TextBlock Text="Date and time" FontWeight="SemiBold" Margin="0,0,0,6"/><StackPanel x:Name="ePickHost"/><TextBlock x:Name="eWarn" Foreground="{DynamicResource ErrFg}" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/></StackPanel>
        <TextBlock x:Name="eSaveState" Grid.Row="4" Foreground="{DynamicResource Muted}" TextWrapping="Wrap" Margin="0,6,0,10"/>
        <StackPanel Grid.Row="5" Orientation="Horizontal"><Button x:Name="eSave" Content="_Save change" Style="{DynamicResource Btn}"/><Button x:Name="eDisc" Content="_Revert this commit" Style="{DynamicResource Btn}"/></StackPanel></Grid>

       <StackPanel x:Name="vMulti" Visibility="Collapsed" VerticalAlignment="Top">
        <TextBlock x:Name="mHead" FontSize="20" FontWeight="SemiBold"/>
        <TextBlock Text="Give them new dates, oldest to newest, about 1 to 6 hours apart. Only the dates change - messages stay as they are." Foreground="{DynamicResource Muted}" TextWrapping="Wrap" Margin="0,6,0,16"/>
        <TextBlock Text="The oldest of them gets this date" FontWeight="SemiBold" Margin="0,0,0,6"/><StackPanel x:Name="mPickHost"/>
        <TextBlock x:Name="mPrev" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,12,0,16"/>
        <Button x:Name="mBtn" Content="Re-_date these commits" Style="{DynamicResource Btn}" HorizontalAlignment="Left" Margin="0"/></StackPanel>
      </Grid></Border>
    </Grid>
   </Grid>

   <!-- publish bar -->
   <Border x:Name="pubBar" Grid.Row="5" Style="{DynamicResource CardStyle}" Padding="18,12">
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <StackPanel VerticalAlignment="Center" Margin="0,0,24,0">
      <Border x:Name="pubChip" CornerRadius="15" Padding="12,5" HorizontalAlignment="Left"><StackPanel Orientation="Horizontal"><TextBlock x:Name="pubIcon" Style="{DynamicResource Glyph}" FontSize="15" Margin="0,0,8,0"/><TextBlock x:Name="pubHead" FontWeight="SemiBold" FontSize="14"/></StackPanel></Border>
      <TextBlock x:Name="pubDetail" TextWrapping="Wrap" Margin="2,8,0,0" LineHeight="20"/>
      <TextBlock x:Name="pubMeta" Visibility="Collapsed"/>
      <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><TextBlock x:Name="accIcon" Style="{DynamicResource Glyph}" FontSize="14" Margin="2,0,8,0"/><TextBlock x:Name="eAcc" VerticalAlignment="Center"/><Button x:Name="btnSign" Content="Check sign-in" Style="{DynamicResource GhostBtn}" Padding="10,3" Margin="10,0,0,0" FontSize="12"/></StackPanel></StackPanel>
     <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Right">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
       <Button x:Name="btnPrimary" Content="Push to GitHub" Style="{DynamicResource Btn}" FontSize="14" FontWeight="SemiBold" Padding="20,11" MinWidth="200" Margin="0,0,10,0"/>
       <Button x:Name="btnAll" Content="_Save &amp; publish to GitHub" Style="{DynamicResource PrimaryBtn}" FontSize="14.5" FontWeight="SemiBold" Padding="24,11" MinWidth="270" Margin="0"/></StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0"><Button x:Name="lnkUndo" Content="_Undo last edit" Style="{DynamicResource GhostBtn}" Padding="10,4" FontSize="12.5"/><Button x:Name="lnkDetails" Content="Show details" Style="{DynamicResource GhostBtn}" Padding="10,4" FontSize="12.5" Margin="0"/></StackPanel></StackPanel>
    </Grid></Border>
   <!-- activity log -->
   <Border x:Name="logCard" Grid.Row="6" Style="{DynamicResource CardStyle}" Padding="12" Margin="0,12,0,0" Visibility="Collapsed"><TextBox x:Name="eLog" IsReadOnly="True" Height="150" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/></Border>
  </Grid>
  </Grid>
  </ScrollViewer>

  <!-- toast -->
  <Border x:Name="toast" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,24" CornerRadius="10" Padding="18,12" Visibility="Collapsed" Panel.ZIndex="20"><StackPanel Orientation="Horizontal"><TextBlock x:Name="toastIcon" Style="{DynamicResource Glyph}" FontSize="16" Margin="0,0,10,0"/><TextBlock x:Name="toastText" FontWeight="SemiBold" VerticalAlignment="Center"/></StackPanel></Border>

  <!-- busy overlay -->
  <Grid x:Name="busy" Background="{DynamicResource Scrim}" Visibility="Collapsed" Panel.ZIndex="30">
   <Border Style="{DynamicResource CardStyle}" Width="480" Padding="26" HorizontalAlignment="Center" VerticalAlignment="Center">
    <StackPanel><TextBlock x:Name="busyTitle" Text="Working..." FontSize="19" FontWeight="SemiBold" TextWrapping="Wrap"/>
     <ProgressBar x:Name="busyBar" IsIndeterminate="True" Height="6" Margin="0,14,0,14" Foreground="{DynamicResource Accent}"/>
     <TextBlock x:Name="busyText" Foreground="{DynamicResource Muted}" TextWrapping="Wrap" LineHeight="24"/>
     <Button x:Name="btnCancelBusy" Content="Cancel" Style="{DynamicResource Btn}" HorizontalAlignment="Right" Margin="0,16,0,0"/></StackPanel></Border></Grid>
 </Grid>
</Window>
'@
$script:win = [Windows.Markup.XamlReader]::Parse($script:MainXaml)
$script:win.Resources.MergedDictionaries.Add($script:Res)
foreach ($m in [regex]::Matches($script:MainXaml, 'x:Name="(\w+)"')) { $n = $m.Groups[1].Value; Set-Variable -Name $n -Value ($script:win.FindName($n)) -Scope Script }
$f = $script:win; $script:ActiveOwner = $f
$script:win.Icon = $null

# glyphs
$icoFolder.Text = $script:I.Folder; $icoEmpty.Text = $script:I.Folder; $icoPlain.Text = $script:I.Warn; $icoFind.Text = $script:I.Search; $icoNone.Text = $script:I.Edit
# date fields
$ePick = New-Dt (Get-Date); $ePickHost.Children.Add($ePick.Panel) | Out-Null
$mPick = New-Dt (Get-Date).AddDays(-30); $mPickHost.Children.Add($mPick.Panel) | Out-Null
$nPick = New-Dt (Get-Date).AddDays(-1); $nDtHost.Children.Add($nPick.Panel) | Out-Null; $nDtHost.Visibility = 'Collapsed'
# "when" chips for the new commit
$script:nWhen = 'now'
$script:WhenBtns = @{}
foreach ($k in @(@('now', 'Now'), @('yesterday', 'Yesterday'), @('week', '1 week ago'), @('month', '1 month ago'), @('custom', 'Pick a date...'))) {
  $b = New-Button $k[1] 'normal'; $b.Style = $script:Res['ChipBtn']; $b.Padding = '14,6'; $b.Tag = $k[0]; $b.Margin = '0,0,8,6'; $spWhen.Children.Add($b) | Out-Null; $script:WhenBtns[$k[0]] = $b
}

# banners (stacked above the work area): icon, title, detail, optional extra row, actions
function New-Banner {
  $o = [pscustomobject]@{ Border = $null; Icon = $null; Title = $null; Detail = $null; Extra = $null; Actions = $null; Err = $null }
  $bd = New-Object Windows.Controls.Border; $bd.CornerRadius = '12'; $bd.Padding = '18,14'; $bd.Margin = '0,0,0,12'; $bd.Visibility = 'Collapsed'
  $g = New-Object Windows.Controls.Grid
  foreach ($w in @('Auto', '*', 'Auto')) { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $w; $g.ColumnDefinitions.Add($c) }
  $ic = New-Glyph '' 22; $ic.VerticalAlignment = 'Top'; $ic.Margin = '0,2,16,0'; [Windows.Controls.Grid]::SetColumn($ic, 0)
  $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
  $t = New-Tb '' 15 'Text' 'SemiBold'; $d = New-Tb '' 13 'Text'; $d.Margin = '0,3,0,0'; $d.LineHeight = 20
  $ex = New-Object Windows.Controls.WrapPanel; $ex.Margin = '0,10,0,0'; $ex.Visibility = 'Collapsed'
  $er = New-Tb '' 13 'ErrFg' 'SemiBold'; $er.Margin = '0,8,0,0'; $er.Visibility = 'Collapsed'
  foreach ($c in @($t, $d, $ex, $er)) { $sp.Children.Add($c) | Out-Null }
  $ac = New-Object Windows.Controls.StackPanel; $ac.Orientation = 'Horizontal'; $ac.VerticalAlignment = 'Center'; $ac.Margin = '16,0,0,0'; [Windows.Controls.Grid]::SetColumn($ac, 2)
  foreach ($c in @($ic, $sp, $ac)) { $g.Children.Add($c) | Out-Null }
  $bd.Child = $g; $spBan.Children.Add($bd) | Out-Null
  $o.Border = $bd; $o.Icon = $ic; $o.Title = $t; $o.Detail = $d; $o.Extra = $ex; $o.Actions = $ac; $o.Err = $er; $o
}
function Set-Banner($b, [string]$kind, [string]$glyph, [string]$title, [string]$detail) {
  $k = switch ($kind) { 'ok' { 'Ok' } 'warn' { 'Warn' } 'danger' { 'Err' } 'info' { 'Info' } default { 'Idle' } }
  SetRes $b.Border ([Windows.Controls.Border]::BackgroundProperty) "${k}Bg"; SetRes $b.Icon ([Windows.Controls.TextBlock]::ForegroundProperty) "${k}Fg"
  SetRes $b.Title ([Windows.Controls.TextBlock]::ForegroundProperty) "${k}Fg"; SetRes $b.Detail ([Windows.Controls.TextBlock]::ForegroundProperty) "${k}Fg"
  $b.Icon.Text = $glyph; $b.Title.Text = $title; $b.Detail.Text = $detail; $b.Detail.Visibility = $(if ($detail) { 'Visible' } else { 'Collapsed' })
}
function New-Field([string]$placeholder, [double]$w) {
  $g = New-Object Windows.Controls.Grid; $g.Width = $w; $g.Margin = '0,0,8,0'
  $tb = New-Object Windows.Controls.TextBox; $ph = New-Tb $placeholder 13 'Muted' 'Normal' $false; $ph.IsHitTestVisible = $false; $ph.Margin = '12,0,0,0'; $ph.VerticalAlignment = 'Center'
  $g.Children.Add($tb) | Out-Null; $g.Children.Add($ph) | Out-Null
  $tb.Add_TextChanged({ }) ; [pscustomobject]@{ Grid = $g; Box = $tb; Ph = $ph }
}
$bnPre = New-Banner; $bnHook = New-Banner; $bnLink = New-Banner; $bnSub = New-Banner
$bGitHelp = New-Button 'How to install Git' 'normal'; $bnPre.Actions.Children.Add($bGitHelp) | Out-Null
$fName = New-Field 'Your name' 190; $fMail = New-Field 'you@example.com' 230; $bSaveId = New-Button 'Save my name and email' 'primary'; $bSaveId.Margin = '0'
foreach ($c in @($fName.Grid, $fMail.Grid, $bSaveId)) { $bnPre.Extra.Children.Add($c) | Out-Null }
$tbName = $fName.Box; $tbMail = $fMail.Box; $lIdErr = $bnPre.Err
$bHookRemove = New-Button 'Remove it' 'normal'; $bHookKeep = New-Button 'Keep it' 'normal'; $bHookKeep.Margin = '0'; $bnHook.Actions.Children.Add($bHookRemove) | Out-Null; $bnHook.Actions.Children.Add($bHookKeep) | Out-Null
$fLink = New-Field 'https://github.com/you/my-project.git' 420; $bLink = New-Button 'Connect' 'primary'; $bNewRepo = New-Button 'Open github.com/new' 'normal'; $bNewRepo.Margin = '0'
foreach ($c in @($fLink.Grid, $bLink, $bNewRepo)) { $bnLink.Extra.Children.Add($c) | Out-Null }
$tbLink = $fLink.Box; $lLinkErr = $bnLink.Err
$script:Banners = @($bnPre, $bnHook, $bnLink, $bnSub)

# steps bar
function Set-Step([string]$n, [string]$state, [string]$sub) {
  $bd = Get-Variable -Name "st$n" -ValueOnly -Scope Script; $dot = Get-Variable -Name "st${n}d" -ValueOnly -Scope Script; $num = Get-Variable -Name "st${n}n" -ValueOnly -Scope Script
  $t = Get-Variable -Name "st${n}t" -ValueOnly -Scope Script; $s = Get-Variable -Name "st${n}s" -ValueOnly -Scope Script
  switch ($state) {
    'done' { SetRes $bd ([Windows.Controls.Border]::BackgroundProperty) 'Card'; SetRes $bd ([Windows.Controls.Border]::BorderBrushProperty) 'CardBorder'; SetRes $dot ([Windows.Controls.Border]::BackgroundProperty) 'OkBg'; SetRes $num ([Windows.Controls.TextBlock]::ForegroundProperty) 'OkFg'; $num.Text = $script:I.Check; $num.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol'); SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) 'Text' }
    'current' { SetRes $bd ([Windows.Controls.Border]::BackgroundProperty) 'Card'; SetRes $bd ([Windows.Controls.Border]::BorderBrushProperty) 'Accent'; SetRes $dot ([Windows.Controls.Border]::BackgroundProperty) 'Accent'; SetRes $num ([Windows.Controls.TextBlock]::ForegroundProperty) 'OnAccent'; $num.Text = $n; $num.FontFamily = $f.FontFamily; SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) 'Text' }
    default { SetRes $bd ([Windows.Controls.Border]::BackgroundProperty) 'Bg'; SetRes $bd ([Windows.Controls.Border]::BorderBrushProperty) 'CardBorder'; SetRes $dot ([Windows.Controls.Border]::BackgroundProperty) 'IdleBg'; SetRes $num ([Windows.Controls.TextBlock]::ForegroundProperty) 'Muted'; $num.Text = $n; $num.FontFamily = $f.FontFamily; SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) 'Muted' }
  }
  SetRes $s ([Windows.Controls.TextBlock]::ForegroundProperty) 'Muted'; $s.Text = $sub
  $bd.Tag = $state
}
#endregion


#region logic
$script:eRepo = $null; $script:eCommits = @(); $script:eEdits = @{}; $script:eOrig = @{}; $script:eSel = $null; $script:eSelShas = @(); $script:eView = 'none'
$script:ePush = $null; $script:ePushErr = $null; $script:eBackups = @(); $script:eFilling = $false; $script:eBusy = $false; $script:eLoadErr = $null; $script:eLoading = $false
$script:eSort = $null; $script:eAccess = $null; $script:SignInHook = $null; $script:IdentityHook = $null; $script:BgCancel = $false; $script:eRunning = $false; $script:eSteps = $null
$script:eChanges = @(); $script:eChecks = @{}; $script:ePlain = $null; $script:eSubNote = $null; $script:RowMap = @{}; $script:FileRows = @(); $script:Pre = $null
$ePath = $tbPath; $eFind = $tbFind; $ePrimary = $btnPrimary; $eAll = $btnAll; $eSign = $btnSign; $eUndo = $lnkUndo; $eHead = $pubHead; $eInfo = $pubDetail; $eMeta = $pubMeta; $eDetL = $lnkDetails

function Bind-Ph($tb, $ph) { $tb.Add_TextChanged({ $ph.Visibility = if ($tb.Text) { 'Collapsed' } else { 'Visible' } }.GetNewClosure()); $ph.Visibility = if ($tb.Text) { 'Collapsed' } else { 'Visible' } }
Bind-Ph $tbPath $phPath; Bind-Ph $tbInit $phInit; Bind-Ph $tbFind $phFind; Bind-Ph $nMsg $phNMsg; Bind-Ph $fName.Box $fName.Ph; Bind-Ph $fMail.Box $fMail.Ph; Bind-Ph $fLink.Box $fLink.Ph

function Add-ELog([string]$t) { $body = $t -replace "`r?`n", "`r`n    "; $eLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $body`r`n"); $eLog.ScrollToEnd() }
function EFail($err) { Add-ELog "ERROR: $($err.Exception.Message)"; Fail $err }
function Find-ECommit([string]$sha) { if ($sha -and $sha -ne '__new__') { @($script:eCommits | Where-Object { $_.Sha -eq $sha -or $_.Sha.StartsWith($sha) })[0] } }
function Get-EOrigMsg([string]$sha) { if (-not $script:eOrig.ContainsKey($sha)) { $script:eOrig[$sha] = Get-CommitMessage $script:eRepo $sha }; $script:eOrig[$sha] }
function First-Line([string]$m) { ($m -split "`n")[0].TrimEnd("`r") }
function Get-RepoLeaf { if ($script:eRepo) { Split-Path $script:eRepo -Leaf } else { '' } }
function Info-Text { "$($eHead.Text) $($eInfo.Text) $($eMeta.Text)" }
function Open-Url([string]$u) { if ($script:Confirm) { try { Start-Process $u } catch { Add-ELog "Could not open $u" } } }
function Fmt([datetime]$d) { $d.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }

# ---- toasts (results) and busy handling: slow git/network work runs in a background runspace, the window keeps repainting, Cancel stops it
$script:ToastTimer = $null
function Show-Toast([string]$text, [string]$kind = 'ok') {
  Set-Chip $toast $toastIcon $toastText $kind $(if ($kind -eq 'ok') { $script:I.Check } elseif ($kind -eq 'danger') { $script:I.Err } else { $script:I.Info }) $text
  $toast.Visibility = 'Visible'
  if (-not $script:Confirm) { return }
  if ($script:ToastTimer) { $script:ToastTimer.Stop() }
  $script:ToastTimer = New-Object Windows.Threading.DispatcherTimer; $script:ToastTimer.Interval = [TimeSpan]::FromSeconds(5)
  $script:ToastTimer.Add_Tick({ $toast.Visibility = 'Collapsed'; $script:ToastTimer.Stop() })
  $script:ToastTimer.Start()
}
function Stop-GitChildren { try { foreach ($p in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'git*' })) { & taskkill.exe /PID $p.ProcessId /T /F 2>&1 | Out-Null } } catch {} }
function Render-ERun {
  if (-not $script:eSteps) { return }
  $run = [string][char]0x25B6; $G = $script:G
  $lines = foreach ($s in $script:eSteps) { $g = switch ($s[0]) { 'ok' { $G.Ok } 'run' { $run } 'fail' { $G.Err } 'skip' { $G.Dash } default { $G.Off } }; "$g   $($s[1])" }
  $busyText.Text = ($lines -join "`r`n")
}
function Set-ERunStep([int]$i, [string]$state) { if ($script:eSteps) { $script:eSteps[$i][0] = $state; Render-ERun; if ($script:Confirm) { DoEvents } } }
function Start-ERun([string[]]$names) { $script:eRunning = $true; $script:eSteps = @(); foreach ($n in $names) { $script:eSteps += , @('todo', $n) }; Set-EBusy $true 'Saving and publishing...' $false; Render-ERun }
function Stop-ERun { $script:eRunning = $false; $script:eSteps = $null; Set-EBusy $false }
function Set-EBusy([bool]$on, [string]$label = 'Working...', [bool]$cancellable = $false) {
  if ($on) {
    $script:eBusy = $true; $busyTitle.Text = $label; if (-not $script:eSteps) { $busyText.Text = '' }
    $btnCancelBusy.Visibility = $(if ($cancellable) { 'Visible' } else { 'Collapsed' }); $btnCancelBusy.IsEnabled = $true; $busy.Visibility = 'Visible'; $rootGrid.IsEnabled = $false
  } else {
    if ($script:eRunning) { return }
    $script:eBusy = $false; $busy.Visibility = 'Collapsed'; $rootGrid.IsEnabled = $true; Update-EUi
  }
  if ($script:Confirm) { DoEvents }
}
function Invoke-Bg([string]$Label, [scriptblock]$Script, [object[]]$ArgList = @(), [bool]$Cancellable = $false) {
  if ($SelfTest -or $NoShow) { return (& $Script @ArgList) }
  Set-EBusy $true $Label $Cancellable; $script:BgCancel = $false
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript('param($root, $sb, $a) . (Join-Path $root "lib.ps1"); & ([scriptblock]::Create($sb)) @a').AddArgument($PSScriptRoot).AddArgument($Script.ToString()).AddArgument($ArgList)
  $t0 = Get-Date; $ar = $ps.BeginInvoke(); $cancelled = $false
  try {
    while (-not $ar.IsCompleted) {
      DoEvents; Start-Sleep -Milliseconds 30
      if (-not $script:eSteps) { $busyText.Text = "$([int]((Get-Date) - $t0).TotalSeconds) s" }
      if ($script:BgCancel -and -not $cancelled) { $cancelled = $true; if (-not $script:eSteps) { $busyText.Text = 'Cancelling...' }; [void]$ps.BeginStop($null, $null) }
      if ($cancelled) { Stop-GitChildren }
    }
    $out = $null; $err = $null
    try { $out = @($ps.EndInvoke($ar)) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $err = $e.Message }
    if ($cancelled) { throw 'Cancelled by you. Nothing was changed on GitHub.' }
    if ($err) { throw $err }
    if ($out.Count -eq 1) { $out[0] } else { $out }
  } finally { try { $ps.Dispose(); $rs.Dispose() } catch {}; Set-EBusy $false }
}
$btnCancelBusy.Add_Click({ $script:BgCancel = $true; $btnCancelBusy.IsEnabled = $false })

# ---- prerequisites: git installed? name + email known?
function Get-Prereq {
  $g = Test-GitInstalled; $n = ''; $m = ''
  if ($g) { $gi = Get-GlobalGitIdentity; $n = $gi.Name; $m = $gi.Mail }
  [pscustomobject]@{ Git = $g; Name = $n; Mail = $m; Ok = [bool]($g -and $n -and $m) }
}
function Vis([bool]$v) { if ($v) { 'Visible' } else { 'Collapsed' } }
function Update-EBanners {
  $G = $script:G; $I = $script:I; $pre = Get-Prereq; $script:Pre = $pre
  if ($pre.Ok) { $bnPre.Border.Visibility = 'Collapsed' }
  else {
    $bnPre.Border.Visibility = 'Visible'
    if (-not $pre.Git) { Set-Banner $bnPre 'warn' $I.Warn 'Before we start: Git is missing' 'backd8 uses Git, the free tool that keeps your project history. Install it once, then restart backd8.'; $bGitHelp.Visibility = 'Visible'; $bnPre.Extra.Visibility = 'Collapsed' }
    else { Set-Banner $bnPre 'warn' $I.Warn 'Before we start: who are you?' 'Git writes your name and email into every commit. Tell it once - it is saved for all your projects on this PC.'; $bGitHelp.Visibility = 'Collapsed'; $bnPre.Extra.Visibility = 'Visible'; if (-not $tbName.Text) { $tbName.Text = $pre.Name }; if (-not $tbMail.Text) { $tbMail.Text = $pre.Mail } }
  }
  $hs = $null; try { $hs = Get-Status } catch {}
  $dis = $false; try { $dis = [bool](Load-Ui).hookNoticeDismissed } catch {}
  if ($hs -and $hs.Installed -and (($hs.Enabled -and -not $script:hookOnKeep) -or (-not $hs.Enabled -and -not $dis -and -not $script:hookKeepSession))) {
    $bnHook.Border.Visibility = 'Visible'
    if ($hs.Enabled) { Set-Banner $bnHook 'danger' $I.Warn 'Auto-backdating is ON for this PC' "Every new commit you make in other programs gets a made-up date. You don't need it in this window - remove it unless you want it."; $bHookKeep.Content = 'Keep it for now' }
    else { Set-Banner $bnHook 'info' $I.Info 'Auto-backdating is installed on this PC (currently OFF)' "It is an optional extra and not needed here. Remove it if you don't use it."; $bHookKeep.Content = 'Keep it' }
  } else { $bnHook.Border.Visibility = 'Collapsed' }
  $needLink = [bool]($script:eRepo -and $script:ePush -and -not $script:ePush.Url)
  if ($needLink) { Set-Banner $bnLink 'warn' $I.Link 'Not connected to GitHub yet' 'To publish, create an empty repository at github.com/new and paste its address below. You can keep editing and committing without it.'; $bnLink.Extra.Visibility = 'Visible' }
  $bnLink.Border.Visibility = Vis $needLink
  if ($script:eLoadErr) { $x = Explain-Error $script:eLoadErr; Set-Banner $bnSub 'danger' $I.Err $x.Heading "$($x.Next)`r`nGit said: $($script:eLoadErr)"; $bnSub.Border.Visibility = 'Visible' }
  elseif ($script:eSubNote) { Set-Banner $bnSub 'info' $I.Info 'Using the whole project' $script:eSubNote; $bnSub.Border.Visibility = 'Visible' }
  else { $bnSub.Border.Visibility = 'Collapsed' }
}
function Do-SaveIdentity([string]$name, [string]$mail) {
  try {
    if (-not $PSBoundParameters.ContainsKey('name')) { $name = $tbName.Text.Trim(); $mail = $tbMail.Text.Trim() }
    $msg = $null
    if (-not $name) { $msg = 'Type your name first.' } elseif ($mail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $msg = 'Type a valid email address, for example you@example.com.' }
    if ($msg) { $lIdErr.Text = $msg; $lIdErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw $msg }; return }
    $lIdErr.Visibility = 'Collapsed'
    if ($script:IdentityHook) { & $script:IdentityHook $name $mail }
    else {
      Set-GitIdentity $name $mail

    }
    Add-ELog "Saved your name and email for git: $name <$mail>"; Show-Toast 'Saved your name and email'
  } catch { Fail $_ }
  Update-EBanners; Update-EUi
}

# ---- publish card text (plain language; every state has an icon and words, never colour alone)
function Set-Pub([string]$kind, [string]$glyph, [string]$head, [string]$detail, [string]$meta = '') {
  Set-Chip $pubChip $pubIcon $pubHead $kind $glyph $head
  $pubDetail.Text = $detail; $pubDetail.Visibility = Vis ([bool]$detail); $pubMeta.Text = $meta; $pubChip.ToolTip = $meta; $pubDetail.ToolTip = $meta
}
function Update-EInfo {
  $st = $script:ePush; $I = $script:I
  if (-not $script:eRepo) { Set-Pub 'idle' $I.Circle 'Nothing to publish yet' 'Choose a project folder first.'; return }
  if (-not $st) { Set-Pub 'danger' $I.Err "Can't read this project's GitHub state" "$($script:ePushErr)`r`nIf you are not on a branch, switch to one first (git switch main)." "Folder: $($script:eRepo)"; return }
  $rem = if ($st.Url) { "$($st.Remote)  $($st.Url)" } else { "none ('$($st.Remote)' not set)" }
  $meta = "Branch: $($st.Branch)    $($script:G.Dot)    GitHub address: $rem"
  $n = @($script:eCommits).Count
  if (-not $st.Url) { Set-Pub 'warn' $I.Warn 'Not connected to GitHub' 'This project has no GitHub address yet, so there is nothing to publish to. Paste an address in the yellow box above.' $meta }
  elseif ($n -eq 0) { Set-Pub 'idle' $I.Circle 'No commits yet' 'Commit your files first (the "New commit" row in your history), then publish.' $meta }
  elseif ($null -eq $st.Ahead) { Set-Pub 'info' $I.Cloud 'Not on GitHub yet' "Nothing has been published. Publishing sends your $(Plural $n 'commit' 'commits') to GitHub." $meta }
  elseif ($st.Ahead -eq 0 -and $st.Behind -eq 0) { Set-Pub 'ok' $I.Check 'In sync with GitHub' 'GitHub has exactly what your computer has. Nothing to publish.' $meta }
  elseif ($st.Behind -eq 0) { Set-Pub 'info' $I.Upload "$(Plural $st.Ahead 'commit is' 'commits are') not on GitHub yet" 'Publishing sends them. Nothing on GitHub is replaced.' $meta }
  elseif ($st.RemoteOnly -gt 0) { Set-Pub 'danger' $I.Warn "GitHub has $(Plural $st.RemoteOnly 'commit' 'commits') you don't have locally" "That is someone else's work, or your own edited commits after an undo. Replacing GitHub's version would DELETE them. Download them first (git pull), or replace on purpose." "$meta    (ahead $($st.Ahead) / behind $($st.Behind))" }
  elseif ($st.Ahead -eq 0) { Set-Pub 'danger' $I.Warn "GitHub has $(Plural $st.Behind 'newer commit' 'newer commits') than your computer" 'Download them first (git pull), or replace GitHub''s version if you know they can go.' "$meta    (ahead $($st.Ahead) / behind $($st.Behind))" }
  else { Set-Pub 'warn' $I.Warn 'GitHub still has the old version' "You changed commits that were already on GitHub, so its copy no longer matches yours. Publishing has to replace GitHub's old version: the old commits disappear there, and anyone who copied them must download again." "$meta    (technically: ahead $($st.Ahead) / behind $($st.Behind) - needs a force push)" }
}
function Update-EAccessLabel {
  $a = $script:eAccess; $I = $script:I; $kind = 'Muted'; $g = $I.Circle
  if (-not $script:eRepo -or -not $a) { $eAcc.Text = 'GitHub sign-in: not checked yet' }
  elseif (-not $a.GitInstalled) { $eAcc.Text = 'Git is not installed'; $g = $I.Err; $kind = 'ErrFg' }
  elseif (-not $a.Url) { $eAcc.Text = 'Not connected to GitHub' }
  elseif ($a.Transport -eq 'local') { $eAcc.Text = 'Local remote - no sign-in needed'; $g = $I.Check; $kind = 'OkFg' }
  elseif ($a.CanPush -eq $true) { $eAcc.Text = $(if ($a.Transport -eq 'ssh') { 'SSH key accepted' } else { 'Signed in to GitHub' }); $g = $I.Check; $kind = 'OkFg' }
  elseif ($a.CanPush -eq $false) { $eAcc.Text = $(if ($a.Transport -eq 'ssh') { 'SSH key not accepted' } else { 'NOT signed in to GitHub' }); $g = $I.Err; $kind = 'ErrFg' }
  else { $eAcc.Text = 'Could not check sign-in'; $g = $I.Warn; $kind = 'WarnFg' }
  $accIcon.Text = $g; SetRes $accIcon ([Windows.Controls.TextBlock]::ForegroundProperty) $kind; SetRes $eAcc ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($kind -eq 'Muted') { 'Muted' } else { 'Text' })
}
function Set-EAccess($a, [bool]$LogAdvice = $true) {
  $script:eAccess = $a; Update-EAccessLabel; Update-EUi
  if ($a -and $LogAdvice) { Add-ELog $eAcc.Text; foreach ($l in @($a.Advice)) { if ($l) { Add-ELog "Tip: $l" } } }
}
function Update-EAccess {
  if (-not $script:eRepo) { return }
  try { $r = $script:eRepo; Set-EAccess (Invoke-Bg 'Checking GitHub sign-in...' { param($p) Get-GitHubAccess $p } @($r) $true) }
  catch { $script:eAccess = $null; Update-EAccessLabel; Add-ELog "Could not check GitHub access: $($_.Exception.Message)" }
}

# ---- state helpers
function Get-ECheckedFiles { @($script:FileRows | Where-Object { $_.Box.IsChecked } | ForEach-Object { $_.Path }) }
function Get-ENewReady { [bool]($script:eRepo -and $script:eChanges.Count -and $nMsg.Text.Trim() -and (Get-ECheckedFiles).Count) }
function Get-EDirty {
  if ($script:eView -ne 'commit' -or -not $script:eSel) { return $false }
  $c = Find-ECommit $script:eSel; if (-not $c) { return $false }
  $ed = $script:eEdits[$c.Sha]
  $baseMsg = if ($ed -and $null -ne $ed.message) { $ed.message } else { Get-EOrigMsg $c.Sha }
  $baseDate = if ($ed -and $ed.date) { [datetime]$ed.date } else { $c.Date }
  $now = ($eMsg.Text -replace "`r`n", "`n").TrimEnd(); $d = $ePick.Value
  if ($d -eq [datetime]::MinValue) { return $true }
  $d = $d.AddMilliseconds(-$d.Millisecond)
  [bool](($now -cne "$baseMsg".TrimEnd()) -or ([math]::Abs(($d - $baseDate).TotalSeconds) -ge 1))
}
function Show-EView([string]$v) { $script:eView = $v; $vNone.Visibility = Vis ($v -eq 'none'); $vNew.Visibility = Vis ($v -eq 'new'); $vCommit.Visibility = Vis ($v -eq 'commit'); $vMulti.Visibility = Vis ($v -eq 'multi') }
function Set-NewWhen([string]$mode, $dt = $null) {
  $script:nWhen = $mode
  foreach ($k in $script:WhenBtns.Keys) { $script:WhenBtns[$k].Style = $script:Res[$(if ($k -eq $mode) { 'ChipOnBtn' } else { 'ChipBtn' })] }
  $now = Get-Date
  $v = switch ($mode) { 'yesterday' { $now.AddDays(-1) } 'week' { $now.AddDays(-7) } 'month' { $now.AddMonths(-1) } default { $null } }
  if ($dt) { $nPick.Value = [datetime]$dt } elseif ($v) { $nPick.Value = $v }
  $nDtHost.Visibility = Vis ($mode -ne 'now'); Update-EUi
}
function Get-ENext {
  $loaded = [bool]$script:eRepo; $st = $script:ePush; $nE = $script:eEdits.Count; $dirty = Get-EDirty
  $canPush = [bool]($loaded -and $st -and $st.Url -and @($script:eCommits).Count -and -not ($st.Ahead -eq 0 -and $st.Behind -eq 0))
  $force = [bool]($canPush -and $st.Behind -gt 0)
  $needSign = [bool]($canPush -and $script:eAccess -and $script:eAccess.Transport -in 'https', 'ssh' -and $script:eAccess.CanPush -eq $false)
  $newReady = Get-ENewReady
  $role = 'none'; $text = 'Push to GitHub'
  if (-not $loaded) { $text = 'Choose a folder first' }
  elseif ($newReady) { $role = 'commit'; $text = 'Commit these files' }
  elseif ($nE -or $dirty) { $role = 'apply'; $n = $nE + $(if ($dirty -and -not ($script:eSel -and $script:eEdits.ContainsKey($script:eSel))) { 1 } else { 0 }); $text = "Apply my $(Plural $n 'edit' 'edits')" }
  elseif ($needSign) { $role = 'signin'; $text = 'Sign in to GitHub' }
  elseif ($force) { $role = 'force'; $text = "Replace GitHub's version..." }
  elseif ($canPush) { $role = 'push'; $text = 'Push to GitHub' }
  [pscustomobject]@{ Role = $role; Text = $text; CanPush = $canPush; Force = $force; NewReady = $newReady; Dirty = $dirty; Edits = $nE; HasRemote = [bool]($st -and $st.Url) }
}
function Update-EUi {
  $G = $script:G; $loaded = [bool]$script:eRepo; $st = $script:ePush; $nE = $script:eEdits.Count
  $next = Get-ENext; $script:eNext = $next
  $mode = if ($loaded) { 'project' } elseif ($script:ePlain) { 'plain' } else { 'empty' }
  $pEmpty.Visibility = Vis ($mode -eq 'empty'); $pPlain.Visibility = Vis ($mode -eq 'plain'); $pProject.Visibility = Vis ($mode -eq 'project')
  $pubBar.Visibility = Vis ($mode -ne 'plain')
  $tbFind.IsEnabled = $loaded
  $one = ($script:eView -eq 'commit') -and [bool]$script:eSel
  $eDisc.IsEnabled = $one -and $script:eEdits.ContainsKey($script:eSel)
  $eSave.IsEnabled = $one -and $next.Dirty
  if ($one) {
    $c = Find-ECommit $script:eSel
    if ($c) {
      $staged = $script:eEdits.ContainsKey($c.Sha)
      $eSelHead.Text = "Change commit $($c.Short)"
      $eSelSub.Text = "by $($c.Author)  $($G.Dot)  " + $(if ($next.Dirty) { 'you have unsaved typing' } elseif ($staged) { 'changed, not written to the project yet' } else { 'original' })
      $eSaveState.Text = if ($next.Dirty) { "Press Save change - or just click another commit, your typing is kept." } elseif ($staged) { "$($G.Ok) Saved. It is written into your project when you press Apply." } else { 'Nothing changed yet.' }
    }
  }
  $nB = @(Get-ECheckedFiles); $nCount.Text = "$($nB.Count) of $($script:eChanges.Count) selected"
  $nBtn.IsEnabled = $next.NewReady
  $nHint.Text = if ($script:eChanges.Count -and -not $nB.Count) { 'Tick at least one file.' } elseif ($script:eChanges.Count -and -not $nMsg.Text.Trim()) { 'Write a short message to continue.' } elseif ($script:nWhen -ne 'now') { "Will be dated $(Fmt $nPick.Value)." } else { 'Will be dated now.' }
  $ePrimary.Content = $next.Text; $ePrimary.IsEnabled = ($next.Role -ne 'none')
  $allOk = [bool]($loaded -and $next.HasRemote -and ($next.NewReady -or $nE -gt 0 -or $next.Dirty) -and $st -and $mode -eq 'project')
  $eAll.IsEnabled = $allOk; $eAll.Content = '_Save & publish to GitHub'
  $kAll = if ($allOk) { 'primary' } else { 'normal' }; $kPri = if ($next.Role -ne 'none' -and -not $allOk) { 'primary' } else { 'normal' }
  Set-Kind $eAll $kAll; Set-Kind $ePrimary $kPri
  $eAll.Visibility = Vis $allOk; $ePrimary.Visibility = Vis ($mode -eq 'project')
  $script:ePrimaryBtn = if ($allOk) { $eAll } elseif ($next.Role -ne 'none') { $ePrimary } else { $null }
  Set-Kind $nBtn $(if ($next.Role -eq 'commit' -and -not $allOk) { 'normal' } else { 'normal' })
  Set-Kind $eSave $(if ($eSave.IsEnabled -and -not $script:ePrimaryBtn) { 'primary' } else { 'normal' })
  Set-Kind $btnBrowse $(if ($loaded -or $script:ePlain) { 'normal' } else { 'primary' })
  $eSign.IsEnabled = $loaded -and $next.HasRemote; $eSign.Visibility = Vis ($loaded -and $next.HasRemote); $accIcon.Visibility = Vis $loaded; $eAcc.Visibility = Vis $loaded
  $eUndo.Visibility = Vis $loaded; $eUndo.IsEnabled = $loaded -and @($script:eBackups).Count -gt 0
  Tip $eUndo $(if ($eUndo.IsEnabled) { 'Put the project back to how it was before your last Apply (Ctrl+Z). Refused if the branch changed since; you can then undo anyway.' } else { 'Nothing to undo: no backup of this branch exists.' })
  Tip $eDisc 'Throw away your saved change to this commit and show the original message and date again.'
  Tip $eSave 'Keep this message/date as a pending change. Nothing is rewritten until you press Apply.'
  Tip $ePrimary $(switch ($next.Role) {
      'commit' { 'Save the ticked files as a new commit with your message.' }
      'apply' { "Write your pending edits into the project. The edited commits and every later commit get new IDs. A backup is kept for Undo. Nothing is sent to GitHub yet." }
      'signin' { 'Sign in to GitHub in a separate window (browser, GitHub CLI or SSH test). backd8 never stores your password or token.' }
      'force' { "GitHub's copy and yours differ, so a normal push would be refused. This replaces GitHub's version (a force push with a safety lease). You must confirm it." }
      'push' { "Send the new commits of '$($st.Branch)' to $($st.Remote) ($($st.Url))." }
      default { if (-not $loaded) { 'Choose a project folder first.' } elseif (-not $next.HasRemote) { 'Connect a GitHub address first.' } else { 'Nothing to do: your project and GitHub match.' } } })
  Tip $eAll $(if ($eAll.IsEnabled) { 'Does everything in order: commit the ticked files (if you wrote a message), apply your edits, sign in if needed, push to GitHub. You confirm first.' } else { 'Available when you have a new commit or edits waiting and a GitHub address.' })
  # steps bar
  $name = Get-RepoLeaf; $draft = [bool]($script:eChanges.Count -and $nMsg.Text.Trim())
  $waiting = $nE + $(if ($next.Dirty) { 1 } else { 0 }) + $(if ($next.NewReady) { 1 } else { 0 })
  if (-not $loaded) { Set-Step '1' 'current' $(if ($script:ePlain) { 'Make it a project' } else { 'Browse or drop a folder' }); Set-Step '2' 'todo' 'Choose a project first'; Set-Step '3' 'todo' 'After your changes' }
  else {
    Set-Step '1' 'done' $name
    if ($waiting) { Set-Step '2' 'current' "$(Plural $waiting 'change' 'changes') waiting"; Set-Step '3' 'todo' 'Press the big button' }
    elseif ($next.CanPush) { Set-Step '2' 'done' 'Nothing waiting'; Set-Step '3' 'current' $(if ($next.Force) { "Replace GitHub's old version" } else { 'Ready to publish' }) }
    else { Set-Step '2' 'current' 'Pick a commit or new files'; Set-Step '3' 'todo' $(if (-not $next.HasRemote) { 'Connect GitHub first' } elseif ($st -and $st.Ahead -eq 0 -and $st.Behind -eq 0) { 'GitHub is up to date' } else { 'Nothing to publish' }) }
  }
  Update-ECount
}

# ---- history list (rows are built in code; no data binding needed)
function Get-EView {
  $v = @($script:eCommits); $q = $tbFind.Text.Trim()
  if ($q) { $v = @($v | Where-Object { $_.Subject -like "*$q*" -or $_.Author -like "*$q*" -or $_.Sha.StartsWith($q.ToLower()) -or $_.Date.ToString('yyyy-MM-dd HH:mm') -like "*$q*" -or ($script:eEdits[$_.Sha] -and $script:eEdits[$_.Sha].message -like "*$q*") }) }
  if ($script:eSort) {
    $key = switch ($script:eSort.Col) { 'date' { { $_.Date } } 'msg' { { $_.Subject } } 'id' { { $_.Short } } default { { $_.Date } } }
    $v = @($v | Sort-Object -Property $key -Descending:$script:eSort.Desc)
  }
  $v
}
function New-HistRow([string]$tag) {
  $g = New-Object Windows.Controls.Grid
  foreach ($w in @(30, 142, 0, 72)) { $c = New-Object Windows.Controls.ColumnDefinition; if ($w) { $c.Width = New-Object Windows.GridLength($w) } else { $c.Width = New-Object Windows.GridLength(1, 'Star') }; $g.ColumnDefinitions.Add($c) }
  $mark = New-Glyph '' 14; $date = New-Tb '' 13 'Muted' 'Normal' $false; $subj = New-Tb '' 13 'Text' 'Normal' $false; $subj.TextTrimming = 'CharacterEllipsis'; $subj.Margin = '0,0,12,0'; $id = New-Tb '' 12 'Muted' 'Normal' $false; $id.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
  $i = 0; foreach ($c in @($mark, $date, $subj, $id)) { [Windows.Controls.Grid]::SetColumn($c, $i); $g.Children.Add($c) | Out-Null; $i++ }
  $it = New-Object Windows.Controls.ListBoxItem; $it.Content = $g; $it.Tag = $tag; $it.Style = $script:Res['RowItem']
  @{ Item = $it; Mark = $mark; Date = $date; Subj = $subj; Id = $id }
}
function Style-HistRow($r, $c) {
  $ed = $script:eEdits[$c.Sha]; $subj = $c.Subject; $date = $c.Date
  if ($ed) { if ($null -ne $ed.message) { $subj = First-Line $ed.message }; if ($ed.date) { $date = [datetime]$ed.date } }
  $r.Mark.Text = $(if ($ed) { $script:I.Edit } else { '' }); SetRes $r.Mark ([Windows.Controls.TextBlock]::ForegroundProperty) 'Accent'
  $r.Date.Text = Fmt $date; $r.Subj.Text = $(if ($c.IsMerge) { "[merge] $subj" } else { $subj }); $r.Id.Text = $c.Short
  $r.Subj.FontWeight = $(if ($ed) { 'SemiBold' } else { 'Normal' }); SetRes $r.Subj ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($ed) { 'Accent' } elseif ($c.IsMerge) { 'Muted' } else { 'Text' })
  SetRes $r.Date ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($ed -and $ed.date) { 'Accent' } else { 'Muted' })
  $r.Item.ToolTip = "$($c.Short)  $(Fmt $date)  $($c.Author)`r`n$subj" + $(if ($ed) { "`r`n(changed - not applied yet)" } else { '' })
}
function Update-EItem([string]$sha) { $r = $script:RowMap[$sha]; if ($r) { $c = Find-ECommit $sha; if ($c) { Style-HistRow $r $c } } }
function Update-ECount {
  $n = $script:eCommits.Count; $shown = @($lbHist.Items | Where-Object { $_.Tag -ne '__new__' }).Count
  $tHistCount.Text = if (-not $script:eRepo) { '' } else { $(if ($shown -ne $n) { "$shown of $(Plural $n 'commit' 'commits')" } else { Plural $n 'commit' 'commits' }) }
  $tbHistEmpty.Visibility = Vis ($lbHist.Items.Count -eq 0)
  $tbHistEmpty.Text = if (-not $script:eRepo) { '' } elseif ($n -eq 0) { "No commits yet and no changed files.`r`nAdd or change a file in the folder, then press F5." } elseif ($shown -eq 0) { "No commit matches '$($tbFind.Text.Trim())'." } else { '' }
}
function Fill-EList {
  $script:eFilling = $true
  try {
    $lbHist.Items.Clear(); $script:RowMap = @{}
    if ($script:eRepo -and $script:eChanges.Count) {
      $r = New-HistRow '__new__'; $n = $script:eChanges.Count
      $r.Mark.Text = $script:I.Add; SetRes $r.Mark ([Windows.Controls.TextBlock]::ForegroundProperty) 'Accent'; $r.Date.Text = 'now'; SetRes $r.Date ([Windows.Controls.TextBlock]::ForegroundProperty) 'Accent'
      $r.Subj.Text = "New commit - $(Plural $n 'changed file' 'changed files')"; $r.Subj.FontWeight = 'SemiBold'; SetRes $r.Subj ([Windows.Controls.TextBlock]::ForegroundProperty) 'Accent'
      $r.Item.ToolTip = 'Your files have changes that are not saved in a commit yet. Click to save them.'
      [void]$lbHist.Items.Add($r.Item); if ($script:eSelShas -contains '__new__') { $r.Item.IsSelected = $true }
    }
    foreach ($c in (Get-EView)) {
      $r = New-HistRow $c.Sha; Style-HistRow $r $c; $script:RowMap[$c.Sha] = $r; [void]$lbHist.Items.Add($r.Item)
      if ($script:eSelShas -contains $c.Sha) { $r.Item.IsSelected = $true }
    }
  } finally { $script:eFilling = $false }
  $hSortDate.Content = 'When' + $(if ($script:eSort -and $script:eSort.Col -eq 'date') { " $(if ($script:eSort.Desc) { $script:G.Down } else { $script:G.Up })" } else { '' })
  $hSortMsg.Content = 'What you saved (message)' + $(if ($script:eSort -and $script:eSort.Col -eq 'msg') { " $(if ($script:eSort.Desc) { $script:G.Down } else { $script:G.Up })" } else { '' })
  $hSortId.Content = 'ID' + $(if ($script:eSort -and $script:eSort.Col -eq 'id') { " $(if ($script:eSort.Desc) { $script:G.Down } else { $script:G.Up })" } else { '' })
  Update-ECount
}
function Fill-EFiles {
  $spFiles.Children.Clear(); $script:FileRows = @()
  foreach ($c in $script:eChanges) {
    $risky = [bool]$c.Risky
    $cb = New-Object Windows.Controls.CheckBox; $cb.Tag = $c.Path; $cb.Margin = '0,3,0,3'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $kindText = switch ($c.Kind) { 'new' { 'New file' } 'deleted' { 'Deleted' } 'renamed' { "Renamed (was $($c.OldPath))" } default { 'Changed' } }
    $tn = New-Tb $c.Path 13 'Text' 'Normal' $false; $tk = New-Tb "   $kindText" 12 'Muted' 'Normal' $false; $tk.VerticalAlignment = 'Center'
    if ($risky) { $w = New-Glyph $script:I.Warn 14 'WarnFg'; $w.Margin = '0,0,6,0'; $sp.Children.Add($w) | Out-Null; $tk.Text = "   $kindText - may hold passwords or keys"; SetRes $tk ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $cb.ToolTip = 'This file name usually holds secrets (passwords, keys). It starts unticked - only include it if you are sure.' }
    $sp.Children.Add($tn) | Out-Null; $sp.Children.Add($tk) | Out-Null; $cb.Content = $sp
    $cb.IsChecked = $(if ($script:eChecks.ContainsKey($c.Path)) { [bool]$script:eChecks[$c.Path] } else { -not $risky })
    $cb.Add_Click({ $script:eChecks[[string]$this.Tag] = [bool]$this.IsChecked; Update-EUi })
    [void]$spFiles.Children.Add($cb); $script:FileRows += [pscustomobject]@{ Path = $c.Path; Box = $cb; Risky = $risky; Text = $c.Path }
  }
}
function Clear-EDetail { $script:eSel = $null; $script:eSelShas = @(); $script:eLoading = $true; try { $eMsg.Text = '' } finally { $script:eLoading = $false }; $eWarn.Visibility = 'Collapsed'; Show-EView 'none' }
function Reset-ELoaded {
  $script:eRepo = $null; $script:eCommits = @(); $script:eEdits = @{}; $script:eOrig = @{}; $script:ePush = $null; $script:ePushErr = $null; $script:eBackups = @(); $script:eAccess = $null; $script:eLoadErr = $null
  $script:eChanges = @(); $script:eChecks = @{}; $script:ePlain = $null; $script:eSubNote = $null
  Clear-EDetail; Fill-EList; Fill-EFiles; Update-EInfo; Update-EAccessLabel; Update-EBanners; Update-EUi
}
function Get-EPendingNote {
  $n = $script:eEdits.Count; $draft = [bool]($script:eChanges.Count -and $nMsg.Text.Trim())
  if (-not $n -and -not $draft) { return $null }
  $a = @(); if ($n) { $a += "$(Plural $n 'saved change' 'saved changes') to old commits" }; if ($draft) { $a += 'the message you typed for a new commit' }
  ($a -join ' and ')
}
function Do-ELoad([string]$path, [switch]$Quiet, [switch]$NoAccess, [string]$Chosen) {
  try {
    if (-not $path) { $path = $tbPath.Text.Trim().Trim('"') }
    $root = Get-RepoRoot $path
    $same = $script:eRepo -and (Norm $root) -eq (Norm $script:eRepo)
    if (-not $same) {
      $pend = Get-EPendingNote
      if ($pend -and $script:Confirm) {
        if ((Ask 'backd8 - open another folder' "Leave '$(Get-RepoLeaf)' and lose unsaved work?" "You have $pend that are not saved into git yet. They are lost if you continue." @('Discard and open the other folder', 'Keep working here') 1 'warn') -ne 0) { $tbPath.Text = $script:eRepo; return }
      }
      $script:eEdits = @{}; $script:eSel = $null; $script:eSelShas = @(); $script:eOrig = @{}; $script:eChecks = @{}; $nMsg.Text = ''; Clear-EDetail
    }
    $script:eLoadErr = $null; $script:ePlain = $null; $script:eRepo = $root; $tbPath.Text = $root
    $script:eSubNote = $null; if ($Chosen -and (Norm $Chosen) -ne (Norm $root)) { $script:eSubNote = "You chose '$Chosen', which is inside the project '$root'. backd8 works on the whole project." }
    $script:eCommits = @(Get-CommitList $root 300)
    $script:eChanges = @(); try { $script:eChanges = @(Get-WorkingChanges $root) } catch { Add-ELog "Could not read changed files: $($_.Exception.Message)" }
    $script:ePush = $null; $script:ePushErr = $null
    try { $script:ePush = Get-PushState $root } catch { $script:ePushErr = $_.Exception.Message }
    $script:eBackups = @(); try { $script:eBackups = @(Get-Backups $root) } catch { }
    if ($script:eSel -and -not (Find-ECommit $script:eSel)) { Clear-EDetail }
    Fill-EFiles; Fill-EList; Update-EInfo; Update-EBanners; Update-EUi
    Add-ELog "Opened $root - $(Plural $script:eCommits.Count 'commit' 'commits')$(if ($script:eChanges.Count) { ", $(Plural $script:eChanges.Count 'changed file' 'changed files') not committed" })."
    if (-not $same) { $script:eAccess = $null; Update-EAccessLabel }
    if ($script:Confirm) { Save-Ui $null '' $root }
    if (-not $script:eSelShas -or -not $script:eSelShas.Count) { if ($script:eChanges.Count) { Do-ESelect '__new__' } else { Show-EView 'none' } }
    elseif ($script:eView -eq 'new' -and -not $script:eChanges.Count) { Clear-EDetail }
    Update-EUi
    if (-not $NoAccess) { Update-EAccess }
  } catch {
    if ($Quiet) { Add-ELog "Could not open: $($_.Exception.Message)" }
    elseif ($script:Confirm) { $m = $_.Exception.Message; Reset-ELoaded; $script:eLoadErr = $m; Update-EBanners; Update-EUi; Add-ELog "ERROR: $m" }
    else { Reset-ELoaded; EFail $_ }
  }
}
# One entry point for every way of choosing a folder: browse, paste, recent list, drag and drop, last session.
function Open-Folder([string]$path, [switch]$Quiet, [switch]$NoAccess) {
  try {
    $path = "$path".Trim().Trim('"'); if (-not $path) { return }
    if (-not (Test-GitInstalled)) { Update-EBanners; Add-ELog 'Git is not installed - see "Before we start".'; return }
    $t = Test-IsRepo $path
    if (-not $t.Exists) { throw "Folder not found: $path" }
    if (-not $t.IsRepo) {
      $pend = Get-EPendingNote
      if ($pend -and $script:Confirm -and (Ask 'backd8 - open another folder' "Leave '$(Get-RepoLeaf)' and lose unsaved work?" "You have $pend that are not saved into git yet. They are lost if you continue." @('Discard and open the other folder', 'Keep working here') 1 'warn') -ne 0) { $tbPath.Text = $script:eRepo; return }
      Reset-ELoaded; $script:ePlain = $t.Folder; $tbPath.Text = $t.Folder; $wpFolder.Text = $t.Folder; $tbInit.Text = ''; $wpErr.Visibility = 'Collapsed'
      Add-ELog "$($t.Folder) is not a git project yet."; Update-EUi; return
    }
    Do-ELoad $t.Root -Quiet:$Quiet -NoAccess:$NoAccess -Chosen $t.Folder
  } catch {
    if ($Quiet) { Add-ELog "Could not open: $($_.Exception.Message)" }
    elseif ($script:Confirm) { $m = $_.Exception.Message; Reset-ELoaded; $script:eLoadErr = $m; Update-EBanners; Update-EUi; Add-ELog "ERROR: $m" }
    else { Reset-ELoaded; EFail $_ }
  }
}
function Do-EBrowse([string]$path) {
  try {
    if (-not $path) {
      $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose the folder of your project'
      if ($tbPath.Text -and (Test-Path -LiteralPath $tbPath.Text -PathType Container)) { $d.SelectedPath = $tbPath.Text }
      if ($d.ShowDialog() -ne 'OK') { return }; $path = $d.SelectedPath
    }
    $tbPath.Text = $path
  } catch { EFail $_; return }
  Open-Folder $path
}
function Do-EInit([string]$url) {
  try {
    if (-not $script:ePlain) { return }
    if (-not $PSBoundParameters.ContainsKey('url')) { $url = $tbInit.Text.Trim() }
    if ($url -and -not (Test-RemoteUrl $url)) { $wpErr.Text = 'That does not look like a GitHub address. Example: https://github.com/you/my-project.git'; $wpErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw 'Bad GitHub address.' }; return }
    $wpErr.Visibility = 'Collapsed'; $folder = $script:ePlain
    [void](Initialize-Repo $folder $url)
    Add-ELog "Turned $folder into a git project$(if ($url) { " linked to $(Hide-Secrets $url)" })."
    $script:ePlain = $null; Open-Folder $folder -NoAccess
    Show-Toast 'Your folder is now a git project'
    if ($url) { Update-EAccess }
  } catch { EFail $_ }
}
function Do-EConnect([string]$url) {
  try {
    if (-not $script:eRepo) { return }
    if (-not $PSBoundParameters.ContainsKey('url')) { $url = $tbLink.Text.Trim() }
    if (-not (Test-RemoteUrl $url)) { $lLinkErr.Text = 'That does not look like a GitHub address. Example: https://github.com/you/my-project.git'; $lLinkErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw 'Bad GitHub address.' }; return }
    $lLinkErr.Visibility = 'Collapsed'
    Add-ELog (Set-RemoteUrl $script:eRepo $url)
    $tbLink.Text = ''; $script:eAccess = $null
    Do-ELoad $script:eRepo -NoAccess
    Show-Toast 'Connected to GitHub'
    Update-EAccess
  } catch { EFail $_ }
}

# ---- selecting rows
function Do-ESelect([string]$sha) {
  try {
    $items = @($lbHist.SelectedItems)
    $tags = @(if ($sha) { $sha } else { $items | ForEach-Object { [string]$_.Tag } })
    $prev = $script:eSel
    if ($prev -and (Get-EDirty) -and -not ($tags.Count -eq 1 -and $tags[0] -eq $prev)) { try { Sync-EEdit } catch { } }   # never lose a typed change
    $script:eSelShas = $tags
    $commits = @($tags | Where-Object { $_ -ne '__new__' })
    if ($tags.Count -eq 1 -and $tags[0] -eq '__new__') { $script:eSel = $null; Show-EView 'new'; Update-EUi; return }
    if ($commits.Count -eq 0) { $script:eSel = $null; Show-EView 'none'; Update-EUi; return }
    if ($commits.Count -gt 1) { $script:eSel = $null; Show-EView 'multi'; $mHead.Text = "$($commits.Count) commits selected"; Update-EMulti; Update-EUi; return }
    $c = Find-ECommit $commits[0]
    if (-not $c) { Clear-EDetail; Update-EUi; return }
    $script:eSel = $c.Sha
    $ed = $script:eEdits[$c.Sha]
    $msg = if ($ed -and $null -ne $ed.message) { $ed.message } else { Get-EOrigMsg $c.Sha }
    $d = if ($ed -and $ed.date) { [datetime]$ed.date } else { $c.Date }
    $script:eLoading = $true
    try { $ePick.Value = $d; $eMsg.Text = $msg -replace "`r?`n", "`r`n" } finally { $script:eLoading = $false }
    $eWarn.Visibility = 'Collapsed'; Show-EView 'commit'
    Update-EUi
  } catch { EFail $_ }
}
function Update-EMulti {
  $n = @($script:eSelShas | Where-Object { $_ -ne '__new__' }).Count; if ($n -lt 2) { return }
  $s = $mPick.Value
  if ($s -eq [datetime]::MinValue) { $mPrev.Text = 'Type the date like 2025-03-01 and the time like 09:30.'; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $mBtn.IsEnabled = $false; return }
  $avg = $s.AddMinutes(210 * ($n - 1)); $fast = $s.AddMinutes(60 * ($n - 1))
  if ($fast -gt (Get-Date)) { $mPrev.Text = "$($script:I.Err) These $n commits do not fit before today. Choose an earlier first date."; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $mBtn.IsEnabled = $false }
  else { $mPrev.Text = "From $(Fmt $s) to about $(Fmt $avg) (roughly 3.5 hours between commits)."; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'Text'; $mBtn.IsEnabled = $true }
}
function Do-ESpread {
  try {
    $shas = @($script:eSelShas | Where-Object { $_ -ne '__new__' }); if ($shas.Count -lt 1) { return }
    $cs = @($shas | ForEach-Object { Find-ECommit $_ } | Where-Object { $_ } | Sort-Object { $_.Date })
    $dates = $null; $last = $null
    foreach ($try in 1..8) { try { $dates = New-DateSpread -Start $mPick.Value -Count $cs.Count; break } catch { $last = $_ } }
    if (-not $dates) { throw $last }
    for ($i = 0; $i -lt $cs.Count; $i++) {
      $c = $cs[$i]; $ed = $script:eEdits[$c.Sha]; if (-not $ed) { $ed = @{} }
      $ed.date = $dates[$i]; $script:eEdits[$c.Sha] = $ed; Update-EItem $c.Sha
    }
    Add-ELog "Re-dated $($cs.Count) commit(s): $(Fmt $dates[0]) ... $(Fmt $dates[-1]). Press Apply to write them."
    Show-Toast "New dates set for $(Plural $cs.Count 'commit' 'commits')"; Update-EUi
  } catch { EFail $_ }
}

# ---- editing a commit: the controls and the pending-edit table stay in sync
function Sync-EEdit([switch]$Strict) {
  $c = Find-ECommit $script:eSel
  if (-not $c) { if ($Strict) { throw 'Select a commit first.' }; return }
  $new = ($eMsg.Text -replace "`r`n", "`n").TrimEnd()
  if (-not $new.Trim()) { $eWarn.Text = "The message can't be empty - this change is not kept."; $eWarn.Visibility = 'Visible'; if ($Strict) { throw 'The commit message cannot be empty.' }; return }
  $d = $ePick.Value
  if ($d -eq [datetime]::MinValue) { $eWarn.Text = 'Type the date like 2025-03-01 and the time like 09:30.'; $eWarn.Visibility = 'Visible'; if ($Strict) { throw 'The date is not valid. Use yyyy-MM-dd and HH:mm.' }; return }
  $d = $d.AddMilliseconds(-$d.Millisecond)
  if ($d -gt (Get-Date)) { $eWarn.Text = 'The date must be in the past.'; $eWarn.Visibility = 'Visible'; if ($Strict) { throw 'The date must be in the past.' }; return }
  $eWarn.Visibility = 'Collapsed'
  $ed = @{}
  if ($new -cne (Get-EOrigMsg $c.Sha)) { $ed.message = $new }
  if ([math]::Abs(($d - $c.Date).TotalSeconds) -ge 1) { $ed.date = $d }
  if ($ed.Count) { $script:eEdits[$c.Sha] = $ed; Add-ELog "Saved change for $($c.Short): $((@($ed.Keys) | Sort-Object) -join ' + ')." }
  else { [void]$script:eEdits.Remove($c.Sha); if ($Strict) { Add-ELog "$($c.Short) is the same as the original - nothing to save." } }
  Update-EItem $c.Sha; Update-EUi
}
function Do-EStage { try { Sync-EEdit -Strict } catch { EFail $_ } }
function Do-EDiscard {
  try {
    $sha = $script:eSel
    if (-not $sha -or -not $script:eEdits.ContainsKey($sha)) { return }
    [void]$script:eEdits.Remove($sha); Add-ELog "Reverted your change to $($sha.Substring(0, 7))."
    Update-EItem $sha; Do-ESelect $sha
  } catch { EFail $_ }
}

# ---- commit new files
function Do-ENewCommit {
  try {
    if (-not $script:eRepo) { return }
    $files = @(Get-ECheckedFiles); $msg = $nMsg.Text
    if (-not $files.Count) { throw 'Choose at least one file to commit.' }
    if (-not $msg.Trim()) { throw 'Write a commit message first.' }
    $date = $null; if ($script:nWhen -ne 'now') { $date = $nPick.Value; if ($date -eq [datetime]::MinValue) { throw 'The date is not valid. Use yyyy-MM-dd and HH:mm.' }; if ($date -gt (Get-Date)) { throw 'Date must be in the past.' } }
    $risky = @($script:eChanges | Where-Object { $_.Risky -and $files -contains $_.Path })
    if ($risky.Count -and $script:Confirm) {
      if ((Ask 'backd8 - commit' 'Commit files that may hold secrets?' "These files usually contain passwords or private keys. Once they are on GitHub, assume they are public.`n`n$(($risky | ForEach-Object { $_.Path }) -join "`n")" @('Include them anyway', 'Cancel') 1 'error') -ne 0) { Add-ELog 'Commit cancelled.'; return }
    }
    $r = $script:eRepo
    $c = Invoke-Bg 'Saving your new commit...' { param($p, $m, $fs, $d) $a = @{ Path = $p; Message = $m; Files = $fs }; if ($d) { $a.Date = $d }; New-CommitFromChanges @a } @($r, $msg, $files, $date)
    Add-ELog "Committed $($c.Short): $($c.Subject)  (dated $(Fmt $c.Date))"
    $script:eChecks = @{}; $nMsg.Text = ''; $script:eSelShas = @(); Set-NewWhen 'now'
    Do-ELoad $r -NoAccess
    Show-Toast "Saved commit $($c.Short) $($script:G.Dot) $(Fmt $c.Date)"
    return $true
  } catch { EFail $_ }
  $false
}

function Get-EPushedEdits {
  $n = 0
  try {
    $s = Get-PushState $script:eRepo
    $ref = if ($s.Upstream) { $s.Upstream } else { "refs/remotes/$($s.Remote)/$($s.Branch)" }
    if (-not (Git-Out $script:eRepo @('rev-parse', '--verify', '-q', "$ref^{commit}")).Code) {
      foreach ($k in @($script:eEdits.Keys)) { if ((Git-Out $script:eRepo @('merge-base', '--is-ancestor', $k, $ref)).Code -eq 0) { $n++ } }
    }
  } catch { }
  $n
}
function Get-RewriteCount([string]$repo, [string[]]$shas) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($s in $shas) { [void]$set.Add($s); foreach ($x in (Git-Out $repo @('rev-list', '--ancestry-path', "$s..HEAD")).Out) { if ($x) { [void]$set.Add($x) } } }
  $set.Count
}
function Do-EApply([switch]$NoConfirm) {
  try {
    if (Get-EDirty) { try { Sync-EEdit } catch { } }
    if (-not $script:eRepo -or -not $script:eEdits.Count) { return $false }
    $pushed = Get-EPushedEdits; $nE = $script:eEdits.Count
    if ($script:Confirm -and -not $NoConfirm) {
      $rw = Get-RewriteCount $script:eRepo @($script:eEdits.Keys)
      $lines = foreach ($k in @($script:eEdits.Keys)) { $c = Find-ECommit $k; $e = $script:eEdits[$k]; "$($c.Short)  $((@($e.Keys) | Sort-Object) -join ' + ')  $($c.Subject)" }
      $m = "You changed $(Plural $nE 'commit' 'commits'). Git also has to re-save the $($rw - $nE) commit(s) that come after $(if ($nE -eq 1) { 'it' } else { 'them' }), so $rw commit(s) get new IDs.`n`n$($script:G.Dot) Your files are not touched.`n$($script:G.Dot) A backup of the current history is kept: 'Undo last edit' (Ctrl+Z) brings it back.`n$($script:G.Dot) Nothing is sent to GitHub until you publish."
      if ($pushed) { $m += "`n`n$(Plural $pushed 'changed commit is' 'changed commits are') already on GitHub. Afterwards GitHub and your PC disagree until you replace GitHub's version." }
      $r = Ask 'backd8 - apply edits' "Apply $(Plural $nE 'edit' 'edits') to this project?" $m @("Apply $(Plural $nE 'edit' 'edits')", 'Cancel') $(if ($pushed) { 1 } else { 0 }) 'warn' (($lines | Select-Object -First 12) -join "`n")
      if ($r -ne 0) { Add-ELog 'Apply cancelled - your changes are still waiting.'; return $false }
    }
    $ed = @{}; foreach ($k in @($script:eEdits.Keys)) { $ed[$k] = $script:eEdits[$k] }
    $res = Invoke-Bg 'Applying your edits...' { param($r, $e) Set-CommitEdits $r $e } @($script:eRepo, $ed) $true
    $script:eEdits = @{}; $script:eOrig = @{}; $script:eSel = $null; Clear-EDetail
    $out = "Edits applied: $($res.Edited) commit(s) edited, $($res.Rewritten) commit(s) got new hashes.`nNew head: $($res.NewHead.Substring(0, 7)).  Backup: $($res.Backup)`nUse 'Undo last edit' to go back."
    if ($res.SignaturesDropped -gt 0) { $out += "`nNote: $($res.SignaturesDropped) rewritten commit(s) were signed; the new commits are NOT signed (signatures cannot survive a rewrite)." }
    if (@($res.StaleRefs).Count) { $out += "`nNote: these branches/tags still point at the OLD commits (not rewritten): $(@($res.StaleRefs) -join ', '). Move or delete them yourself if they should follow the new history." }
    if ($pushed) { $out += "`nSome rewritten commits were already pushed: GitHub now needs its version replaced." }
    Add-ELog $out
    Do-ELoad $script:eRepo -NoAccess
    if ($script:Confirm -and -not $NoConfirm) {
      $x = "$($res.Rewritten) commit(s) were rewritten ($($res.Edited) edited). Undo is available (Ctrl+Z)."
      if ($res.SignaturesDropped -gt 0) { $x += "`n`n$($res.SignaturesDropped) rewritten commit(s) were signed. The new commits are NOT signed (signatures cannot survive a rewrite)." }
      if (@($res.StaleRefs).Count) { $x += "`n`nThese branches/tags still point at the OLD commits: $(@($res.StaleRefs) -join ', '). Move them yourself if they should follow." }
      if ($pushed) { $x += "`n`nGitHub still has the old commits - publish when you are ready." }
      if ($res.SignaturesDropped -gt 0 -or @($res.StaleRefs).Count) { [void](Ask 'backd8 - done' 'Your edits are applied' $x @('OK') 0 'info') } else { Show-Toast "$(Plural $res.Edited 'edit' 'edits') applied $($script:G.Dot) Undo is available" }
    }
    return $true
  } catch { EFail $_ }
  $false
}
function Do-EUndo([switch]$Force) {
  try {
    if (-not $script:eRepo) { return }
    if ($script:Confirm) {
      $n = $script:eEdits.Count
      $m = "The project goes back to how it was before your last Apply. The re-saved commits are no longer on the branch.`n`n$($script:G.Dot) This uses up the backup (press Undo again to go back one more step).`n$($script:G.Dot) $(if ($n) { "Your $(Plural $n 'waiting change' 'waiting changes') are discarded." } else { 'No waiting changes are lost.' })`n$($script:G.Dot) If the branch changed since the Apply, you will be asked again."
      if ((Ask 'backd8 - undo' "Undo the last edit of '$(Get-RepoLeaf)'?" $m @('Undo it', 'Cancel') 1 'question') -ne 0) { return }
    }
    $msg = $null; $uerr = $null; $repo = $script:eRepo; $fo = [bool]$Force
    try { $msg = Invoke-Bg 'Restoring the previous history...' { param($r, $fo) if ($fo) { Undo-CommitEdits $r -Force } else { Undo-CommitEdits $r } } @($repo, $fo) } catch { $uerr = $_ }
    if ($uerr) {
      if ($uerr.Exception.Message -notlike 'The branch has changed since the last rewrite*') { throw $uerr }
      Add-ELog "Undo refused: $($uerr.Exception.Message)"
      if (-not $script:Confirm) { return }
      $m = "Since the edit the branch changed (new commits, another edit or a reset).`n`nUndoing now moves the branch back and DROPS everything added since. Those newer commits would stay reachable ONLY through git's reflog (git reflog) until git cleans it up - backd8 does not back them up."
      if ((Ask 'backd8 - undo refused' 'Undo anyway and drop the newer commits?' $m @('Undo anyway', 'Cancel') 1 'error' '' -1 0 'I understand the newer commits will be dropped from the branch') -ne 0) { Add-ELog 'Undo cancelled.'; return }
      $msg = Invoke-Bg 'Restoring the previous history...' { param($r) Undo-CommitEdits $r -Force } @($repo)
    }
    $script:eEdits = @{}; $script:eOrig = @{}; $script:eSel = $null; Clear-EDetail
    Add-ELog "$msg"
    Do-ELoad $script:eRepo -NoAccess
    Show-Toast 'Undone - your project is back as it was' 'info'
  } catch { EFail $_ }
}

# ---- GitHub sign-in and push
function Offer-ESignIn([string]$why) {
  if ($script:SignInHook) { return $true }
  if (-not $script:Confirm) { return $false }
  (Ask 'backd8 - sign in to GitHub' $why "Sign in now?`n`nA separate window opens (Git Credential Manager's browser login, the GitHub CLI or an SSH test). backd8 never stores a password or token." @('Sign in...', 'Not now') 0 'question') -eq 0
}
function Do-ESignIn {
  $a = $null
  try {
    if (-not $script:eRepo) { return $null }
    if (-not (Test-GitInstalled)) { throw $script:GitInstallHint }
    $r = $script:eRepo
    if ($script:SignInHook) { Add-ELog 'Signing in to GitHub (test hook)...'; $a = & $script:SignInHook $r }
    elseif ($script:Confirm) { Add-ELog 'Opening the GitHub sign-in window - finish it there, then come back...'; $a = Invoke-Bg 'Waiting for the sign-in window - finish signing in there...' { param($p) Connect-GitHub $p } @($r) $false }
    else { Add-ELog 'Sign-in window skipped (non-interactive mode); only checking access.'; $a = Get-GitHubAccess $r }
    Set-EAccess $a
    if ($script:Confirm -and $a -and $a.CanPush -eq $true) { Show-Toast 'Signed in to GitHub' }
  } catch { EFail $_ }
  $a
}
function Invoke-EPush([bool]$doForce, [bool]$discard, [bool]$retried) {
  $done = $false
  try {
    $r = $script:eRepo; $perr = $null; $out = $null
    try { $out = Invoke-Bg $(if ($doForce) { "Replacing GitHub's version..." } else { 'Publishing to GitHub...' }) { param($p, $fo, $di) if ($fo -and $di) { Push-Repo $p -Force -DiscardRemote } elseif ($fo) { Push-Repo $p -Force } else { Push-Repo $p } } @($r, $doForce, $discard) $true }
    catch { $perr = $_ }
    if (-not $perr) {
      Add-ELog "$out"; $done = $true
      if ($script:eAccess -and $script:eAccess.Transport -ne 'local') { $script:eAccess.CanPush = $true; Update-EAccessLabel }
      Do-ELoad $r -NoAccess
      Show-Toast 'Published to GitHub'
    } else {
      $msg = $perr.Exception.Message
      if ($msg -like 'GitHub sign-in required*') {
        if ($retried) { throw $perr }
        Add-ELog "ERROR: $msg"
        if (Offer-ESignIn 'GitHub did not accept the upload: you are not signed in (or this account may not write to this repository).') {
          $a = Do-ESignIn
          if ($a -and $a.CanPush -eq $true) { Add-ELog 'Signed in - retrying the upload once.'; return (Invoke-EPush $doForce $discard $true) }
          Add-ELog 'Still not signed in - nothing was uploaded.'
        } else { Add-ELog 'Upload cancelled: not signed in.' }
      }
      elseif ($doForce -and -not $discard -and $msg -like '*exist nowhere in this repository*') {
        Add-ELog "ERROR: $msg"
        Do-ELoad $r -NoAccess
        $n = if ($msg -match 'has (\d+) commit') { $Matches[1] } else { '?' }
        if ($script:Confirm) {
          $m = "$n commit(s) on GitHub are in NO branch, tag or backup on this PC - most likely someone else's work.`n`nReplacing GitHub's version DELETES them for good. backd8 cannot bring them back."
          if ((Ask 'backd8 - DELETE COMMITS ON GITHUB' "Delete $n commit(s) from GitHub that you don't have?" $m @("Delete $n commit(s) and replace", 'Cancel, keep them') 1 'error' '' -1 0 "I know these $n commit(s) will be deleted from GitHub") -eq 0) { return (Invoke-EPush $true $true $retried) }
          Add-ELog 'Cancelled: the commits on GitHub were kept.'
        } else { Add-ELog 'Force push refused: the remote has commits that exist nowhere locally.' }
      }
      else { throw $perr }
    }
  } catch { EFail $_ }
  $done
}
function Do-EPush([switch]$Force, [switch]$DiscardRemote) {
  try {
    if (-not $script:eRepo) { return $false }
    $s = Get-PushState $script:eRepo
    if ($script:Confirm -and $script:eEdits.Count) {
      $n = $script:eEdits.Count
      if ((Ask 'backd8 - publish' "$(Plural $n 'waiting change' 'waiting changes') will NOT be published" "Publishing only sends what is already in your project history. Your waiting changes are not applied yet. Press Apply first if you want them on GitHub." @('Publish without them', 'Cancel') 1 'warn') -ne 0) { return $false }
    }
    if ($script:Confirm -and $s.Url -and $script:eAccess -and $script:eAccess.Transport -in 'https', 'ssh' -and $script:eAccess.CanPush -ne $true) {
      Update-EAccess
      if ($script:eAccess -and $script:eAccess.CanPush -eq $false) {
        if (-not (Offer-ESignIn 'This PC is not signed in to GitHub for this project, so publishing would fail.')) { Add-ELog 'Upload cancelled: not signed in.'; return $false }
        $a = Do-ESignIn
        if (-not $a -or $a.CanPush -ne $true) { Add-ELog 'Still not signed in - nothing was uploaded.'; return $false }
      }
    }
    $doForce = $false
    if ($s.Url -and $s.Behind -gt 0) {
      if ($script:Confirm) {
        $m = "GitHub address: $($s.Url)`nBranch: $($s.Branch)  (remote '$($s.Remote)')`n`nGitHub still has an older version of this branch. If you continue:`n$($script:G.Dot) GitHub's $(Plural $s.Behind 'old commit' 'old commits') are REPLACED (deleted there).`n$($script:G.Dot) Your $(Plural $s.Ahead 'commit' 'commits') take their place.`n$($script:G.Dot) Anyone who already copied this branch must download it again.`n$($script:G.Dot) Safety net: GitHub refuses if somebody uploaded after you last looked (force push with lease).`n$($script:G.Dot) Your own backup of the old history stays on this PC (Undo last edit)."
        if ((Ask "backd8 - replace GitHub's version" "Replace GitHub's version of '$($s.Branch)'?" $m @("Replace GitHub's version", 'Cancel') 1 'error' '' -1 0 "I understand GitHub will lose the old version of this branch") -ne 0) { Add-ELog 'Cancelled: GitHub was not changed.'; return $false }
        $doForce = $true
      }
      elseif ($Force) { $doForce = $true }
      else { Add-ELog "Push refused: local branch differs from the remote (ahead $($s.Ahead), behind $($s.Behind)); a force push is needed."; return $false }
    }
    return (Invoke-EPush $doForce ([bool]($DiscardRemote -and -not $script:Confirm)) $false)
  } catch { EFail $_ }
  $false
}

# One click: commit the new files (if a message is written), apply the edits, sign in if needed, publish. Confirms once up front.
function Do-EPublishAll {
  try {
    if (-not $script:eRepo) { return }
    if (Get-EDirty) { try { Sync-EEdit } catch { } }
    $newReady = Get-ENewReady; $nE = $script:eEdits.Count
    if (-not $newReady -and -not $nE) { return }
    $names = @(); if ($newReady) { $names += 'Save your new commit' }; if ($nE) { $names += 'Apply your edits' }; $names += 'Publish to GitHub'
    if ($script:Confirm) {
      $lines = @(); if ($newReady) { $lines += "$($script:G.Dot) 1 new commit with $(Plural (Get-ECheckedFiles).Count 'file' 'files'), dated $(if ($script:nWhen -ne 'now') { Fmt $nPick.Value } else { 'now' })" }
      if ($nE) { $lines += "$($script:G.Dot) $(Plural $nE 'edited commit' 'edited commits') (every later commit gets a new ID; a backup is kept)" }
      $lines += "$($script:G.Dot) Publish to $($script:ePush.Url)"
      if ($script:ePush.Behind -gt 0 -or $nE) { $lines += "`nIf GitHub already has the old version of an edited commit, you will be asked once more before it is replaced." }
      if ((Ask 'backd8 - save and publish' 'Save everything and publish to GitHub?' ($lines -join "`n") @('Save & publish', 'Cancel') 0 'question') -ne 0) { Add-ELog 'Cancelled.'; return }
    }
    Start-ERun $names; $i = 0
    try {
      if ($newReady) { Set-ERunStep $i 'run'; if (-not (Do-ENewCommit)) { Set-ERunStep $i 'fail'; return }; Set-ERunStep $i 'ok'; $i++ }
      if ($nE) { Set-ERunStep $i 'run'; if (-not (Do-EApply -NoConfirm)) { Set-ERunStep $i 'fail'; return }; Set-ERunStep $i 'ok'; $i++ }
      Set-ERunStep $i 'run'
      if (Do-EPush) { Set-ERunStep $i 'ok' } else { Set-ERunStep $i 'fail'; Add-ELog 'Not published. Your commits and edits are saved on this PC; press the publish button when ready.' }
      if ($script:Confirm) { Start-Sleep -Milliseconds 700 }
    } finally { Stop-ERun }
  } catch { EFail $_; Stop-ERun }
}
function Invoke-ENext {
  switch ($script:eNext.Role) {
    'commit' { [void](Do-ENewCommit) }
    'apply' { [void](Do-EApply) }
    'signin' { [void](Do-ESignIn) }
    'push' { [void](Do-EPush) }
    'force' { [void](Do-EPush) }
  }
}
#endregion


#region Advanced: the optional global auto-backdate hook (old model) - NOT part of the main flow
$script:AdvXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="adv" Title="backd8 - Advanced: auto-backdate new commits" Width="860" Height="680" MinWidth="760" MinHeight="560" Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="True" WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
 <Border Padding="26,22,26,22"><Grid x:Name="advRoot">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Border Grid.Row="0" Background="{DynamicResource WarnBg}" CornerRadius="12" Padding="18,14" Margin="0,0,0,14">
   <StackPanel Orientation="Horizontal"><TextBlock x:Name="aWarnIcon" Style="{DynamicResource Glyph}" FontSize="22" Foreground="{DynamicResource WarnFg}" VerticalAlignment="Top" Margin="0,2,16,0"/>
    <StackPanel MaxWidth="720"><TextBlock Text="Optional extra - you do NOT need this to edit commits or publish" FontWeight="SemiBold" FontSize="15" Foreground="{DynamicResource WarnFg}"/>
     <TextBlock Text="Auto-backdating gives EVERY new commit you make on this PC (in any program, in any project) a made-up date while it is ON, starting at a date you choose and moving 1 to 6 hours forward per commit. Leave it off unless you really want that." TextWrapping="Wrap" Foreground="{DynamicResource WarnFg}" Margin="0,4,0,0" LineHeight="20"/></StackPanel></StackPanel></Border>
  <Border Grid.Row="1" Style="{DynamicResource CardStyle}" Padding="20,14" Margin="0,0,0,14"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBlock x:Name="aStatus" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
   <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="aInstall" Content="Install on this PC" Style="{DynamicResource Btn}"/><Button x:Name="aToggle" Content="Turn ON" Style="{DynamicResource Btn}" Margin="0"/></StackPanel></Grid></Border>
  <Border Grid.Row="2" Style="{DynamicResource CardStyle}" Padding="20,14" Margin="0,0,0,14"><StackPanel>
   <TextBlock Text="First date for new commits in projects that are not listed below" FontWeight="SemiBold" Margin="0,0,0,8"/>
   <StackPanel Orientation="Horizontal"><StackPanel x:Name="aDefHost" Margin="0,0,10,0"/><Button x:Name="aSave" Content="Save date" Style="{DynamicResource Btn}" VerticalAlignment="Top"/><TextBlock x:Name="aSaved" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="4,0,0,0"/></StackPanel></StackPanel></Border>
  <Border Grid.Row="3" Style="{DynamicResource CardStyle}" Padding="20,16"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
   <TextBlock Text="Projects with their own date (each has its own clock)" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,10"/>
   <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8"><Button x:Name="aAdd" Content="Add a project..." Style="{DynamicResource Btn}"/><Button x:Name="aUpd" Content="Change date..." Style="{DynamicResource Btn}"/><Button x:Name="aRem" Content="Remove" Style="{DynamicResource Btn}"/></StackPanel>
   <Grid Grid.Row="2"><ListBox x:Name="aList" BorderThickness="0" Background="Transparent" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/><TextBlock x:Name="aEmpty" Text="No project has its own date. Every project uses the date above." Foreground="{DynamicResource Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/></Grid></Grid></Border>
  <Button x:Name="aClose" Grid.Row="4" Content="Close" Style="{DynamicResource Btn}" HorizontalAlignment="Right" Margin="0,14,0,0" IsCancel="True" MinWidth="110"/>
 </Grid></Border>
</Window>
'@
$af = [Windows.Markup.XamlReader]::Parse($script:AdvXaml)
foreach ($m in [regex]::Matches($script:AdvXaml, 'x:Name="(\w+)"')) { $n = $m.Groups[1].Value; Set-Variable -Name $n -Value ($af.FindName($n)) -Scope Script }
$aWarnIcon.Text = $script:I.Warn
$pDef = New-Dt (Get-Date).AddYears(-1); $aDefHost.Children.Add($pDef.Panel) | Out-Null
$bInstall = $aInstall; $bToggle = $aToggle; $bDef = $aSave; $bAdd = $aAdd; $bUpd = $aUpd; $bRem = $aRem; $lv = $aList
Tip $bInstall "Sets git's global core.hooksPath to backd8's hooks folder so a small script can re-date each new commit."

$script:ovCache = $null; $script:ovAt = [datetime]::MinValue
function Get-OverridesCached {
  if (((Get-Date) - $script:ovAt).TotalSeconds -gt 20) { try { $script:ovCache = @(Get-HookOverrides | ForEach-Object { Norm $_.Path }) } catch { $script:ovCache = @() }; $script:ovAt = Get-Date }
  $script:ovCache
}
function Show-Path([string]$p) {
  $x = $p -replace '/', '\'; if ($x -match '^[a-z]:') { $x = $x.Substring(0, 1).ToUpper() + $x.Substring(1) }
  try {                                                  # config.json stores lower-case paths: show the real spelling when the folder exists
    if (Test-Path -LiteralPath $x -PathType Container) {
      $parts = $x.Split('\'); $cur = $parts[0].ToUpper() + '\'
      for ($i = 1; $i -lt $parts.Count; $i++) { if (-not $parts[$i]) { continue }; $m = @([IO.Directory]::GetFileSystemEntries($cur, $parts[$i])); if ($m.Count) { $cur = Join-Path $cur (Split-Path $m[0] -Leaf) } else { $cur = Join-Path $cur $parts[$i] } }
      return $cur
    }
  } catch {}
  $x
}
function Refresh-Adv {
  $s = Get-Status; $c = $s.Config; $G = $script:G; $script:mOn = $s.Enabled
  $hasDate = [bool]($c.default.start -or (@($c.repos) | Where-Object { $_.start }))
  $aStatus.Text = if ($s.Enabled) { "$($G.Warn)  Auto-backdating is ON" } elseif ($s.Installed) { "$($G.Ok)  Installed, currently OFF" } else { "$($G.Off)  Not installed" }
  SetRes $aStatus ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($s.Enabled) { 'ErrFg' } else { 'Text' })
  $bInstall.Content = if ($s.Installed) { 'Uninstall' } else { 'Install on this PC' }
  $bToggle.Content = if ($s.Enabled) { 'Turn OFF' } else { 'Turn ON' }; $bToggle.IsEnabled = [bool]($s.Installed -and $hasDate)
  Set-Kind $bInstall 'normal'; Set-Kind $bToggle $(if ($s.Enabled) { 'primary' } else { 'normal' })
  Tip $bToggle $(if (-not $s.Installed) { 'Install first.' } elseif (-not $hasDate) { 'Save a date first.' } elseif ($s.Enabled) { 'Stop re-dating new commits.' } else { 'Start re-dating EVERY new commit on this PC (you confirm first).' })
  $saved = if ($c.default.start) { [datetime]$c.default.start } else { $null }
  if ($saved -and -not $script:pDefInit) { $script:pDefInit = $true; $pDef.Value = if ($saved -gt (Get-Date)) { Get-Date } else { $saved } }
  $dirty = $saved -and ($pDef.Value -ne [datetime]::MinValue) -and ([math]::Abs(($pDef.Value - $saved).TotalMinutes) -ge 1)
  $aSaved.Text = if (-not $saved) { 'Not saved yet.' } elseif ($dirty) { "Saved: $(Fmt $saved) - you changed it, press Save date" } else { "$($G.Ok) Saved: $(Fmt $saved)" }
  $sel = if ($lv.SelectedItem) { [string]$lv.SelectedItem.Tag } else { $null }
  $ov = if ($s.Installed) { @(Get-OverridesCached) } else { @() }
  $lv.Items.Clear()
  foreach ($r in @($c.repos)) {
    $full = Show-Path $r.path; $leaf = Split-Path $full -Leaf; $par = Split-Path $full -Parent
    $note = ''
    if (-not (Test-Path -LiteralPath $r.path -PathType Container)) { $note = "$($G.Warn) Folder not found" }
    elseif ($ov -contains (Norm $r.path)) { $note = "$($G.Warn) Own hooks setting: not backdated" }
    elseif ($r.next -and ([datetime]$r.next) -gt (Get-Date)) { $note = "$($G.Ok) Caught up with today" }
    $g = New-Object Windows.Controls.Grid
    foreach ($w in @(0, 0)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength(1, 'Star'); $g.ColumnDefinitions.Add($cd) }
    $l = New-Object Windows.Controls.StackPanel; $l.Children.Add((New-Tb $leaf 14 'Text' 'SemiBold' $false)) | Out-Null; $l.Children.Add((New-Tb $par 12 'Muted' 'Normal' $false)) | Out-Null
    $rt = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($rt, 1)
    $rt.Children.Add((New-Tb "First date $(Fmt ([datetime]$r.start))   $($G.Arrow)   next commit gets $(if ($r.next) { Fmt ([datetime]$r.next) } else { 'the first date' })" 12.5 'Text' 'Normal' $false)) | Out-Null
    if ($note) { $rt.Children.Add((New-Tb $note 12.5 'WarnFg' 'SemiBold' $false)) | Out-Null }
    $g.Children.Add($l) | Out-Null; $g.Children.Add($rt) | Out-Null
    $it = New-Object Windows.Controls.ListBoxItem; $it.Content = $g; $it.Tag = $r.path; $it.Style = $script:Res['RowItem']; $it.ToolTip = $full
    [void]$lv.Items.Add($it); if ($sel -and (Norm $r.path) -eq (Norm $sel)) { $it.IsSelected = $true }
  }
  $aEmpty.Visibility = Vis ($lv.Items.Count -eq 0); $bUpd.IsEnabled = $bRem.IsEnabled = [bool]$lv.SelectedItem
}
function Refresh { Refresh-Adv; Update-EBanners; $f.Title = $(if ($script:mOn) { 'backd8 - auto-backdating is ON for this PC' } else { 'backd8 - fix your commits and publish to GitHub' }) }

function Get-DateFromUser([string]$title, [string]$prompt, [datetime]$initial) {
  if (-not $script:Confirm -and -not $script:AskCapture) { return $initial }
  $w = New-Object Windows.Window; $w.Title = $title; $w.SizeToContent = 'Height'; $w.Width = 520; $w.ResizeMode = 'NoResize'; $w.WindowStartupLocation = 'CenterOwner'; $w.ShowInTaskbar = $false
  $w.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI'); $w.FontSize = 13; SetRes $w ([Windows.Window]::BackgroundProperty) 'Bg'
  if ($script:ActiveOwner -and $script:ActiveOwner.IsVisible) { $w.Owner = $script:ActiveOwner }
  $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '26,22,26,20'
  $sp.Children.Add((New-Tb $prompt 15 'Text' 'SemiBold')) | Out-Null
  $dt = New-Dt $initial; $dt.Panel.Margin = '0,16,0,0'; $sp.Children.Add($dt.Panel) | Out-Null
  $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.HorizontalAlignment = 'Right'; $r.Margin = '0,22,0,0'
  $ok = New-Button 'Save date' 'primary' 110; $ca = New-Button 'Cancel' 'normal' 100; $ca.Margin = '0'; $ca.IsCancel = $true; $ok.IsDefault = $true
  $script:dtResult = $null; $script:dtField = $dt; $script:dtWin = $w
  $ok.Add_Click({ if ($script:dtField.Value -ne [datetime]::MinValue) { $script:dtResult = $script:dtField.Value; $script:dtWin.DialogResult = $true } })
  $r.Children.Add($ok) | Out-Null; $r.Children.Add($ca) | Out-Null; $sp.Children.Add($r) | Out-Null; $wrap = New-Object Windows.Controls.Grid; $wrap.Children.Add($sp) | Out-Null; $w.Content = $wrap
  if ($script:AskCapture) { $null = & $script:AskCapture $w 0 1; return $null }
  [void]$w.ShowDialog(); $script:dtResult
}
function Do-Install {
  try {
    if ((Get-Status).Installed) { [void](Uninstall-Hooks) }
    else {
      try { Install-Hooks } catch {
        if ($script:Confirm -and $_.Exception.Message -like '*already set*') {
          $cur = Get-HooksPath
          $r = Ask 'backd8 - install' 'Another git hooks folder is already set up' ("Git on this PC already runs hooks from:`n$cur`n`nIf backd8 replaces it, those hooks stop running in EVERY repository.`n`nbackd8 cannot put the old folder back for you. To restore it later, run:`ngit config --global core.hooksPath `"$cur`"") @('Replace it', 'Keep it, do nothing') 1 'warn' $cur
          if ($r -eq 0) { Install-Hooks -Force }
        }
        elseif ($_.Exception.Message -like '*already set*') { Install-Hooks -Force }
        else { throw }
      }
    }
  } catch { Fail $_ }; Refresh
}
function Do-Toggle {
  try {
    $on = -not (Get-Status).Enabled
    if ($on) {
      $c = Get-Config; $dirty = (-not $c.default.start) -or ([math]::Abs(($pDef.Value - [datetime]$c.default.start).TotalMinutes) -ge 1)
      if ($dirty -and $script:Confirm -and $pDef.Valid) { Set-StartDate '*' $pDef.Value }
      $c = Get-Config; $own = @($c.repos).Count
      $first = if ($c.default.start) { Fmt ([datetime]$c.default.start) } else { 'set per project' }
      if ($script:Confirm) {
        $body = "From now on, EVERY commit you make on this PC - in any project, with any program (git, VS Code, GitHub Desktop...) - is given a made-up date:`n`n  $($script:G.Dot) first commit: $first, then +1 to 6 hours for each next commit`n  $($script:G.Dot) $(Plural $own 'project has' 'projects have') their own start date`n`nCommits you already made are not changed. You can turn it OFF here at any time. (This does not affect the main backd8 window.)"
        if ((Ask 'backd8 - turn ON' 'Turn auto-backdating ON for the whole PC?' $body @('Turn ON', 'Cancel') 1 'warn') -ne 0) { return }
      }
    }
    Set-Enabled $on
  } catch { Fail $_ }; Refresh
}
function Do-Default { try { if (-not $pDef.Valid) { throw 'Start date must be in the past. Type it like 2025-03-01 and the time like 09:30.' }; Set-StartDate '*' $pDef.Value } catch { Fail $_ }; Refresh }
function Do-Add([string]$path) {
  try {
    if (-not $path) { $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose the project folder'; if ($d.ShowDialog() -ne 'OK') { return }; $path = $d.SelectedPath }
    $root = Get-RepoRoot $path
    $init = if ((Get-Config).default.start) { [datetime](Get-Config).default.start } else { $pDef.Value }
    $when = Get-DateFromUser 'backd8 - start date' "First date for new commits in '$(Split-Path $root -Leaf)'" $init
    if ($null -eq $when) { return }
    Set-StartDate $root $when
  } catch { Fail $_ }; Refresh
}
function Sel([string]$p) { if ($p) { $p } elseif ($lv.SelectedItem) { [string]$lv.SelectedItem.Tag } }
function Do-Update([string]$path) {
  $p = Sel $path; if (-not $p) { return }
  try {
    $cur = (Get-Config).repos | Where-Object { (Norm $_.path) -eq (Norm $p) } | Select-Object -First 1
    $when = Get-DateFromUser 'backd8 - start date' "New first date for '$(Split-Path (Show-Path $p) -Leaf)'" $(if ($cur) { [datetime]$cur.start } else { $pDef.Value })
    if ($null -eq $when) { return }
    Set-StartDate $p $when
  } catch { Fail $_ }; Refresh
}
function Do-Remove([string]$path) {
  $p = Sel $path; if (-not $p) { return }
  try {
    if ($script:Confirm) {
      $nm = Split-Path (Show-Path $p) -Leaf
      if ((Ask 'backd8 - remove' "Remove '$nm' from this list?" "Its commits are not changed. New commits there will use the date above instead.`n`n$(Show-Path $p)" @('Remove from list', 'Cancel') 1 'question') -ne 0) { return }
    }
    Remove-Repo $p
  } catch { Fail $_ }; Refresh
}
function Do-HookRemove {
  try {
    if ($script:Confirm -and (Ask 'backd8 - remove auto-backdating' 'Remove auto-backdating from this PC?' "It stops changing the dates of new commits you make in other programs. Commits you already made are not changed. You can install it again from Advanced." @('Remove it', 'Cancel') 1 'question') -ne 0) { return }
    [void](Uninstall-Hooks); Add-ELog 'Removed auto-backdating from git.'; if ($script:Confirm) { Show-Toast 'Auto-backdating removed' }
  } catch { Fail $_ }; Refresh
}
$bInstall.Add_Click({ Do-Install }); $bToggle.Add_Click({ Do-Toggle }); $bDef.Add_Click({ Do-Default })
$bAdd.Add_Click({ Do-Add }); $bUpd.Add_Click({ Do-Update }); $bRem.Add_Click({ Do-Remove })
$lv.Add_SelectionChanged({ $bUpd.IsEnabled = $bRem.IsEnabled = [bool]$lv.SelectedItem })
$lv.Add_MouseDoubleClick({ Do-Update })
$lv.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Delete') { Do-Remove } elseif ($e.Key -eq 'Return') { Do-Update } })
$pDef.Date.Add_TextChanged({ if ($script:pDefInit) { Refresh-Adv } }); $pDef.Time.Add_TextChanged({ if ($script:pDefInit) { Refresh-Adv } })
function Show-Advanced { try { Refresh; $af.Owner = $f; $script:ActiveOwner = $af; [void]$af.ShowDialog() } catch { Fail $_ } finally { $script:ActiveOwner = $f; Update-EBanners } }
$af.Add_Closing({ param($s, $e) $e.Cancel = $true; $s.Hide(); $script:ActiveOwner = $f })
#endregion


#region events, keyboard, startup
function New-AppIcon([bool]$on) {
  $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
  $col = if ($on) { Hex '#C42B1C' } else { Hex '#005FB8' }
  $dc.DrawRoundedRectangle((New-Object Windows.Media.SolidColorBrush($col)), $null, (New-Object Windows.Rect(2, 2, 60, 60)), 14, 14)
  $ft = New-Object Windows.Media.FormattedText($(if ($on) { '!' } else { 'b8' }), [Globalization.CultureInfo]::InvariantCulture, 'LeftToRight', (New-Object Windows.Media.Typeface('Segoe UI')), 30, [Windows.Media.Brushes]::White)
  $dc.DrawText($ft, (New-Object Windows.Point((64 - $ft.Width) / 2, (64 - $ft.Height) / 2))); $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap(64, 64, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($dv); $rtb.Freeze(); $rtb
}
try { $f.Icon = New-AppIcon $false; $af.Icon = $f.Icon } catch { }
function Show-Help {
  $body = "1. Choose the folder of your project (Browse, paste the path, or drop the folder on this window).`n`n2. Change what you want:`n   $($script:G.Dot) 'New commit' (top of the history) saves the files you changed - give it any date you like.`n   $($script:G.Dot) Click an older commit to change its message or date. Select several to re-date them together.`n`n3. Publish. The big button always shows the next step: Commit, Apply my edits, Sign in, Push - or 'Save & publish' to do it all at once.`n`nNothing is sent to GitHub until you press the publish button. Every edit keeps a backup (Undo last edit, Ctrl+Z).`n`nKeys: Enter = the highlighted button, F5 = reload, Ctrl+F = search, Ctrl+Z = undo last edit, Alt + underlined letter = press a button."
  [void](Ask 'backd8 - how it works' 'How backd8 works' $body @('Close') 0 'info')
}
$btnBrowse.Add_Click({ Do-EBrowse }); $btnEmptyBrowse.Add_Click({ Do-EBrowse })
$bInit.Add_Click({ Do-EInit }); $bInitNew.Add_Click({ Open-Url 'https://github.com/new' }); $bNewRepo.Add_Click({ Open-Url 'https://github.com/new' }); $bLink.Add_Click({ Do-EConnect })
$bGitHelp.Add_Click({ if ($script:Confirm) { if ((Ask 'backd8 - install Git' 'Install Git for Windows' "Git is the free tool that stores your project history. Install it once:`n`n$($script:G.Dot) Easiest: open a terminal and run:  winget install --id Git.Git -e`n$($script:G.Dot) Or download the installer from git-scm.com/download/win`n`nThen close and reopen backd8." @('Open the download page', 'Close') 1 'info') -eq 0) { Open-Url 'https://git-scm.com/download/win' } } })
$bSaveId.Add_Click({ Do-SaveIdentity }); $bHookRemove.Add_Click({ Do-HookRemove })
$bHookKeep.Add_Click({ if ((Get-Status).Enabled) { $script:hookOnKeep = $true } else { $script:hookKeepSession = $true; Set-UiValue 'hookNoticeDismissed' $true }; Update-EBanners })
$btnAdv.Add_Click({ Show-Advanced }); $btnHelp.Add_Click({ Show-Help })
$btnRecent.Add_Click({
  $cm = New-Object Windows.Controls.ContextMenu; $u = Load-Ui; $seen = @{}
  foreach ($p in @(@($u.recent) + @((Get-Config).repos | ForEach-Object { Show-Path $_.path }))) { if ($p -and -not $seen.ContainsKey((Norm $p))) { $seen[(Norm $p)] = 1; $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $p; $mi.Tag = $p; $mi.Add_Click({ Open-Folder ([string]$this.Tag) }); [void]$cm.Items.Add($mi) } }
  if (-not $cm.Items.Count) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = 'No recent folders yet'; $mi.IsEnabled = $false; [void]$cm.Items.Add($mi) }
  $cm.PlacementTarget = $btnRecent; $cm.Placement = 'Bottom'; $cm.IsOpen = $true
})
$lbHist.Add_SelectionChanged({ if (-not $script:eFilling) { Do-ESelect } })
$lbHist.Add_MouseDoubleClick({ if ($script:eView -eq 'commit') { [void]$eMsg.Focus() } elseif ($script:eView -eq 'new') { [void]$nMsg.Focus() } })
function Set-Sort([string]$col) { if ($script:eSort -and $script:eSort.Col -eq $col) { if ($script:eSort.Desc) { $script:eSort = @{ Col = $col; Desc = $false } } else { $script:eSort = $null } } else { $script:eSort = @{ Col = $col; Desc = $true } }; Fill-EList }
$hSortDate.Add_Click({ Set-Sort 'date' }); $hSortMsg.Add_Click({ Set-Sort 'msg' }); $hSortId.Add_Click({ Set-Sort 'id' })
function Copy-ESelected([bool]$withTitle) {
  $lines = foreach ($it in $lbHist.SelectedItems) { $c = Find-ECommit ([string]$it.Tag); if ($c) { if ($withTitle) { "$($c.Sha) $($c.Subject)" } else { $c.Sha } } }
  if ($lines) { try { [Windows.Clipboard]::SetText(($lines -join "`r`n")); Add-ELog "Copied $(Plural @($lines).Count 'commit ID' 'commit IDs') to the clipboard."; Show-Toast 'Copied to the clipboard' 'info' } catch { } }
}
$cm = New-Object Windows.Controls.ContextMenu
foreach ($spec in @(@('Copy commit ID', { Copy-ESelected $false }), @('Copy ID and message', { Copy-ESelected $true }), @('Revert my edit of this commit', { Do-EDiscard }))) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $spec[0]; $mi.Add_Click($spec[1]); [void]$cm.Items.Add($mi) }
$lbHist.ContextMenu = $cm
$nAll.Add_Click({ foreach ($i in $script:FileRows) { $i.Box.IsChecked = $true; $script:eChecks[$i.Path] = $true }; Update-EUi })
$nNone.Add_Click({ foreach ($i in $script:FileRows) { $i.Box.IsChecked = $false; $script:eChecks[$i.Path] = $false }; Update-EUi })
$nMsg.Add_TextChanged({ Update-EUi })
foreach ($k in $script:WhenBtns.Keys) { $script:WhenBtns[$k].Add_Click({ Set-NewWhen ([string]$this.Tag) }) }
$nPick.Date.Add_TextChanged({ Update-EUi }); $nPick.Time.Add_TextChanged({ Update-EUi })
$nBtn.Add_Click({ [void](Do-ENewCommit) })
$eMsg.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } })
$ePick.Date.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } }); $ePick.Time.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } })
$eSave.Add_Click({ Do-EStage }); $eDisc.Add_Click({ Do-EDiscard })
$mPick.Date.Add_TextChanged({ Update-EMulti }); $mPick.Time.Add_TextChanged({ Update-EMulti }); $mBtn.Add_Click({ Do-ESpread })
$tbFind.Add_TextChanged({ if ($script:eRepo) { Fill-EList } })
$btnPrimary.Add_Click({ Invoke-ENext }); $btnAll.Add_Click({ Do-EPublishAll }); $btnSign.Add_Click({ [void](Do-ESignIn) })
$lnkUndo.Add_Click({ if ($lnkUndo.IsEnabled) { Do-EUndo } })
$lnkDetails.Add_Click({ $show = ($logCard.Visibility -ne 'Visible'); $logCard.Visibility = Vis $show; $lnkDetails.Content = $(if ($show) { 'Hide details' } else { 'Show details' }) })
Tip $tbPath 'Folder of your project (any folder inside it works). Press Enter to open it.'; Tip $btnBrowse 'Choose the project folder in a folder dialog. You can also drop a folder on this window.'; Tip $tbFind 'Type part of a message, author, date or commit ID (Ctrl+F).'
Tip $lbHist 'Hover a row for the full message. Select several commits to re-date them together. Ctrl+C copies commit IDs. Right-click for more.'; Tip $eAcc 'Whether this PC may push to the remote (checked with a harmless dry run when the project is opened).'
Tip $btnSign "Check whether this PC may push to this repository, and sign in if not. Opens the sign-in in a separate window (browser, GitHub CLI or an SSH test). backd8 itself never stores a password or token."
Tip $nMsg 'A short sentence about what you changed, e.g. "Add login page". The first line is the title.'; Tip $eMsg 'Change the message here, then press Save change. A change is kept if you click another commit.'
Acc $tbPath 'Project folder' 'Folder of your project. Press Enter to open it, or drop a folder on the window.'; Acc $btnBrowse 'Browse for a project folder'; Acc $tbFind 'Find commits'; Acc $lbHist 'Your project history'
Acc $eMsg 'Commit message'; Acc $btnPrimary 'Next step'; Acc $btnAll 'Save everything and publish to GitHub'; Acc $eLog 'Activity log'; Acc $nMsg 'Message for the new commit'; Acc $tbInit 'GitHub address'; Acc $fLink.Box 'GitHub address'

$f.Add_PreviewKeyDown({ param($s, $e)
  if ($script:eBusy) { return }
  $ac = [Windows.Input.Keyboard]::FocusedElement; $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
  $isText = ($ac -is [Windows.Controls.TextBox])
  if ($e.Key -eq 'F5') { if ($script:eRepo) { Do-ELoad $script:eRepo } elseif ($script:ePlain) { Open-Folder $script:ePlain }; $e.Handled = $true }
  elseif ($e.Key -eq 'F1') { Show-Help; $e.Handled = $true }
  elseif ($ctrl -and $e.Key -eq 'F') { if ($tbFind.IsEnabled) { [void]$tbFind.Focus(); $tbFind.SelectAll() }; $e.Handled = $true }
  elseif ($ctrl -and $e.Key -eq 'Z' -and -not $isText) { if ($lnkUndo.IsEnabled) { Do-EUndo }; $e.Handled = $true }
  elseif ($e.Key -eq 'Escape') { if ($ac -eq $tbFind -and $tbFind.Text) { $tbFind.Clear(); $e.Handled = $true } }
  elseif ($e.Key -eq 'Return') {
    if ($ctrl -and $script:ePrimaryBtn) { $script:ePrimaryBtn.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))); $e.Handled = $true; return }
    if ($ac -eq $tbPath) { Open-Folder $tbPath.Text; $e.Handled = $true }
    elseif ($ac -eq $tbInit) { Do-EInit; $e.Handled = $true }
    elseif ($ac -eq $tbLink) { Do-EConnect; $e.Handled = $true }
    elseif ($ac -eq $tbName -or $ac -eq $tbMail) { Do-SaveIdentity; $e.Handled = $true }
    elseif ($ac -is [Windows.Controls.ListBoxItem]) { if ($script:eView -eq 'commit') { [void]$eMsg.Focus() } elseif ($script:eView -eq 'new') { [void]$nMsg.Focus() }; $e.Handled = $true }
    elseif (-not $isText -and $ac -isnot [Windows.Controls.Primitives.ButtonBase] -and $script:ePrimaryBtn) { $script:ePrimaryBtn.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))); $e.Handled = $true }
  }
})
$f.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e.Effects = 'Copy' } else { $e.Effects = 'None' }; $e.Handled = $true })
$f.Add_Drop({ param($s, $e) foreach ($p in @($e.Data.GetData([Windows.DataFormats]::FileDrop))) { $d = if (Test-Path -LiteralPath $p -PathType Container) { $p } else { Split-Path $p -Parent }; if ($d) { $tbPath.Text = $d; Open-Folder $d; break } } })
$f.Add_Activated({ if (-not $script:eBusy -and $script:Confirm) { Update-EBanners } })
$f.Add_Closing({
  param($sender, $ev)
  if ($script:eBusy) { $ev.Cancel = $true; return }
  if ($script:Confirm) {
    if (Get-EDirty) { try { Sync-EEdit } catch { } }
    $pend = Get-EPendingNote
    if ($pend -and (Ask 'backd8 - close' 'Close and lose unsaved work?' "You have $pend that are not saved into git yet. They are lost if you close." @('Discard and close', 'Keep working') 1 'warn') -ne 0) { $ev.Cancel = $true; return }
    $on = $false; try { $on = (Get-Status).Enabled } catch {}
    if ($on) {
      $r = Ask 'backd8 - auto-backdating is ON' 'Auto-backdating is still ON for this PC' "Every new commit you make anywhere on this PC keeps getting a made-up date until you turn it off." @('Turn it OFF and close', 'Keep it ON and close', 'Cancel') 0 'warn' '' 2
      if ($r -eq 2) { $ev.Cancel = $true; return }
      if ($r -eq 0) { try { Set-Enabled $false } catch { } }
    }
    Save-Ui $f 'main'
  }
})
Restore-Bounds $f 'main'
Set-NewWhen 'now'
Reset-ELoaded
#endregion

function Test-Editor([string]$repo) {
  function Role { (Get-ENext).Role }
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-editor FAILED: $what" } }
  function Head([string]$p, [string]$ref = 'HEAD') { (Git-Out $p @('rev-parse', $ref)).Out[0] }

  # invalid folders are reported, not fatal
  $threw = $false; try { Do-ELoad (Join-Path $env:TEMP 'backd8-no-such-folder') } catch { $threw = $true }
  Check $threw 'loading a missing folder should fail'
  Check ((Role) -eq 'none' -and $script:eView -eq 'none') 'nothing is actionable with nothing loaded'

  Do-EBrowse $repo
  Check ($script:eRepo -and $script:eCommits.Count -ge 3) 'repo loaded with >= 3 commits'
  Check ($script:ePush -and $script:ePush.Url) 'push state has a remote url'
  $branch = $script:ePush.Branch; $remote = $script:ePush.Remote
  $bare = (Git-Out $repo @('remote', 'get-url', $remote)).Out[0]
  Check ($lbHist.Items.Count -eq $script:eCommits.Count) 'list shows all commits'
  Check ($script:eAccess -and $script:eAccess.Transport -eq 'local' -and $eAcc.Text -like '*local remote*') "access status line says local remote (got '$($eAcc.Text)')"
  Check ($eSign.IsEnabled -and $eSign.ToolTip -and $eAcc.ToolTip) 'sign-in button enabled and has tooltips'
  $script:SignInHook = { param($p) $script:hookCalls++; [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $true; Advice = @() } }
  $script:hookCalls = 0; $a = Do-ESignIn; $script:SignInHook = $null
  Check ($script:hookCalls -eq 1 -and $a.CanPush -eq $true -and $eAcc.Text -like '*signed in*') 'sign-in button uses the hook and updates the status line'
  $a = Do-ESignIn
  Check ($a.Transport -eq 'local' -and $eAcc.Text -like '*local remote*') 'sign-in without hook in self-test only re-checks (opens nothing)'
  Check ((Role) -ne 'apply' -and -not $eDisc.IsEnabled) 'Apply/Discard disabled with nothing staged'

  # make sure the remote has the branch first
  if ($null -eq $script:ePush.Ahead -or $script:ePush.Ahead -gt 0) { Check (Do-EPush) 'initial push should work' }
  Check ($script:ePush.Ahead -eq 0 -and $script:ePush.Behind -eq 0) 'in sync after initial push'
  Check ((Info-Text) -like '*In sync*' -and (Role) -eq 'none') 'info says in sync, nothing to do'
  $startHead = Head $repo; $n = $script:eCommits.Count; $mid = [int][math]::Floor($n / 2)
  $cMid = $script:eCommits[$mid]; $cTop = $script:eCommits[0]; $cOld = $script:eCommits[$n - 1]
  $origOldSha = $cOld.Sha; $backups0 = @(Get-Backups $repo).Count

  # stage: message on a middle commit
  Do-ESelect $cMid.Sha
  Check (($eMsg.Text -replace "`r`n", "`n").TrimEnd() -eq (Get-CommitMessage $repo $cMid.Sha)) 'detail shows the original message'
  Check ($script:eView -eq 'commit' -and -not $eDisc.IsEnabled) 'commit view shown, Revert disabled'
  Do-EStage
  Check ($script:eEdits.Count -eq 0) 'unchanged commit stages nothing'
  $eMsg.Text = "Edited by selftest`r`nsecond line"; Do-EStage
  Check ($script:eEdits.Count -eq 1 -and $script:eEdits[$cMid.Sha].message -like "Edited by selftest`nsecond line" -and -not $script:eEdits[$cMid.Sha].ContainsKey('date')) 'message-only edit staged'
  Check ((Role) -eq 'apply' -and $eDisc.IsEnabled -and $ePrimary.Content -like '*Apply my 1 edit*') 'Apply/Revert enabled after saving a change'
  $item = $script:RowMap[$cMid.Sha]
  Check ($item.Mark.Text -eq $script:I.Edit -and $item.Subj.Text -eq 'Edited by selftest') 'list marks the staged edit with the new subject'
  # stage: date on another commit
  $newDate = (Get-Date).AddDays(-400); $newDate = $newDate.AddMilliseconds(-$newDate.Millisecond)
  Do-ESelect $cTop.Sha; $ePick.Value = $newDate; Do-EStage
  Check ($script:eEdits.Count -eq 2 -and $script:eEdits[$cTop.Sha].date -and -not $script:eEdits[$cTop.Sha].ContainsKey('message')) 'date-only edit staged'
  # discard works, empty message is refused
  Do-ESelect $cOld.Sha; $eMsg.Text = 'temp'; Do-EStage
  Check ($script:eEdits.ContainsKey($cOld.Sha)) 'third edit staged'
  Do-EDiscard
  Check (-not $script:eEdits.ContainsKey($cOld.Sha) -and $script:eEdits.Count -eq 2) 'discard removes the staged edit'
  Do-ESelect $cTop.Sha; $eMsg.Text = '   '; $threw = $false; try { Do-EStage } catch { $threw = $true }
  Check ($threw -and $script:eEdits.Count -eq 2) 'empty message refused'
  Do-ESelect $cTop.Sha
  $subjects = @($script:eCommits | ForEach-Object { $_.Subject })

  # apply (a tag on the top commit must be reported as still pointing at the old history)
  [void](Git-Out $repo @('tag', 'selftest-stale', $cTop.Sha))
  [void](Do-EApply)
  [void](Git-Out $repo @('tag', '-d', 'selftest-stale'))
  Check ($eLog.Text -like '*still point at the OLD commits*selftest-stale*') 'apply reports the stale tag'
  Check ($script:eEdits.Count -eq 0 -and (Role) -ne 'apply') 'staged edits cleared after apply'
  Check ($script:eCommits.Count -eq $n) 'same number of commits after rewrite'
  Check ($script:eCommits[$mid].Subject -like 'Edited by selftest*') 'middle commit has the new subject'
  Check ((Get-CommitMessage $repo $script:eCommits[$mid].Sha) -eq "Edited by selftest`nsecond line") 'middle commit has the full new message'
  Check ([math]::Abs(($script:eCommits[0].Date - $newDate).TotalSeconds) -lt 2) 'top commit has the new date'
  Check ($script:eCommits[0].Subject -eq $subjects[0] -and $script:eCommits[0].Sha -ne $cTop.Sha) 'top commit keeps subject, new hash'
  Check ($script:eCommits[$n - 1].Sha -eq $origOldSha) 'older commits are untouched'
  Check ((Head $repo) -ne $startHead) 'branch head moved'
  Check (@(Get-Backups $repo).Count -eq $backups0 + 1 -and $eUndo.IsEnabled) 'backup created and Undo enabled'
  Check ($script:ePush.Ahead -gt 0 -and $script:ePush.Behind -gt 0) 'push state is diverged after rewrite'
  Check ((Info-Text) -like '*needs a force push*' -and (Role) -eq 'force' -and $ePrimary.Content -like "*Replace GitHub's version*") 'info explains the force push need and the button offers to replace'

  # push: normal refused, force works
  $remoteBefore = Head $bare "refs/heads/$branch"
  Check ($remoteBefore -eq $startHead) 'remote still has the original history'
  Check ((Do-EPush) -eq $false) 'normal push of rewritten history is refused'
  Check ((Head $bare "refs/heads/$branch") -eq $remoteBefore) 'remote unchanged after refused push'
  $threw = $false; try { [void](Push-Repo $repo) } catch { $threw = $true }
  Check $threw 'Push-Repo without -Force refuses'
  Check ((Do-EPush -Force) -eq $true) 'force push works'
  Check ((Head $bare "refs/heads/$branch") -eq (Head $repo)) 'remote head equals local head after force push'
  Check ($script:ePush.Ahead -eq 0 -and $script:ePush.Behind -eq 0 -and (Info-Text) -like '*In sync*') 'in sync after force push'

  # undo
  Do-EUndo
  Check ((Head $repo) -eq $startHead) 'undo restores the original head'
  Check (@(Get-Backups $repo).Count -eq $backups0) 'backup consumed'
  Check ($script:ePush.Behind -gt 0 -and $script:ePush.RemoteOnly -gt 0 -and (Info-Text) -like "*you don't have locally*") 'after undo the force-pushed rewritten commits exist only on the remote'

  # push error "GitHub sign-in required" is routed to the sign-in offer (no window is opened; Push-Repo is faked)
  $script:pushCalls = 0; $script:hookCalls = 0; $eLog.Clear()
  & {
    function Push-Repo([string]$Path, [switch]$Force, [switch]$DiscardRemote) { $script:pushCalls++; throw 'GitHub sign-in required (or this account cannot write). Use "Sign in to GitHub"' }
    $script:SignInHook = $null
    Check ((Do-EPush -Force) -eq $false -and $script:pushCalls -eq 1 -and $script:hookCalls -eq 0 -and $eLog.Text -like '*cancelled: not signed in*') 'sign-in required without confirmation: offer declined, nothing opened'
    $script:SignInHook = { param($p) $script:hookCalls++; [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $true; Advice = @() } }
    $script:pushCalls = 0
    $threw = $false; try { [void](Do-EPush -Force) } catch { $threw = $true }
    Check ($threw -and $script:pushCalls -eq 2 -and $script:hookCalls -eq 1) 'sign-in required: hook called once, push retried exactly once, then the error is shown'
    function Push-Repo([string]$Path, [switch]$Force, [switch]$DiscardRemote) { $script:pushCalls++; if ($script:pushCalls -eq 1) { throw 'GitHub sign-in required (test)' }; 'Pushed (fake)' }
    $script:pushCalls = 0; $script:hookCalls = 0
    Check ((Do-EPush -Force) -eq $true -and $script:pushCalls -eq 2 -and $script:hookCalls -eq 1 -and $eLog.Text -like '*retrying the upload once*') 'sign-in required then success: push retried after sign-in'
  }
  $script:SignInHook = $null
  Check ((Head $bare "refs/heads/$branch") -ne (Head $repo)) 'faked pushes left the real remote alone'

  # undo refuses when the branch changed since the rewrite; -Force overrides
  $headBefore = Head $repo; $bk0 = @(Get-Backups $repo).Count
  Do-ESelect $script:eCommits[0].Sha; $eMsg.Text = 'second rewrite'; Do-EStage; [void](Do-EApply)
  $headRw = Head $repo
  Check ($headRw -ne $headBefore) 'second rewrite moved the head'
  [void](Git-Out $repo @('commit', '--allow-empty', '-q', '-m', 'added after rewrite'))
  $headNew = Head $repo
  Do-EUndo
  Check ((Head $repo) -eq $headNew -and $eLog.Text -like '*Undo refused*' -and $eUndo.IsEnabled) 'undo refused when commits were added after the rewrite'
  Do-EUndo -Force
  Check ((Head $repo) -eq $headBefore -and @(Get-Backups $repo).Count -eq $bk0) 'undo -Force restores the pre-rewrite head'

  # foreign commits on the remote: force push refused unless explicitly discarded
  $clone = Join-Path ([IO.Path]::GetTempPath()) "backd8-foreign-$PID"
  Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue
  try {
    Check ((Git-Out $repo @('clone', '-q', '--branch', $branch, $bare, $clone)).Code -eq 0) 'foreign clone created'
    [void](Git-Out $clone @('-c', 'user.name=Other', '-c', 'user.email=other@example.com', 'commit', '--allow-empty', '-q', '-m', 'someone elses work'))
    [void](Git-Out $clone @('push', '-q', 'origin', "HEAD:refs/heads/$branch"))
    $foreign = Head $bare "refs/heads/$branch"
    Check ($foreign -eq (Head $clone)) 'foreign commit is on the remote'
    [void](Git-Out $repo @('fetch', '-q', $remote))
    Do-ELoad $repo -NoAccess
    Check ($script:ePush.RemoteOnly -ge 1 -and (Info-Text) -like "*GitHub has *you don't have locally*") 'info shows the foreign remote commit count'
    Check ((Do-EPush -Force) -eq $false -and (Head $bare "refs/heads/$branch") -eq $foreign -and $eLog.Text -like '*Force push refused*') 'force push refused while the remote holds foreign commits'
    Check ((Do-EPush -Force -DiscardRemote) -eq $true -and (Head $bare "refs/heads/$branch") -eq (Head $repo)) 'force push with -DiscardRemote replaces them'
  } finally { Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue }
  'selftest-editor-ok'
}

function Test-Flow([string]$plain, [string]$repo) {
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-flow FAILED: $what" } }
  function Head([string]$p, [string]$ref = 'HEAD') { (Git-Out $p @('rev-parse', $ref)).Out[0] }
  Reset-ELoaded
  # identity form: only through the hook in self-test, never touches git config here
  $script:idCalls = @(); $script:IdentityHook = { param($n, $m) $script:idCalls += "$n|$m" }
  $threw = $false; try { Do-SaveIdentity 'X' 'not-an-email' } catch { $threw = $true }
  Check ($threw -and $lIdErr.Visibility -eq 'Visible') 'bad email is refused inline'
  Do-SaveIdentity 'Sim User' 'sim@example.com'
  Check ($script:idCalls.Count -eq 1 -and $script:idCalls[0] -eq 'Sim User|sim@example.com') 'identity saved through the hook only'
  $script:IdentityHook = $null

  # 1. a plain folder is recognised and offered "Turn into a project"
  Open-Folder $plain
  Check ($script:ePlain -and -not $script:eRepo -and ($pPlain.Visibility -eq 'Visible')) 'plain folder shows the not-a-project panel'
  $threw = $false; try { Do-EInit 'not a url' } catch { $threw = $true }
  Check ($threw -and $wpErr.Visibility -eq 'Visible') 'bad GitHub address refused inline'
  $bare = Join-Path ([IO.Path]::GetTempPath()) "backd8-flow-remote-$PID"
  Remove-Item -LiteralPath $bare -Recurse -Force -ErrorAction SilentlyContinue
  [void](Git-Out ([IO.Path]::GetTempPath()) @('init', '-q', '--bare', $bare))
  try {
    Do-EInit $bare
    Check ($script:eRepo -and -not $script:ePlain -and $script:ePush.Url) 'folder became a project linked to the remote'
    Check ($script:eChanges.Count -ge 1 -and $lbHist.Items[0].Tag -eq '__new__' -and $script:eView -eq 'new') 'New commit row first and selected'
    # a risky file starts unticked
    Set-Content -LiteralPath (Join-Path $script:eRepo '.env') -Value 'SECRET=1'
    Do-ELoad $script:eRepo -NoAccess
    $env = @($script:FileRows | Where-Object { $_.Path -eq '.env' })[0]
    Check ($env -and -not $env.Box.IsChecked -and $env.Risky) 'risky file is flagged and unticked'
    Check (-not (Get-ENewReady) -and (Get-ENext).Role -eq 'none') 'no message yet: nothing to commit'
    # 2. new commit with a past date
    $when = (Get-Date).AddDays(-30); $when = $when.AddMilliseconds(-$when.Millisecond)
    $nMsg.Text = 'First commit from the GUI'; Set-NewWhen 'custom' $when
    Check ((Get-ENext).Role -eq 'commit' -and $nBtn.IsEnabled) 'commit button offered once a message is written'
    Check ((Do-ENewCommit) -eq $true) 'new commit created'
    $c0 = @(Get-CommitList $script:eRepo 5)[0]
    Check ($c0.Subject -eq 'First commit from the GUI' -and [math]::Abs(($c0.Date - $when).TotalSeconds) -lt 2) 'new commit has the chosen past date'
    Check (-not ((Git-Out $script:eRepo @('ls-tree', '-r', '--name-only', 'HEAD')).Out -contains '.env')) 'unticked risky file was NOT committed'
    Check ($script:eChanges.Count -eq 1 -and $script:eChanges[0].Path -eq '.env') 'the left-out file is still listed as changed'
    # second commit (now-dated, via the same path) so there is something to re-date together
    Set-Content -LiteralPath (Join-Path $script:eRepo 'b.txt') -Value 'b'; Do-ELoad $script:eRepo -NoAccess
    foreach ($i in $script:FileRows) { $i.Box.IsChecked = ($i.Path -eq 'b.txt') }
    Set-NewWhen 'now'; $nMsg.Text = 'Second commit'
    Check ((Do-ENewCommit) -eq $true) 'second commit created'
    Check (@(Get-CommitList $script:eRepo 5).Count -eq 2) 'two commits in the list'
    # 3. publish: first push to the empty remote
    Check ((Get-ENext).Role -eq 'push') 'publish button says push'
    Check ((Do-EPush) -eq $true -and (Head $bare 'refs/heads/main') -eq (Head $script:eRepo)) 'first publish reaches the remote'
    # 4. edit a message and a date of already-published commits, then publish (needs replacing GitHub's version)
    $cs = @(Get-CommitList $script:eRepo 5); $old = $cs[1]; $new = $cs[0]
    Do-ESelect $old.Sha; $eMsg.Text = 'Edited first commit'; $d2 = (Get-Date).AddDays(-60); $d2 = $d2.AddMilliseconds(-$d2.Millisecond); $ePick.Value = $d2; Do-EStage
    Check ($script:eEdits.Count -eq 1 -and (Get-ENext).Role -eq 'apply') 'edit saved; apply is the next step'
    # 5. re-date several commits starting at a date: ascending, 1-6 h apart
    $script:eSel = $null; Show-EView 'multi'; $script:eSelShas = @($old.Sha, $new.Sha); $mPick.Value = (Get-Date).AddDays(-90); Do-ESpread
    $da = [datetime]$script:eEdits[$old.Sha].date; $db = [datetime]$script:eEdits[$new.Sha].date
    Check (($db - $da).TotalMinutes -ge 60 -and ($db - $da).TotalMinutes -le 360) 're-date tool spaces commits 1-6 hours apart, oldest first'
    Check ($script:eEdits[$old.Sha].message -eq 'Edited first commit') 're-date keeps the message edit'
    Check ((Do-EApply) -eq $true) 'edits applied'
    $after = @(Get-CommitList $script:eRepo 5)
    Check ($after[1].Subject -eq 'Edited first commit' -and [math]::Abs(($after[1].Date - $da).TotalSeconds) -lt 2 -and [math]::Abs(($after[0].Date - $db).TotalSeconds) -lt 2) 'messages and dates were rewritten'
    Check ((Get-ENext).Role -eq 'force' -and $ePrimary.Content -like "*Replace GitHub's version*") 'next step: replace GitHub''s old version'
    Check ((Do-EPush) -eq $false) 'normal publish refused without force'
    Check ((Do-EPush -Force) -eq $true -and (Head $bare 'refs/heads/main') -eq (Head $script:eRepo)) 'force publish replaces the remote'
    # 6. one-click save & publish: a new commit plus nothing else
    Set-Content -LiteralPath (Join-Path $script:eRepo 'c.txt') -Value 'c'; Do-ELoad $script:eRepo -NoAccess
    foreach ($i in $script:FileRows) { $i.Box.IsChecked = ($i.Path -eq 'c.txt') }
    $nMsg.Text = 'Third commit via Save and publish'
    Do-EPublishAll
    Check ((Head $bare 'refs/heads/main') -eq (Head $script:eRepo) -and @(Get-CommitList $script:eRepo 5)[0].Subject -like 'Third commit*') 'Save & publish committed and pushed in one go'
  } finally { Remove-Item -LiteralPath $bare -Recurse -Force -ErrorAction SilentlyContinue }
  'selftest-flow-ok'
}

Refresh
if ($NoShow) { return }
if ($SelfTest) {
  # drive the same handlers the buttons call; uat.ps1 inspects the resulting config
  Do-Install; Do-Default; Do-Add $env:BACKD8_TEST_REPO; Do-Toggle
  $row = [string]$lv.Items[0].Tag; Do-Update $row; Do-Toggle; Do-Remove $row; Do-Install
  "selftest-ok rows=$($lv.Items.Count)"
  if ($env:BACKD8_TEST_REPO2) { Test-Editor $env:BACKD8_TEST_REPO2 } else { 'selftest-editor-skipped (BACKD8_TEST_REPO2 not set)' }
  if ($env:BACKD8_TEST_PLAIN) { Test-Flow $env:BACKD8_TEST_PLAIN $env:BACKD8_TEST_REPO2 } else { 'selftest-flow-skipped (BACKD8_TEST_PLAIN not set)' }
  return
}
$script:ActiveOwner = $f
$script:App.Add_DispatcherUnhandledException({ param($s, $e) $e.Handled = $true; Show-Crash $e.Exception })
$f.Add_ContentRendered({
  if ($script:started) { return }; $script:started = $true
  if (-not (Test-GitInstalled)) { return }
  $u = Load-Ui; if ($u.lastRepo -and (Test-Path -LiteralPath ([string]$u.lastRepo) -PathType Container)) { $tbPath.Text = [string]$u.lastRepo; Open-Folder ([string]$u.lastRepo) -Quiet }
})
try { [void]$f.ShowDialog() } catch { Show-Crash $_ }

