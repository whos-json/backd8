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
    $d = New-Object Windows.Controls.TextBlock; $d.Text = 'Your files and commits are safe: nothing is changed unless a button says so. Press Details, then Copy details, if you want help.'; $d.TextWrapping = 'Wrap'; $d.Margin = '0,8,0,12'; $sp.Children.Add($d) | Out-Null
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $text; $tb.IsReadOnly = $true; $tb.Height = 170; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.TextWrapping = 'Wrap'; $tb.Visibility = 'Collapsed'; $sp.Children.Add($tb) | Out-Null
    $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.HorizontalAlignment = 'Right'; $r.Margin = '0,14,0,0'
    $cp = New-Object Windows.Controls.Button; $cp.Content = 'Copy details'; $cp.Padding = '16,6'; $cp.Margin = '0,0,8,0'; $dt = New-Object Windows.Controls.Button; $dt.Content = 'Details >>'; $dt.Padding = '16,6'; $dt.Margin = '0,0,8,0'; $dt.Add_Click({ if ($tb.Visibility -eq 'Visible') { $tb.Visibility = 'Collapsed'; $dt.Content = 'Details >>' } else { $tb.Visibility = 'Visible'; $dt.Content = '<< Details' } }.GetNewClosure()); $ok = New-Object Windows.Controls.Button; $ok.Content = 'Close'; $ok.Padding = '16,6'; $ok.IsDefault = $true; $ok.IsCancel = $true
    $cp.Add_Click({ try { [Windows.Clipboard]::SetText($tb.Text) } catch {}; $cp.Content = 'Copied' }.GetNewClosure()); $ok.Add_Click({ $w.Close() }.GetNewClosure())
    $r.Children.Add($dt) | Out-Null; $r.Children.Add($cp) | Out-Null; $r.Children.Add($ok) | Out-Null; $sp.Children.Add($r) | Out-Null; $w.Content = $sp; [void]$w.ShowDialog()
  } catch { }
}
if (-not ($SelfTest -or $NoShow)) { trap { Show-Fatal "$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"; exit 1 } }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
. "$PSScriptRoot\lib.ps1"
$script:Confirm = -not ($SelfTest -or $NoShow)
$script:AskCapture = $null; $script:ActiveOwner = $null




#region Windows 98 look: palette, bevels, control styles (everything is drawn in code, no image files)
function SysHex($c) { '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
$script:Classic = @{
  Face = '#C0C0C0'; Hi = '#FFFFFF'; Light = '#DFDFDF'; Shadow = '#808080'; Dark = '#000000'; Navy = '#000080'; OnNavy = '#FFFFFF'; Teal = '#40A0A0'; Backdrop = '#3A3A9C'
  Win = '#FFFFFF'; Text = '#000000'; Hint = '#404040'; Link = '#0000FF'; Sel = '#000080'; SelText = '#FFFFFF'; Yellow = '#FFFF00'; Side = '#000000'; SideText = '#FFFFFF'
  Gray = '#808080'; Tip = '#FFFFE1'; OkFg = '#005000'; WarnFg = '#6B4000'; ErrFg = '#A00000'; InfoFg = '#000080'
}
function Get-HcPalette {
  $s = [Windows.SystemColors]
  @{ Face = (SysHex $s::ControlColor); Hi = (SysHex $s::ControlLightLightColor); Light = (SysHex $s::ControlLightColor); Shadow = (SysHex $s::ControlDarkColor); Dark = (SysHex $s::ControlDarkDarkColor)
     Navy = (SysHex $s::HighlightColor); OnNavy = (SysHex $s::HighlightTextColor); Teal = (SysHex $s::ControlColor); Backdrop = (SysHex $s::DesktopColor); Win = (SysHex $s::WindowColor)
     Text = (SysHex $s::ControlTextColor); Hint = (SysHex $s::ControlTextColor); Link = (SysHex $s::HotTrackColor); Sel = (SysHex $s::HighlightColor); SelText = (SysHex $s::HighlightTextColor)
     Yellow = (SysHex $s::HotTrackColor); Side = (SysHex $s::WindowColor); SideText = (SysHex $s::WindowTextColor); Gray = (SysHex $s::GrayTextColor); Tip = (SysHex $s::InfoColor)
     OkFg = (SysHex $s::ControlTextColor); WarnFg = (SysHex $s::ControlTextColor); ErrFg = (SysHex $s::ControlTextColor); InfoFg = (SysHex $s::ControlTextColor) }
}
function Hex([string]$h) { [Windows.Media.ColorConverter]::ConvertFromString($h) }
function Grad([string]$tl, [string]$br) {
  $g = New-Object Windows.Media.LinearGradientBrush; $g.StartPoint = New-Object Windows.Point(0, 0); $g.EndPoint = New-Object Windows.Point(1, 1)
  foreach ($s in @(@($tl, 0), @($tl, 0.5), @($br, 0.5), @($br, 1))) { [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop((Hex $s[0]), [double]$s[1]))) }
  $g.Freeze(); [Windows.Media.Brush]$g
}
# one nested pair of 1px borders = one classic 2px bevel; the diagonal hard-stop gradient paints top/left and bottom/right edges in two colours
function BvOpen([string]$o, [string]$i, [string]$bg = 'Transparent', [string]$n = '') {
  function Nm([string]$s) { if ($n) { " x:Name=`"$n$s`"" } else { '' } }
  "<Border$(Nm 'oa') BorderThickness=`"1,1,0,0`" BorderBrush=`"{DynamicResource ${o}a}`"><Border$(Nm 'ob') BorderThickness=`"0,0,1,1`" BorderBrush=`"{DynamicResource ${o}b}`"><Border$(Nm 'ia') BorderThickness=`"1,1,0,0`" BorderBrush=`"{DynamicResource ${i}a}`"><Border$(Nm 'ib') BorderThickness=`"0,0,1,1`" BorderBrush=`"{DynamicResource ${i}b}`" Background=`"$bg`">"
}
$script:BvClose = '</Border></Border></Border></Border>'
$script:ResXaml = $null
function Build-ResXaml {
  $dot = '<Rectangle x:Name="fr" Margin="2" Stroke="{DynamicResource Dark}" StrokeThickness="1" StrokeDashArray="1 1" SnapsToDevicePixels="True" Visibility="Collapsed" IsHitTestVisible="False"/>'
  $btnT = @"
<ControlTemplate TargetType="Button"><Border x:Name="df" BorderThickness="1" BorderBrush="Transparent">$(BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}' 'b')
 <Grid><Border x:Name="pad" Padding="{TemplateBinding Padding}"><ContentPresenter x:Name="cp" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" RecognizesAccessKey="True"/></Border>$dot</Grid>$($script:BvClose)</Border>
 <ControlTemplate.Triggers>
  <Trigger Property="IsDefault" Value="True"><Setter TargetName="df" Property="BorderBrush" Value="{DynamicResource Dark}"/></Trigger>
  <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="df" Property="BorderBrush" Value="{DynamicResource Dark}"/><Setter TargetName="fr" Property="Visibility" Value="Visible"/></Trigger>
  <Trigger Property="IsPressed" Value="True"><Setter TargetName="boa" Property="BorderBrush" Value="{DynamicResource BvPressOa}"/><Setter TargetName="bob" Property="BorderBrush" Value="{DynamicResource BvPressOb}"/><Setter TargetName="bia" Property="BorderBrush" Value="{DynamicResource BvPressIa}"/><Setter TargetName="bib" Property="BorderBrush" Value="{DynamicResource BvPressIb}"/><Setter TargetName="pad" Property="Margin" Value="1,1,-1,-1"/></Trigger>
  <Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger>
 </ControlTemplate.Triggers></ControlTemplate>
"@
  $tglT = $btnT -replace 'TargetType="Button"', 'TargetType="ToggleButton"' -replace '<Trigger Property="IsDefault".*?</Trigger>', '' -replace '(<Trigger Property="IsEnabled" Value="False">)', '<Trigger Property="IsChecked" Value="True"><Setter TargetName="boa" Property="BorderBrush" Value="{DynamicResource BvPressOa}"/><Setter TargetName="bob" Property="BorderBrush" Value="{DynamicResource BvPressOb}"/><Setter TargetName="bia" Property="BorderBrush" Value="{DynamicResource BvPressIa}"/><Setter TargetName="bib" Property="BorderBrush" Value="{DynamicResource BvPressIb}"/><Setter TargetName="bib" Property="Background" Value="{DynamicResource Dither}"/><Setter TargetName="pad" Property="Margin" Value="1,1,-1,-1"/></Trigger>$1'
  $sbArrow = { param($n, $d, $w, $h) "<Style x:Key=`"$n`" TargetType=`"RepeatButton`"><Setter Property=`"Focusable`" Value=`"False`"/><Setter Property=`"Template`"><Setter.Value><ControlTemplate TargetType=`"RepeatButton`">$(BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}' 'b')<Path Data=`"$d`" Width=`"$w`" Height=`"$h`" Fill=`"{DynamicResource Text}`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/>$($script:BvClose)<ControlTemplate.Triggers><Trigger Property=`"IsPressed`" Value=`"True`"><Setter TargetName=`"boa`" Property=`"BorderBrush`" Value=`"{DynamicResource BvPressOa}`"/><Setter TargetName=`"bob`" Property=`"BorderBrush`" Value=`"{DynamicResource BvPressOb}`"/><Setter TargetName=`"bia`" Property=`"BorderBrush`" Value=`"{DynamicResource BvPressIa}`"/><Setter TargetName=`"bib`" Property=`"BorderBrush`" Value=`"{DynamicResource BvPressIb}`"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>" }
@"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style TargetType="Button"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="MinWidth" Value="75"/><Setter Property="Height" Value="23"/><Setter Property="Padding" Value="8,0"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value>$btnT</Setter.Value></Setter></Style>
 <Style x:Key="CapBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="MinWidth" Value="0"/><Setter Property="Width" Value="16"/><Setter Property="Height" Value="14"/><Setter Property="Padding" Value="0"/><Setter Property="FontFamily" Value="Marlett"/><Setter Property="FontSize" Value="9"/><Setter Property="IsTabStop" Value="False"/><Setter Property="Focusable" Value="False"/></Style>
 <Style x:Key="HdrBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="MinWidth" Value="0"/><Setter Property="Height" Value="22"/><Setter Property="Padding" Value="6,0"/><Setter Property="HorizontalContentAlignment" Value="Left"/></Style>
 <Style x:Key="SmallBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="MinWidth" Value="0"/><Setter Property="Height" Value="25"/><Setter Property="Padding" Value="8,0"/></Style>
 <Style x:Key="LinkBtn" TargetType="Button"><Setter Property="Foreground" Value="{DynamicResource Link}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Padding" Value="2,1"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid Background="Transparent"><Border Padding="{TemplateBinding Padding}"><Grid><ContentPresenter RecognizesAccessKey="True"/><Rectangle Height="1" VerticalAlignment="Bottom" Fill="{TemplateBinding Foreground}" Margin="0,0,0,-1" IsHitTestVisible="False"/></Grid></Border>$dot</Grid>
   <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="fr" Property="Visibility" Value="Visible"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ToggleButton"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="Height" Value="23"/><Setter Property="Padding" Value="8,0"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value>$tglT</Setter.Value></Setter></Style>
 <Style TargetType="TextBox"><Setter Property="Background" Value="{DynamicResource Win}"/><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="Padding" Value="2,1"/><Setter Property="MinHeight" Value="21"/><Setter Property="CaretBrush" Value="{DynamicResource Text}"/><Setter Property="SelectionBrush" Value="{DynamicResource Sel}"/><Setter Property="SelectionTextBrush" Value="{DynamicResource SelText}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">$(BvOpen 'BvSunkO' 'BvSunkI' '{TemplateBinding Background}')<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" Focusable="False" HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>$($script:BvClose)
   <ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Width="13" Height="13" VerticalAlignment="Top" Margin="0,1,6,0">$(BvOpen 'BvSunkO' 'BvSunkI' '{DynamicResource Win}')<Path x:Name="tick" Data="M2.5,5 L4.5,7 L8.5,2.5" Stroke="{DynamicResource Text}" StrokeThickness="2" Visibility="Collapsed" Margin="0,0,0,0" HorizontalAlignment="Center" VerticalAlignment="Center"/>$($script:BvClose)</Border>
   <Grid Grid.Column="1"><ContentPresenter VerticalAlignment="Center" RecognizesAccessKey="True" Margin="2,1"/>$dot</Grid></Grid>
   <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="tick" Property="Visibility" Value="Visible"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="fr" Property="Visibility" Value="Visible"/><Setter TargetName="fr" Property="Margin" Value="0"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="RadioButton"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Margin" Value="0,0,0,6"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton"><Grid Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Grid Width="12" Height="12" VerticalAlignment="Top" Margin="0,2,6,0"><Ellipse Fill="{DynamicResource Win}"/>
    <Path Data="M2.11,9.89 A5.5,5.5 0 0 1 9.89,2.11" Stroke="{DynamicResource Shadow}" StrokeThickness="1"/><Path Data="M9.89,2.11 A5.5,5.5 0 0 1 2.11,9.89" Stroke="{DynamicResource Hi}" StrokeThickness="1"/>
    <Path Data="M2.82,9.18 A4.5,4.5 0 0 1 9.18,2.82" Stroke="{DynamicResource Dark}" StrokeThickness="1"/><Path Data="M9.18,2.82 A4.5,4.5 0 0 1 2.82,9.18" Stroke="{DynamicResource Light}" StrokeThickness="1"/>
    <Ellipse x:Name="dot" Width="4" Height="4" Fill="{DynamicResource Text}" Visibility="Collapsed"/></Grid>
   <Grid Grid.Column="1"><ContentPresenter VerticalAlignment="Top" RecognizesAccessKey="True" Margin="3,1,3,1"/>$dot</Grid></Grid>
   <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="dot" Property="Visibility" Value="Visible"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="fr" Property="Visibility" Value="Visible"/><Setter TargetName="fr" Property="Margin" Value="0"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="GroupBox"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="Padding" Value="8,6,8,8"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="GroupBox"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
   <Border Grid.RowSpan="2" Margin="0,7,0,0">$(BvOpen 'BvEtchO' 'BvEtchI')$($script:BvClose)</Border>
   <Border Grid.Row="0" HorizontalAlignment="Left" Margin="8,0,0,0" Padding="3,0" Background="{DynamicResource Face}"><ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/></Border>
   <ContentPresenter Grid.Row="1" Margin="{TemplateBinding Padding}" SnapsToDevicePixels="True"/></Grid></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ToolTip"><Setter Property="FontFamily" Value="{DynamicResource FontUi}"/><Setter Property="FontSize" Value="{DynamicResource FontSizeUi}"/><Setter Property="TextOptions.TextFormattingMode" Value="Display"/><Setter Property="TextOptions.TextRenderingMode" Value="Aliased"/><Setter Property="TextOptions.TextHintingMode" Value="Fixed"/><Setter Property="Background" Value="{DynamicResource Tip}"/><Setter Property="Foreground" Value="#000000"/><Setter Property="BorderBrush" Value="{DynamicResource Dark}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="3,1"/><Setter Property="MaxWidth" Value="380"/><Setter Property="HasDropShadow" Value="False"/>
  <Setter Property="ContentTemplate"><Setter.Value><DataTemplate><TextBlock Text="{Binding}" TextWrapping="Wrap"/></DataTemplate></Setter.Value></Setter></Style>
 <Style x:Key="SbPage" TargetType="RepeatButton"><Setter Property="Focusable" Value="False"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></Setter.Value></Setter></Style>
 <Style x:Key="SbThumb" TargetType="Thumb"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Thumb">$(BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}')$($script:BvClose)</ControlTemplate></Setter.Value></Setter></Style>
 $(& $sbArrow 'SbUp' 'M0,4 L3.5,0 L7,4 Z' 7 4)
 $(& $sbArrow 'SbDown' 'M0,0 L7,0 L3.5,4 Z' 7 4)
 $(& $sbArrow 'SbLeft' 'M4,0 L4,7 L0,3.5 Z' 4 7)
 $(& $sbArrow 'SbRight' 'M0,0 L0,7 L4,3.5 Z' 4 7)
 <Style TargetType="ScrollBar"><Setter Property="Width" Value="16"/><Setter Property="MinWidth" Value="16"/><Setter Property="Background" Value="{DynamicResource Dither}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Background="{DynamicResource Dither}"><Grid.RowDefinitions><RowDefinition Height="16"/><RowDefinition Height="*"/><RowDefinition Height="16"/></Grid.RowDefinitions>
    <RepeatButton Style="{StaticResource SbUp}" Command="ScrollBar.LineUpCommand"/>
    <Track x:Name="PART_Track" Grid.Row="1" IsDirectionReversed="True"><Track.DecreaseRepeatButton><RepeatButton Style="{StaticResource SbPage}" Command="ScrollBar.PageUpCommand"/></Track.DecreaseRepeatButton><Track.IncreaseRepeatButton><RepeatButton Style="{StaticResource SbPage}" Command="ScrollBar.PageDownCommand"/></Track.IncreaseRepeatButton><Track.Thumb><Thumb Style="{StaticResource SbThumb}"/></Track.Thumb></Track>
    <RepeatButton Grid.Row="2" Style="{StaticResource SbDown}" Command="ScrollBar.LineDownCommand"/></Grid></ControlTemplate></Setter.Value></Setter>
  <Style.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="MinWidth" Value="0"/><Setter Property="Height" Value="16"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Background="{DynamicResource Dither}"><Grid.ColumnDefinitions><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/></Grid.ColumnDefinitions>
    <RepeatButton Style="{StaticResource SbLeft}" Command="ScrollBar.LineLeftCommand"/>
    <Track x:Name="PART_Track" Grid.Column="1"><Track.DecreaseRepeatButton><RepeatButton Style="{StaticResource SbPage}" Command="ScrollBar.PageLeftCommand"/></Track.DecreaseRepeatButton><Track.IncreaseRepeatButton><RepeatButton Style="{StaticResource SbPage}" Command="ScrollBar.PageRightCommand"/></Track.IncreaseRepeatButton><Track.Thumb><Thumb Style="{StaticResource SbThumb}"/></Track.Thumb></Track>
    <RepeatButton Grid.Column="2" Style="{StaticResource SbRight}" Command="ScrollBar.LineRightCommand"/></Grid></ControlTemplate></Setter.Value></Setter></Trigger></Style.Triggers></Style>
 <Style TargetType="ListBox"><Setter Property="Background" Value="{DynamicResource Win}"/><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Padding" Value="0"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBox">$(BvOpen 'BvSunkO' 'BvSunkI' '{TemplateBinding Background}')<ScrollViewer Focusable="False" Padding="{TemplateBinding Padding}" HorizontalScrollBarVisibility="{TemplateBinding ScrollViewer.HorizontalScrollBarVisibility}" VerticalScrollBarVisibility="{TemplateBinding ScrollViewer.VerticalScrollBarVisibility}"><ItemsPresenter/></ScrollViewer>$($script:BvClose)</ControlTemplate></Setter.Value></Setter></Style>
 <Style x:Key="RowItem" TargetType="ListBoxItem"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="bd" Background="Transparent" Padding="2,1" BorderThickness="1" BorderBrush="Transparent"><Grid><ContentPresenter x:Name="cp"/>$dot</Grid></Border>
   <ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Sel}"/><Setter Property="Foreground" Value="{DynamicResource SelText}"/></Trigger>
    <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="fr" Property="Visibility" Value="Visible"/><Setter TargetName="fr" Property="Margin" Value="0"/><Setter TargetName="fr" Property="Stroke" Value="{DynamicResource Yellow}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ProgressBar"><Setter Property="Height" Value="20"/><Setter Property="Foreground" Value="{DynamicResource Navy}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ProgressBar">$(BvOpen 'BvSunkO' 'BvSunkI' '{DynamicResource Face}')<Grid x:Name="PART_Track" Margin="2"><Rectangle x:Name="PART_Indicator" HorizontalAlignment="Left" Fill="{DynamicResource Blocks}"/></Grid>$($script:BvClose)</ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ContextMenu"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="FontFamily" Value="{DynamicResource FontUi}"/><Setter Property="FontSize" Value="{DynamicResource FontSizeUi}"/><Setter Property="TextOptions.TextFormattingMode" Value="Display"/><Setter Property="TextOptions.TextRenderingMode" Value="Aliased"/><Setter Property="TextOptions.TextHintingMode" Value="Fixed"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu">$(BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}')<StackPanel IsItemsHost="True" Margin="1"/>$($script:BvClose)</ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="MenuItem"><Setter Property="Foreground" Value="{DynamicResource Text}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem"><Border x:Name="bd" Background="Transparent" Padding="22,3,22,3"><ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Sel}"/><Setter Property="Foreground" Value="{DynamicResource SelText}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource Gray}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="Hyperlink"><Setter Property="Foreground" Value="{DynamicResource Link}"/></Style>
</ResourceDictionary>
"@
}
function Apply-Theme {
  $hc = $false; try { $hc = [bool][Windows.SystemParameters]::HighContrast } catch {}
  $p = if ($hc) { Get-HcPalette } else { $script:Classic }
  foreach ($k in $p.Keys) { $br = New-Object Windows.Media.SolidColorBrush((Hex $p[$k])); $br.Freeze(); $script:Res[$k] = [Windows.Media.Brush]$br }
  foreach ($a in @(@('Muted', 'Hint'), @('Accent', 'Navy'), @('OnAccent', 'OnNavy'), @('Bg', 'Face'), @('Card', 'Face'), @('CardBorder', 'Shadow'))) { $script:Res[$a[0]] = $script:Res[$a[1]] }
  function Pair([string]$name, [string]$tl, [string]$br) { foreach ($x in @(@('a', $tl), @('b', $br))) { $b = New-Object Windows.Media.SolidColorBrush((Hex $x[1])); $b.Freeze(); $script:Res["$name$($x[0])"] = [Windows.Media.Brush]$b } }
  Pair 'BvRaiseO' $p.Hi $p.Dark;   Pair 'BvRaiseI' $p.Light $p.Shadow
  Pair 'BvPressO' $p.Dark $p.Hi;   Pair 'BvPressI' $p.Shadow $p.Light
  Pair 'BvSunkO' $p.Shadow $p.Hi;  Pair 'BvSunkI' $p.Dark $p.Light
  Pair 'BvEtchO' $p.Shadow $p.Hi;  Pair 'BvEtchI' $p.Hi $p.Shadow
  $ns = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
  $script:Res['Dither'] = [Windows.Markup.XamlReader]::Parse("<DrawingBrush $ns TileMode=`"Tile`" Viewport=`"0,0,2,2`" ViewportUnits=`"Absolute`" Viewbox=`"0,0,2,2`" ViewboxUnits=`"Absolute`"><DrawingBrush.Drawing><DrawingGroup><GeometryDrawing Brush=`"$($p.Face)`"><GeometryDrawing.Geometry><RectangleGeometry Rect=`"0,0,2,2`"/></GeometryDrawing.Geometry></GeometryDrawing><GeometryDrawing Brush=`"$($p.Hi)`"><GeometryDrawing.Geometry><GeometryGroup><RectangleGeometry Rect=`"0,0,1,1`"/><RectangleGeometry Rect=`"1,1,1,1`"/></GeometryGroup></GeometryDrawing.Geometry></GeometryDrawing></DrawingGroup></DrawingBrush.Drawing></DrawingBrush>")
  $script:Res['Blocks'] = [Windows.Markup.XamlReader]::Parse("<DrawingBrush $ns TileMode=`"Tile`" Viewport=`"0,0,10,40`" ViewportUnits=`"Absolute`" Viewbox=`"0,0,10,40`" ViewboxUnits=`"Absolute`"><DrawingBrush.Drawing><GeometryDrawing Brush=`"$($p.Navy)`"><GeometryDrawing.Geometry><RectangleGeometry Rect=`"0,0,8,40`"/></GeometryDrawing.Geometry></GeometryDrawing></DrawingBrush.Drawing></DrawingBrush>")
  $script:HighContrast = $hc
}
$script:ResXaml = Build-ResXaml
$script:Res = [Windows.Markup.XamlReader]::Parse($script:ResXaml)
Apply-Theme
if (-not [Windows.Application]::Current) { $script:App = New-Object Windows.Application; $script:App.ShutdownMode = 'OnMainWindowClose' } else { $script:App = [Windows.Application]::Current }
$script:App.Resources.MergedDictionaries.Add($script:Res)

# typography (see assets\fonts\FONTS.md): the real Win98-era system faces, nothing bundled. Tahoma 11px (= 8pt) drawn Aliased with Display hinting is dark, tight and crisp from 100% to 200% DPI,
# unlike pixel fonts (fractional DPI scales smear them). Keep body text at 11 DIP: 12/13 give hint-rounding gaps ("Rem ove"). The comma lists are the silent fallback chain; CJK/RTL/emoji fall back per glyph.
$script:FontUi = New-Object Windows.Media.FontFamily('Tahoma, Microsoft Sans Serif, MS UI Gothic, Segoe UI')
$script:BodySize = 11
$script:FontTitle = New-Object Windows.Media.FontFamily('Arial')
$script:FontMono = New-Object Windows.Media.FontFamily('Lucida Console, Consolas, Courier New')
$script:MonoSize = 12; $script:MonoSmall = 12
$script:FontCaps = $script:FontUi
$script:CapsSize = $script:BodySize
$script:Res['FontUi'] = [Windows.Media.FontFamily]$script:FontUi; $script:Res['FontMono'] = [Windows.Media.FontFamily]$script:FontMono; $script:Res['FontSizeUi'] = [double]$script:BodySize
$script:I = @{ Check = 'check'; Warn = 'warn'; Err = 'error'; Info = 'info'; Folder = 'folder'; Edit = 'pencil'; Add = 'plus'; Cloud = 'cloud'; Upload = 'pc'; Undo = 'info'; Calendar = 'clock'; Search = 'info'; Settings = 'info'; Help = 'question'; Lock = 'key'; Circle = 'info'; Sync = 'info'; Clock = 'clock'; Link = 'globe' }
$script:G = @{ Dot = '-'; Dash = '-'; Ell = '...'; Up = '^'; Down = 'v'; Arrow = '->'; Edit = '*'; Ok = '[OK]'; Warn = '(!)'; Err = '(x)'; Off = '( )'; Info = '(i)' }
#endregion











#region helpers
function New-Err([string]$m) { [Management.Automation.ErrorRecord]::new([Exception]::new($m), 'wf', [Management.Automation.ErrorCategory]::NotSpecified, $null) }
function CT([string]$s, [int]$m = 300) { if (Get-Command Clean-Text -ErrorAction SilentlyContinue) { Clean-Text $s $m } else { $s } }
function Plural([int]$n, [string]$one, [string]$many) { if ($n -eq 1) { "$n $one" } else { "$n $many" } }
function Br([string]$key) { $script:Res[$key] }
function SetRes($el, $prop, [string]$key) { $el.SetResourceReference($prop, $key) }
function Vis([bool]$v) { if ($v) { 'Visible' } else { 'Collapsed' } }
function New-Tb([string]$text, [double]$size = 11, [string]$fg = 'Text', [string]$weight = 'Normal', [bool]$wrap = $true) {
  if ($size -eq 11) { $size = $script:BodySize }; $t = New-Object Windows.Controls.TextBlock; $t.Text = $text; $t.FontSize = $size; $t.FontWeight = $weight; if ($wrap) { $t.TextWrapping = 'Wrap' }
  SetRes $t ([Windows.Controls.TextBlock]::ForegroundProperty) $fg; $t
}
function DoEvents {
  $fr = New-Object Windows.Threading.DispatcherFrame
  $cb = [Windows.Threading.DispatcherOperationCallback]{ param($o) $o.Continue = $false; $null }
  [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, $cb, $fr)
  [Windows.Threading.Dispatcher]::PushFrame($fr)
}
function Acc($c, [string]$name, [string]$help = '') { [Windows.Automation.AutomationProperties]::SetName($c, $name); if ($help) { [Windows.Automation.AutomationProperties]::SetHelpText($c, $help) } }
function Tip($c, [string]$text) { $c.ToolTip = $text; [Windows.Controls.ToolTipService]::SetShowOnDisabled($c, $true); if ($text -and -not [Windows.Automation.AutomationProperties]::GetHelpText($c)) { [Windows.Automation.AutomationProperties]::SetHelpText($c, $text) } }

# label with an always-underlined access key ("&Next >"): Win98 style, and Alt+letter really works. Sets the automation name too.
# access keys are registered only while their control is on a visible page (Apply-MnScope), so one letter can be reused on different pages
$script:MnReg = New-Object System.Collections.ArrayList
function Reg-Mn([string]$k, $c) {
  for ($i = $script:MnReg.Count - 1; $i -ge 0; $i--) { if ([object]::ReferenceEquals($script:MnReg[$i].Ctl, $c)) { if ($script:MnReg[$i].On) { try { [Windows.Input.AccessKeyManager]::Unregister($script:MnReg[$i].Key, $c) } catch {} }; $script:MnReg.RemoveAt($i) } }
  if ($k) { [void]$script:MnReg.Add(@{ Key = $k; Ctl = $c; On = $false; Done = $false }) }
}
function Get-RootWindow($c) { $x = $c; while ($x) { if ($x -is [Windows.Window]) { return $x }; $x = [Windows.LogicalTreeHelper]::GetParent($x) }; $null }
function Test-ChainVisible($c) {
  $x = $c
  while ($x) {
    if ($x -is [Windows.Window]) { if ($script:win -and [object]::ReferenceEquals($x, $script:win)) { return $true }; return [bool]$x.IsVisible }
    if ($x -is [Windows.UIElement] -and $x.Visibility -ne 'Visible') { return $false }
    $x = [Windows.LogicalTreeHelper]::GetParent($x)
  }
  $true
}
function Apply-MnScope {
  for ($i = $script:MnReg.Count - 1; $i -ge 0; $i--) {
    $r = $script:MnReg[$i]; $rw = Get-RootWindow $r.Ctl
    if ($rw -and -not [object]::ReferenceEquals($rw, $script:win) -and -not [object]::ReferenceEquals($rw, $script:af) -and -not $rw.IsVisible -and $r.Done) { if ($r.On) { try { [Windows.Input.AccessKeyManager]::Unregister($r.Key, $r.Ctl) } catch {} }; $script:MnReg.RemoveAt($i); continue }
    $vis = (Test-ChainVisible $r.Ctl) -and $r.Ctl.IsEnabled
    if ($rw -and $rw.IsVisible) { $r.Done = $true }
    if ($vis -and -not $r.On) { [Windows.Input.AccessKeyManager]::Register($r.Key, $r.Ctl); $r.On = $true }
    elseif (-not $vis -and $r.On) { try { [Windows.Input.AccessKeyManager]::Unregister($r.Key, $r.Ctl) } catch {}; $r.On = $false }
  }
}function Get-DuplicateKeys { @($script:MnReg | Where-Object { $_.On } | Group-Object { $_.Key } | Where-Object { $_.Count -gt 1 } | ForEach-Object { "$($_.Name): " + ((@($_.Group | ForEach-Object { Get-Mn $_.Ctl }) -join ' / ')) }) }
function Set-Mn($c, [string]$label) {
  $plain = $label -replace '&', ''
  $i = $label.IndexOf('&')
  if ($i -lt 0 -or $i -ge $label.Length - 1) { $c.Content = $label; Reg-Mn '' $c }
  else {
    $tb = New-Object Windows.Controls.TextBlock
    if ($i -gt 0) { [void]$tb.Inlines.Add((New-Object Windows.Documents.Run($label.Substring(0, $i)))) }
    $u = New-Object Windows.Documents.Run([string]$label[$i + 1]); $u.TextDecorations = [Windows.TextDecorations]::Underline; [void]$tb.Inlines.Add($u)
    if ($i + 2 -lt $label.Length) { [void]$tb.Inlines.Add((New-Object Windows.Documents.Run($label.Substring($i + 2)))) }
    $c.Content = $tb
    Reg-Mn (([string]$label[$i + 1]).ToUpperInvariant()) $c
  }
  Acc $c ($plain -replace '\s*[<>]+\s*', ' ').Trim()
}
function Get-Mn($c) { $x = $c.Content; if ($x -is [Windows.Controls.TextBlock]) { $x.Text } else { "$x" } }
function Set-Kind($b, [string]$kind) { if ($kind -in 'ghost', 'link') { $b.Style = $script:Res['LinkBtn'] } else { $b.ClearValue([Windows.Controls.Button]::StyleProperty) } }
function New-Button([string]$label, [string]$kind = 'normal', [double]$minW = 0) { $b = New-Object Windows.Controls.Button; Set-Mn $b $label; Set-Kind $b $kind; if ($minW) { $b.MinWidth = $minW }; $b }

# ---- tiny vector icons (32x32 design grid, scaled; nothing is loaded from disk)
$script:IconXaml = @{
  info = '<Ellipse Canvas.Left="1" Canvas.Top="1" Width="30" Height="30" Fill="#0000FF" Stroke="#FFFFFF" StrokeThickness="1"/><Rectangle Canvas.Left="14" Canvas.Top="14" Width="4" Height="10" Fill="#FFFFFF"/><Rectangle Canvas.Left="14" Canvas.Top="8" Width="4" Height="4" Fill="#FFFFFF"/>'
  warn = '<Polygon Points="16,2 30,29 2,29" Fill="#FFFF00" Stroke="#000000" StrokeThickness="2"/><Rectangle Canvas.Left="14" Canvas.Top="11" Width="4" Height="10" Fill="#000000"/><Rectangle Canvas.Left="14" Canvas.Top="23" Width="4" Height="3" Fill="#000000"/>'
  error = '<Ellipse Canvas.Left="1" Canvas.Top="1" Width="30" Height="30" Fill="#FF0000" Stroke="#800000" StrokeThickness="1"/><Path Data="M10,10 L22,22 M22,10 L10,22" Stroke="#FFFFFF" StrokeThickness="4"/>'
  question = '<Ellipse Canvas.Left="1" Canvas.Top="1" Width="30" Height="30" Fill="#0000FF" Stroke="#FFFFFF" StrokeThickness="1"/><TextBlock Canvas.Left="10" Canvas.Top="1" Text="?" FontFamily="Arial" FontWeight="Bold" FontSize="26" Foreground="#FFFFFF"/>'
  check = '<Path Data="M5,16 L12,23 L27,7" Stroke="#000000" StrokeThickness="4"/>'
  cloud = '<Path Data="M9,25 C2,25 2,14 9,14 C9,6 21,5 23,12 C30,11 31,25 23,25 Z" Fill="#FFFFFF" Stroke="#000080" StrokeThickness="2.5"/>'
  pc = '<Rectangle Canvas.Left="3" Canvas.Top="4" Width="26" Height="18" Fill="#C0C0C0" Stroke="#000000" StrokeThickness="2"/><Rectangle Canvas.Left="7" Canvas.Top="8" Width="18" Height="10" Fill="#008080"/><Rectangle Canvas.Left="12" Canvas.Top="22" Width="8" Height="4" Fill="#808080"/><Rectangle Canvas.Left="7" Canvas.Top="26" Width="18" Height="4" Fill="#C0C0C0" Stroke="#000000" StrokeThickness="2"/>'
  pencil = '<Path Data="M5,27 L7,20 L21,6 L26,11 L12,25 Z" Fill="#FFFF00" Stroke="#000000" StrokeThickness="2"/><Path Data="M5,27 L7,20 L12,25 Z" Fill="#000000"/>'
  plus = '<Path Data="M16,5 L16,27 M5,16 L27,16" Stroke="#000000" StrokeThickness="5"/>'
  folder = '<Rectangle Canvas.Left="2" Canvas.Top="9" Width="28" Height="20" Fill="#FFFF00" Stroke="#000000" StrokeThickness="2"/><Rectangle Canvas.Left="2" Canvas.Top="4" Width="12" Height="6" Fill="#FFFF00" Stroke="#000000" StrokeThickness="2"/>'
  page = '<Path Data="M6,2 L21,2 L27,8 L27,30 L6,30 Z" Fill="#FFFFFF" Stroke="#000000" StrokeThickness="2"/><Path Data="M10,14 L23,14 M10,19 L23,19 M10,24 L23,24" Stroke="#000080" StrokeThickness="2"/>'
  clock = '<Ellipse Canvas.Left="2" Canvas.Top="2" Width="28" Height="28" Fill="#FFFFFF" Stroke="#000000" StrokeThickness="2"/><Path Data="M16,7 L16,16 L23,20" Stroke="#000000" StrokeThickness="3"/>'
  globe = '<Ellipse Canvas.Left="2" Canvas.Top="2" Width="28" Height="28" Fill="#0000FF" Stroke="#000000" StrokeThickness="2"/><Path Data="M8,10 L14,8 L18,13 L13,18 L9,16 Z M19,18 L25,17 L23,25 L19,23 Z" Fill="#00A000"/>'
  key = '<Ellipse Canvas.Left="3" Canvas.Top="4" Width="14" Height="14" Fill="#FFFF00" Stroke="#000000" StrokeThickness="2"/><Path Data="M15,16 L28,29 M22,22 L25,19 M25,25 L28,22" Stroke="#000000" StrokeThickness="3"/>'
}
function New-Icon([string]$kind, [double]$size = 16) {
  $x = $script:IconXaml[$kind]; if (-not $x) { $x = $script:IconXaml['info'] }
  $c = [Windows.Markup.XamlReader]::Parse("<Canvas xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" Width=`"32`" Height=`"32`">$x</Canvas>")
  $vb = New-Object Windows.Controls.Viewbox; $vb.Width = $size; $vb.Height = $size; $vb.Stretch = 'Uniform'; $vb.Child = $c; $vb.IsHitTestVisible = $false; $vb.Focusable = $false; [Windows.Automation.AutomationProperties]::SetName($vb, ''); $vb
}
function Set-IconHost($host_, [string]$kind, [double]$size = 16) { $host_.Content = (New-Icon $kind $size) }
function Kind-Icon([string]$k) { switch ($k) { 'ok' { 'check' } 'warn' { 'warn' } 'danger' { 'error' } 'idle' { 'info' } default { 'info' } } }

# ---- the pixel-art illustration on the teal panel (rectangles on a small grid, shown at 2x with hard edges)
function New-Art([string]$kind) {
  $c = New-Object Windows.Controls.Canvas; $c.Width = 56; $c.Height = 150; $c.SnapsToDevicePixels = $true; $c.UseLayoutRounding = $true
  function Rc([double]$x, [double]$y, [double]$w, [double]$h, [string]$fill) { $r = New-Object Windows.Shapes.Rectangle; $r.Width = $w; $r.Height = $h; $r.Fill = New-Object Windows.Media.SolidColorBrush((Hex $fill)); [Windows.Controls.Canvas]::SetLeft($r, $x); [Windows.Controls.Canvas]::SetTop($r, $y); [void]$c.Children.Add($r) }
  function El([double]$x, [double]$y, [double]$w, [double]$h, [string]$fill) { $r = New-Object Windows.Shapes.Ellipse; $r.Width = $w; $r.Height = $h; $r.Fill = New-Object Windows.Media.SolidColorBrush((Hex $fill)); [Windows.Controls.Canvas]::SetLeft($r, $x); [Windows.Controls.Canvas]::SetTop($r, $y); [void]$c.Children.Add($r) }
  function Pg([string]$pts, [string]$fill) { $r = New-Object Windows.Shapes.Polygon; $r.Points = [Windows.Media.PointCollection]::Parse($pts); $r.Fill = New-Object Windows.Media.SolidColorBrush((Hex $fill)); [void]$c.Children.Add($r) }
  # monitor
  Rc 5 4 46 38 '#000000'; Rc 6 5 44 36 '#E8E4D8'; Rc 6 5 44 1 '#FFFFFF'; Rc 6 5 1 36 '#FFFFFF'; Rc 49 6 1 35 '#808080'; Rc 7 40 43 1 '#808080'
  Rc 10 9 36 28 '#808080'; Rc 11 10 36 28 '#FFFFFF'; Rc 11 10 34 26 '#000000'; Rc 12 11 32 24 '#006060'
  Rc 22 42 12 4 '#C8C4B8'; Rc 22 42 12 1 '#000000'; Rc 14 46 28 4 '#E8E4D8'; Rc 14 46 28 1 '#000000'; Rc 14 49 28 1 '#808080'; Rc 14 46 1 4 '#000000'; Rc 41 46 1 4 '#000000'
  # keyboard
  Rc 6 54 44 10 '#000000'; Rc 7 55 42 8 '#E8E4D8'; for ($i = 0; $i -lt 8; $i++) { Rc (9 + $i * 5) 57 3 2 '#808080'; Rc (9 + $i * 5) 60 3 2 '#808080' }
  switch ($kind) {
    'p1' {
      Rc 18 17 16 11 '#FFFF00'; Rc 18 15 7 3 '#FFFF00'; Rc 18 27 16 1 '#808000'; Rc 34 17 1 11 '#808000'
      Rc 6 74 24 24 '#000000'; Rc 7 75 22 22 '#000080'; Rc 10 75 14 8 '#C0C0C0'; Rc 20 76 2 5 '#000080'; Rc 9 87 18 9 '#FFFFFF'; Rc 11 90 14 1 '#808080'; Rc 11 93 14 1 '#808080'
      El 32 74 22 22 '#000000'; El 33 75 20 20 '#E8E8E8'; El 39 81 8 8 '#006060'; El 41 83 4 4 '#000000'
      Rc 6 106 24 24 '#000000'; Rc 7 107 22 22 '#000080'; Rc 10 107 14 8 '#C0C0C0'; Rc 20 108 2 5 '#000080'; Rc 9 119 18 9 '#FFFFFF'
    }
    'p2' {
      Rc 16 15 22 1 '#FFFFFF'; Rc 16 18 16 1 '#FFFFFF'; Rc 16 21 20 1 '#FFFFFF'; Rc 16 24 12 1 '#FFFFFF'; Rc 16 27 18 1 '#FFFF00'; Rc 16 30 10 1 '#FFFF00'
      Rc 6 74 36 50 '#000000'; Rc 7 75 34 48 '#FFFFFF'; Rc 7 75 34 7 '#C00000'; for ($i = 0; $i -lt 5; $i++) { Rc 11 (87 + $i * 7) 26 1 '#000080' }
      Rc 10 77 3 3 '#FFFFFF'; Rc 17 77 3 3 '#FFFFFF'; Rc 24 77 3 3 '#FFFFFF'; Rc 31 77 3 3 '#FFFFFF'
      Pg '46,96 52,102 36,128 33,126' '#FFFF00'; Pg '33,126 36,128 31,132' '#000000'; Pg '46,96 52,102 50,104 44,98' '#C00000'
    }
    'p3' {
      El 20 14 16 16 '#4060FF'; Rc 24 18 5 4 '#00A000'; Rc 29 24 4 3 '#00A000'
      El 8 76 40 40 '#000000'; El 9 77 38 38 '#2040FF'; Rc 16 84 12 8 '#00A000'; Rc 24 92 14 10 '#00A000'; Rc 32 82 8 6 '#00A000'; Rc 14 100 8 6 '#00A000'
      El 8 120 14 14 '#000000'; El 10 122 10 10 '#FFFF00'; El 13 125 4 4 '#000000'; Rc 20 126 26 4 '#000000'; Rc 21 127 24 2 '#FFFF00'; Rc 38 130 4 6 '#000000'; Rc 39 130 2 5 '#FFFF00'; Rc 44 130 4 5 '#000000'; Rc 45 130 2 4 '#FFFF00'
    }
    'p4' {
      Rc 18 28 16 2 '#FFFFFF'; Pg '26,14 36,24 31,24 31,28 21,28 21,24 16,24' '#FFFFFF'
      Rc 6 74 24 24 '#000000'; Rc 7 75 22 22 '#000080'; Rc 10 75 14 8 '#C0C0C0'; Rc 20 76 2 5 '#000080'; Rc 9 87 18 9 '#FFFFFF'; Rc 11 90 14 1 '#808080'; Rc 11 93 14 1 '#808080'
      Pg '24,104 34,104 34,100 46,110 34,120 34,116 24,116' '#FFFF00'; Pg '24,104 34,104 34,100 46,110 34,120 34,116 24,116' '#FFFF00'
      El 10 124 18 14 '#FFFFFF'; El 20 118 20 18 '#FFFFFF'; El 30 124 18 14 '#FFFFFF'; Rc 18 130 22 8 '#FFFFFF'
    }
  }
  $c.LayoutTransform = New-Object Windows.Media.ScaleTransform(2, 2); $c
}

# ---- times and dates typed by people: 9:30, 21:05, 9pm, 9:30 pm, 9 ; 2025-3-1, 2025/03/01
function Parse-TimeText([string]$s) {
  $t = ("$s".Trim().ToLowerInvariant() -replace '\s+', '')
  if ($t -eq 'noon') { return (New-TimeSpan -Hours 12) }; if ($t -eq 'midnight') { return (New-TimeSpan) }
  if ($t -notmatch '^(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)?$') { return $null }
  $h = [int]$Matches[1]; $m = if ($Matches[2]) { [int]$Matches[2] } else { 0 }; $ap = $Matches[3]
  if ($m -gt 59) { return $null }
  if ($ap) { if ($h -lt 1 -or $h -gt 12) { return $null }; if ($ap -like 'p*') { $h = ($h % 12) + 12 } else { $h = $h % 12 } } elseif ($h -gt 23) { return $null }
  New-TimeSpan -Hours $h -Minutes $m
}
function Parse-DateText([string]$s) {
  $d = [datetime]::MinValue
  if ([datetime]::TryParseExact("$s".Trim(), [string[]]@('yyyy-MM-dd', 'yyyy-M-d', 'yyyy/MM/dd', 'yyyy/M/d', 'yyyy.MM.dd'), [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $d } else { $null }
}
function Get-DateProblem([datetime]$v) {
  if ($v -eq [datetime]::MinValue) { return 'Type a valid date and time.' }
  try { if (Get-Command Assert-GitDate -ErrorAction SilentlyContinue) { Assert-GitDate $v } elseif ($v -gt (Get-Date)) { throw 'Date must be in the past.' } }
  catch { $m = $_.Exception.Message; if ($m -like 'Date must be in the past*') { return 'That date is in the future. Choose a date and time that have already passed.' }; return $m }
  $null
}
# date + time boxes with a calendar popup. .Value reads/writes a [datetime]; the ORIGINAL seconds are kept while the hour:minute text is untouched
function New-Dt([datetime]$initial = (Get-Date)) {
  $o = [pscustomobject]@{ Panel = $null; Date = $null; Time = $null; Last = [datetime]::MinValue }
  $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
  $d = New-Object Windows.Controls.TextBox; $d.Width = 84; $d.Margin = '0,0,6,0'; $d.MaxLength = 10; Acc $d 'Date (year-month-day)'; Tip $d 'Date as year-month-day, for example 2025-03-01.'
  $t = New-Object Windows.Controls.TextBox; $t.Width = 62; $t.Margin = '0,0,6,0'; $t.MaxLength = 8; Acc $t 'Time'; Tip $t 'Time such as 09:30, 21:05 or 9pm.'
  $cb = New-Object Windows.Controls.Button; $cb.Content = '...'; $cb.MinWidth = 0; $cb.Width = 23; $cb.Height = 21; $cb.Padding = '0'; Acc $cb 'Pick a date from a calendar'; Tip $cb 'Pick the date from a calendar.'
  $pop = New-Object Windows.Controls.Primitives.Popup; $pop.PlacementTarget = $cb; $pop.Placement = 'Bottom'; $pop.StaysOpen = $false
  $cal = New-Object Windows.Controls.Calendar; $cal.DisplayDateEnd = (Get-Date).Date; $cal.FontFamily = $script:FontUi
  $bd = New-Object Windows.Controls.Border; SetRes $bd ([Windows.Controls.Border]::BackgroundProperty) 'Face'; $bd.Padding = '4'; SetRes $bd ([Windows.Controls.Border]::BorderBrushProperty) 'Dark'; $bd.BorderThickness = '1'; $bd.Child = $cal; $pop.Child = $bd
  $cb.Add_Click({ $pop.IsOpen = $true }.GetNewClosure())
  $cal.Add_SelectedDatesChanged({ if ($cal.SelectedDate) { $d.Text = $cal.SelectedDate.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $pop.IsOpen = $false } }.GetNewClosure())
  $d.Add_LostFocus({ $v = Parse-DateText $d.Text; if ($null -ne $v) { $n = $v.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); if ($d.Text -ne $n) { $d.Text = $n } } }.GetNewClosure())
  $t.Add_LostFocus({ $v = Parse-TimeText $t.Text; if ($null -ne $v) { $n = '{0:00}:{1:00}' -f $v.Hours, $v.Minutes; if ($t.Text -ne $n) { $t.Text = $n } } }.GetNewClosure())
  $sp.Children.Add($d) | Out-Null; $sp.Children.Add($t) | Out-Null; $sp.Children.Add($cb) | Out-Null
  $o.Panel = $sp; $o.Date = $d; $o.Time = $t
  $o | Add-Member -MemberType ScriptProperty -Name Value -Value {
      $dd = Parse-DateText $this.Date.Text; $tt = Parse-TimeText $this.Time.Text
      if ($null -eq $dd -or $null -eq $tt) { return [datetime]::MinValue }
      $dt = $dd.Date + $tt; $l = $this.Last
      if ($l -ne [datetime]::MinValue -and $tt.Hours -eq $l.Hour -and $tt.Minutes -eq $l.Minute) { $dt = $dt.AddSeconds($l.Second) }
      $dt
    } -SecondValue {
      param($v) $v = [datetime]$v; $this.Last = $v
      $this.Date.Text = $v.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $this.Time.Text = $v.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
  $o | Add-Member -MemberType ScriptProperty -Name Valid -Value { [bool]($this.Value -ne [datetime]::MinValue) }
  $o | Add-Member -MemberType ScriptProperty -Name Problem -Value {
      if ($null -eq (Parse-DateText $this.Date.Text)) { return 'Type the date like 2025-03-01 (year-month-day).' }
      if ($null -eq (Parse-TimeText $this.Time.Text)) { return 'Type the time like 09:30, 21:05 or 9pm.' }
      Get-DateProblem $this.Value
    }
  $o.Value = $initial
  $o
}
#endregion

#region classic dialogs (Win98 message boxes): gray, navy title bar, 32px icon, safe default button, Details >> for technical text
function New-ClassicWindow([string]$Title, [double]$Width = 460) {
  $w = New-Object Windows.Window; $w.WindowStyle = 'None'; $w.ResizeMode = 'NoResize'; $w.SizeToContent = 'Height'; $w.Width = $Width; $w.ShowInTaskbar = $false; $w.WindowStartupLocation = 'CenterOwner'; $w.Title = $Title
  $w.FontFamily = $script:FontUi; $w.FontSize = $script:BodySize; $w.UseLayoutRounding = $true; $w.SnapsToDevicePixels = $true
  [Windows.Media.TextOptions]::SetTextFormattingMode($w, 'Display'); [Windows.Media.TextOptions]::SetTextRenderingMode($w, 'Aliased'); [Windows.Media.TextOptions]::SetTextHintingMode($w, 'Fixed'); [Windows.Media.RenderOptions]::SetEdgeMode($w, 'Aliased')
  $w.Resources.MergedDictionaries.Add($script:Res); SetRes $w ([Windows.Window]::BackgroundProperty) 'Face'; SetRes $w ([Windows.Window]::ForegroundProperty) 'Text'
  if ($script:ActiveOwner -and $script:ActiveOwner.IsVisible) { $w.Owner = $script:ActiveOwner }
  $x = (BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}') + '<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>' +
    '<Border x:Name="tb" Margin="2,2,2,0" Height="18" Background="{DynamicResource Navy}"><Grid><TextBlock x:Name="tt" Foreground="{DynamicResource OnNavy}" FontWeight="Bold" FontFamily="Arial" FontSize="11" Margin="4,0,24,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>' +
    '<Button x:Name="cx" Style="{DynamicResource CapBtn}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,2,0" Content="r"/></Grid></Border><Border x:Name="body" Grid.Row="1" Padding="12,12,12,12"/></Grid>' + $script:BvClose
  $x = $x -replace '^<Border ', '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" '
  $root = [Windows.Markup.XamlReader]::Parse($x); $w.Content = $root
  $w.Add_ContentRendered({ Apply-MnScope }); $tt = $root.FindName('tt'); $tt.Text = $Title; $tb = $root.FindName('tb'); $cx = $root.FindName('cx'); Acc $cx 'Close'; Tip $cx 'Close this window'
  $tb.Add_MouseLeftButtonDown({ try { $w.DragMove() } catch {} }.GetNewClosure())
  [pscustomobject]@{ Window = $w; Body = $root.FindName('body'); Close = $cx }
}
# Returns the index of the clicked button (Esc / the X = $Cancel). $Danger = index of a button that stays disabled until $CheckText is ticked.
function Ask([string]$Title, [string]$Heading, [string]$Body = '', [string[]]$Buttons = @('OK'), [int]$Default = 0, [string]$Icon = 'info', [string]$Details = '', [int]$Cancel = -1, [int]$Danger = -1, [string]$CheckText = '') {
  if ($Cancel -lt 0) { $Cancel = $Buttons.Count - 1 }
  $cw = New-ClassicWindow $Title 480; $w = $cw.Window
  $root = New-Object Windows.Controls.StackPanel
  $top = New-Object Windows.Controls.Grid; foreach ($cwid in @('Auto', '*')) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cwid; $top.ColumnDefinitions.Add($cd) }
  $ik = switch ($Icon) { 'error' { 'error' } 'warn' { 'warn' } 'question' { 'question' } default { 'info' } }
  $ic = New-Icon $ik 32; $ic.VerticalAlignment = 'Top'; $ic.Margin = '0,0,14,0'; [Windows.Controls.Grid]::SetColumn($ic, 0); $top.Children.Add($ic) | Out-Null
  $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
  $h = New-Tb $Heading 11 'Text' 'Bold'; $sp.Children.Add($h) | Out-Null
  if ($Body) { $b = New-Tb $Body 11 'Text'; $b.Margin = '0,8,0,0'; $sp.Children.Add($b) | Out-Null }
  $chk = $null
  if ($CheckText) { $chk = New-Object Windows.Controls.CheckBox; $chk.Content = $CheckText; $chk.Margin = '0,12,0,0'; $chk.FontWeight = 'Bold'; Acc $chk $CheckText; $sp.Children.Add($chk) | Out-Null }
  $top.Children.Add($sp) | Out-Null; $root.Children.Add($top) | Out-Null
  $tb = $null
  if ($Details) {
    $tb = New-Object Windows.Controls.TextBox; $tb.IsReadOnly = $true; $tb.Text = $Details; $tb.FontFamily = $script:FontMono; $tb.FontSize = $script:MonoSmall; $tb.Height = 100; $tb.Margin = '0,12,0,0'; $tb.TextWrapping = 'NoWrap'; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'; $tb.VerticalContentAlignment = 'Top'; $tb.Visibility = 'Collapsed'; Acc $tb 'Technical details'; Tip $tb 'The exact text git or backd8 answered.'
    $root.Children.Add($tb) | Out-Null
  }
  $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Center'; $row.Margin = '0,16,0,0'
  $script:askRes = $Cancel; $btns = @()
  for ($i = 0; $i -lt $Buttons.Count; $i++) {
    $bt = New-Button $Buttons[$i] 'normal' 75; $bt.Margin = $(if ($i) { '6,0,0,0' } else { '0' }); $bt.IsDefault = ($i -eq $Default); $bt.IsCancel = ($i -eq $Cancel)
    $bt.ToolTip = ($Buttons[$i] -replace '&', ''); $row.Children.Add($bt) | Out-Null; $btns += $bt
  }
  $script:askMap = @{}; $script:askCancel = $Cancel
  for ($k = 0; $k -lt $btns.Count; $k++) { $script:askMap[$btns[$k]] = $k }
  foreach ($bb in $btns) { $bb.Add_Click([Windows.RoutedEventHandler]{ param($s, $e) $script:askRes = [int]$script:askMap[$s]; $script:askWin.DialogResult = $true }) }
  $script:askWin = $w
  $cw.Close.Add_Click({ $script:askRes = $script:askCancel; $script:askWin.DialogResult = $false })
  if ($Details) {
    $dtl = New-Button 'Details >>' 'normal' 75; $dtl.Margin = '12,0,0,0'; Tip $dtl 'Show or hide the technical text'; $dtl.Add_Click({ if ($tb.Visibility -eq 'Visible') { $tb.Visibility = 'Collapsed'; $this.Content = 'Details >>' } else { $tb.Visibility = 'Visible'; $this.Content = '<< Details' } }.GetNewClosure())
    $cp = New-Button 'Copy' 'normal' 60; $cp.Margin = '6,0,0,0'; Tip $cp 'Copy the technical text to the clipboard'; $cp.Add_Click({ try { [Windows.Clipboard]::SetText($tb.Text) } catch {}; $this.Content = 'Copied' }.GetNewClosure())
    $row.Children.Add($dtl) | Out-Null; $row.Children.Add($cp) | Out-Null
  }
  if ($Danger -ge 0 -and $chk) { $btns[$Danger].IsEnabled = $false; $script:askDanger = $btns[$Danger]; $chk.Add_Checked({ $script:askDanger.IsEnabled = $true }); $chk.Add_Unchecked({ $script:askDanger.IsEnabled = $false }) }
  $root.Children.Add($row) | Out-Null; $cw.Body.Child = $root
  $w.Add_ContentRendered({ try { $btns | Where-Object { $_.IsDefault } | Select-Object -First 1 | ForEach-Object { [void]$_.Focus() } } catch {} })
  if ($script:AskCapture) { $r = & $script:AskCapture $w $Default $Cancel; return $r }
  $script:askRes = $Cancel
  [void]$w.ShowDialog()
  $script:askRes
}
# turns raw git/backd8 messages into: what happened + what to do next. The raw text stays behind "Details >>".
function Explain-Error([string]$m) {
  $h = 'Something went wrong'; $n = 'Press Details to see what git answered. If it is unclear, copy it into a search engine or an issue.'
  switch -Wildcard ($m) {
    'Not a git repository*' { $h = "That folder isn't a git project"; $n = 'Choose the folder that contains your project, or any folder inside it.' }
    'Folder not found*' { $h = "That folder doesn't exist"; $n = 'Check the spelling, or use Browse to pick it. It may have been moved or deleted. Your current project and its waiting changes were left as they are.' }
    'HEAD is detached*' { $h = "You're not on a branch right now"; $n = 'Switch to a branch first (for example: git switch main), then open the folder again.' }
    'A rebase, merge or cherry-pick*' { $h = 'Git is in the middle of another operation'; $n = 'Finish or abort the rebase / merge / cherry-pick in your usual git tool, then try again.' }
    'Start date must be in the past*' { $h = 'The date is in the future'; $n = 'backd8 can only give commits dates that have already passed. Pick an earlier date.' }
    '*must be in the past*' { $h = 'The date is in the future'; $n = 'Pick a date and time that have already passed.' }
    'The date * is too early*' { $h = 'That date is too early for git'; $n = 'Git cannot store dates before 1971. Pick a later date.' }
    'Timed out waiting*' { $h = 'Another backd8 window is busy'; $n = 'Wait a few seconds and try again.' }
    'git push failed*' { $h = 'GitHub did not accept the upload'; $n = 'Common causes: no internet, a protected branch, or someone uploaded newer commits first.' }
    'Git is not installed*' { $h = 'Git is not installed on this PC'; $n = 'Install Git for Windows (winget install --id Git.Git -e), then restart backd8.' }
    'Rewriting*failed*' { $h = 'Could not change the commits'; $n = 'Nothing was changed. For a shallow clone run: git fetch --unshallow' }
    'Your project and GitHub have both changed*' { $h = 'GitHub and your project have both changed'; $n = 'Get the latest from GitHub first, then publish. Nothing was lost.' }
    '*newer change*' { $h = 'GitHub has newer changes than you'; $n = 'Someone (maybe you, on another PC) published after you last looked. Get the latest from GitHub, then publish again.' }
    '*exist nowhere in this repository*' { $h = 'GitHub holds commits you do not have'; $n = 'They may be someone else''s work. Get the latest from GitHub first; replacing GitHub''s version would delete them.' }
    '*is not in the current branch''s history*' { $h = 'That commit is not on this branch'; $n = 'Switch to the branch it belongs to, or pick a commit from the list.' }
    '*index.lock*' { $h = 'Another program is using git in this folder'; $n = 'Close other git tools or editors that may be using the project (or wait a moment), then retry.' }
    '*Permission denied*' { $h = 'A file is in use or protected'; $n = 'Close Visual Studio or any program that has the file open, then retry.' }
    '*Filename too long*' { $h = 'A file path is too long for Windows'; $n = 'Move the project to a shorter folder path, or enable long paths in Windows, then retry.' }
    '*GH001*' { $h = 'GitHub refuses a file over 100 MB'; $n = 'Leave the big file out of the commit (or use Git LFS), then try again.' }
    '*repository not found*' { $h = 'GitHub cannot find this project'; $n = 'Create an empty project at github.com/new with exactly this name, or fix the address. GitHub says this both for missing projects and missing access.' }
    '*Host key verification failed*' { $h = 'GitHub''s SSH key is not trusted yet'; $n = 'Run "ssh -T git@github.com" once in a terminal and accept the key, then retry.' }
    '*git add failed*' { $h = 'Git could not add a file'; $n = 'A file may be locked by another program, too long, or protected. Close programs using the project and retry.' }
    '*Access is denied*' { $h = 'Windows blocked a file'; $n = 'Close programs that use the project (or run backd8 from a folder you own), then retry.' }    'UNTRUSTED PROJECT*' { $h = 'This project can run programs on your PC'; $n = 'Downloaded projects can carry hidden git settings that run programs. Choose another folder, or confirm only if you made this project or trust it.' }
    '*may not write*' { $h = 'This GitHub account cannot write to the project'; $n = 'Ask the owner to add you as a collaborator, sign in with another account, or fork the project and publish there.' }
    '*unusual remote or branch name*' { $h = 'backd8 will not sign in for this project'; $n = 'The remote or branch name is unusual (it could trick a command). Rename it in your git tool, then retry.' }    'Cancelled*' { $h = 'Cancelled'; $n = 'GitHub may or may not have received it - the status in the window shows the truth.' }
    'Nothing to commit*' { $h = 'There is nothing to commit'; $n = 'No files have changed since the last commit.' }
    'Choose at least one file*' { $h = 'Pick at least one file'; $n = 'Tick the files that belong in this commit.' }
    'Write a commit message*' { $h = 'Write a message first'; $n = 'Describe in a few words what you changed.' }
    'Git does not know who you are*' { $h = 'Git needs your name and email'; $n = 'Fill in "Before we start" on the first page, or run the two git config commands shown in Details.' }
  }
  @{ Heading = $h; Next = $n }
}
function Show-Crash($err) {
  $m = if ($err -is [Management.Automation.ErrorRecord]) { "$($err.Exception.Message)`r`n$($err.ScriptStackTrace)" } else { "$err" }
  try { [IO.File]::AppendAllText((Join-Path ([IO.Path]::GetTempPath()) 'backd8-error.log'), "[$((Get-Date).ToString('s'))] $m`r`n") } catch {}
  if (-not $script:Confirm) { throw $err }
  try {
    [void](Ask 'backd8 Setup - something went wrong' 'Sorry - backd8 hit a problem and cannot continue this step.' 'Your files and commits are safe: nothing is changed unless a button says so. Press Details, then Copy, and send the text along if you want help.' @('Close') 0 'error' $m)
  } catch { }
}
function Fail($ex) {
  $m = if ($ex -is [Management.Automation.ErrorRecord]) { $ex.Exception.Message } else { "$ex" }
  if (-not $script:Confirm) { throw $ex }
  $x = Explain-Error $m
  if ($script:eQuiet) { $script:eLastFail = @{ Heading = $x.Heading; Next = $x.Next; Raw = $m }; return }
  if ($m -like 'Cancelled*') { try { Show-Toast 'Cancelled' 'info' $x.Next } catch {}; if (Get-Command Refresh-AfterCancel -ErrorAction SilentlyContinue) { Refresh-AfterCancel }; return }
  [void](Ask 'backd8 Setup' $x.Heading $x.Next @('OK') 0 'error' $m)
  if ($m -like 'Cancelled*' -and (Get-Command Refresh-AfterCancel -ErrorAction SilentlyContinue)) { Refresh-AfterCancel }
}
#endregion

#region persisted UI state (window size, last folder, recent list) next to config.json - never in git. A damaged file is kept as ui.json.bak.
function Get-UiPath { if ($env:BACKD8_UI_STATE) { $env:BACKD8_UI_STATE } else { Join-Path (Split-Path (Get-CfgPath)) 'ui.json' } }
function Load-Ui {
  $p = Get-UiPath
  if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{} }
  try {
    $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
    if (-not "$raw".Trim()) { return [pscustomobject]@{} }
    $x = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($x -is [pscustomobject]) { return $x }
    throw 'not an object'
  } catch { try { Copy-Item -LiteralPath $p -Destination "$p.bak" -Force } catch {}; [pscustomobject]@{} }
}
function Write-Ui($h) { try { $p = Get-UiPath; $tmp = "$p.tmp"; ConvertTo-Json -InputObject $h -Depth 4 | Set-Content -LiteralPath $tmp -Encoding utf8; Move-Item -LiteralPath $tmp -Destination $p -Force } catch {} }
function Ui-Hash { $u = Load-Ui; $h = @{}; foreach ($p in $u.PSObject.Properties) { $h[$p.Name] = $p.Value }; $h }
function Set-UiValue([string]$k, $v) { $h = Ui-Hash; $h[$k] = $v; Write-Ui $h }
function Get-RecentList {
  $seen = @{}; $out = @()
  foreach ($p in @((Load-Ui).recent)) { $s = "$p".Trim(); if (-not $s) { continue }; $k = (Norm $s); if ($seen.ContainsKey($k)) { continue }; if (Test-Path -LiteralPath $s -PathType Container) { $seen[$k] = 1; $out += $s } }
  $out
}
function Save-Ui($win, [string]$key, [string]$lastRepo = '') {
  try {
    $h = Ui-Hash
    if ($win) { $b = $win.RestoreBounds; $h[$key] = @{ x = $b.X; y = $b.Y; w = $b.Width; h = $b.Height; max = ($win.WindowState -eq 'Maximized') } }
    if ($lastRepo) { $h['lastRepo'] = $lastRepo; $rec = @($lastRepo) + @(Get-RecentList | Where-Object { (Norm $_) -ne (Norm $lastRepo) }); $h['recent'] = @($rec | Select-Object -First 8) }
    Write-Ui $h
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
























#region the one window: black header band + black sidebar + gray wizard dialog on the blue backdrop
$script:DlgBorder = (BvOpen 'BvRaiseO' 'BvRaiseI' '{DynamicResource Face}')
$script:Sunk = (BvOpen 'BvSunkO' 'BvSunkI' '{DynamicResource Win}')
$script:SunkPane = '<Border BorderThickness="1" BorderBrush="{DynamicResource BvSunkO}" Padding="4,2">'
$script:MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        x:Name="win" Title="backd8 Setup" Width="960" Height="720" MinWidth="800" MinHeight="560" WindowStyle="None" ResizeMode="CanResize"
        Background="{DynamicResource Backdrop}" Foreground="{DynamicResource Text}" FontFamily="{DynamicResource FontUi}" FontSize="13" TextOptions.TextRenderingMode="Aliased" TextOptions.TextHintingMode="Fixed"
        AllowDrop="True" UseLayoutRounding="True" SnapsToDevicePixels="True" WindowStartupLocation="CenterScreen"
        TextOptions.TextFormattingMode="Display" RenderOptions.EdgeMode="Aliased" RenderOptions.BitmapScalingMode="NearestNeighbor">
 <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="56" ResizeBorderThickness="5" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
 <Window.Resources>
  <Style x:Key="PageTitle" TargetType="TextBlock"><Setter Property="FontFamily" Value="Arial"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontSize" Value="18"/></Style>
  <Style x:Key="Lbl" TargetType="TextBlock"><Setter Property="Margin" Value="0,0,0,3"/></Style>
 </Window.Resources>
 <Grid>
  <Grid x:Name="rootGrid" KeyboardNavigation.TabNavigation="Cycle" Background="{DynamicResource Backdrop}">
   <Grid.RowDefinitions><RowDefinition Height="56"/><RowDefinition Height="*"/></Grid.RowDefinitions>
   <Grid.ColumnDefinitions><ColumnDefinition Width="176"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

   <Border Grid.ColumnSpan="2" Background="{DynamicResource Side}">
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0"><TextBlock Text="backd8" FontFamily="Arial" FontWeight="Bold" FontSize="27" Foreground="{DynamicResource SideText}"/><TextBlock Text="  Setup" FontFamily="Arial" FontSize="27" Foreground="{DynamicResource SideText}"/></StackPanel></Border>

   <!-- sidebar -->
   <Border Grid.Row="1" Background="{DynamicResource Side}"><Grid Margin="12,6,10,12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel x:Name="spSteps" Margin="0,4,0,0"/>
    <StackPanel Grid.Row="1" Margin="0,12,0,0"><Rectangle Height="1" Fill="{DynamicResource SideText}" Margin="0,0,0,10"/>
     <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ContentControl x:Name="sideClock" Margin="0,0,8,0" VerticalAlignment="Top" IsTabStop="False"/>
      <StackPanel Grid.Column="1"><TextBlock x:Name="sideCountLbl" Text="Changes waiting:" Foreground="{DynamicResource SideText}" TextWrapping="Wrap"/><TextBlock x:Name="sideCount" Text="0" FontWeight="Bold" FontSize="16" Foreground="{DynamicResource Yellow}" AutomationProperties.LiveSetting="Polite"/></StackPanel></Grid>
     <Rectangle Height="1" Fill="{DynamicResource SideText}" Margin="0,10,0,10"/></StackPanel>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Focusable="False"><TextBlock x:Name="sideHelp" Foreground="{DynamicResource SideText}" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/></ScrollViewer>
    <StackPanel Grid.Row="3" Margin="0,8,0,0"><StackPanel><Button x:Name="btnAdv" Style="{DynamicResource SmallBtn}" MinWidth="100" HorizontalAlignment="Left" Margin="0,0,0,4"/><Button x:Name="btnHelp" Style="{DynamicResource SmallBtn}" MinWidth="100" HorizontalAlignment="Left"/></StackPanel>
     <TextBlock Text="backd8" FontFamily="Arial" FontStyle="Italic" FontWeight="Bold" FontSize="26" Foreground="{DynamicResource SideText}" Margin="0,10,0,0"/></StackPanel>
   </Grid></Border>

   <!-- wizard dialog -->
   <Border Grid.Row="1" Grid.Column="1" Margin="14,10,14,14">$($script:DlgBorder)
    <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <Border x:Name="titleBar" Margin="3,3,3,0" Height="18" Background="{DynamicResource Navy}"><Grid>
      <TextBlock x:Name="dlgTitle" Text="backd8 Setup Wizard" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource OnNavy}" FontFamily="Arial" FontWeight="Bold" FontSize="11"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,2,0"><Button x:Name="capMin" Style="{DynamicResource CapBtn}" Content="0"/><Button x:Name="capMax" Style="{DynamicResource CapBtn}" Content="1"/><Button x:Name="capClose" Style="{DynamicResource CapBtn}" Content="r" Margin="2,0,0,0"/></StackPanel></Grid></Border>

     <Grid Grid.Row="1" Margin="10,10,10,4"><Grid.ColumnDefinitions><ColumnDefinition Width="128"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border x:Name="artBorder" ClipToBounds="True">$(BvOpen 'BvSunkO' 'BvSunkI' '{DynamicResource Teal}')<Border x:Name="artHost" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,12,0,0"/>$($script:BvClose)</Border>
      <Grid x:Name="pageHost" Grid.Column="2">

       <!-- page 1: choose your project (everything that can be wrong is fixed inline here) -->
       <Grid x:Name="p1"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <TextBlock Style="{DynamicResource PageTitle}" Text="Choose your project"/>
        <TextBlock Grid.Row="1" x:Name="p1Intro" Margin="0,6,0,10" TextWrapping="Wrap" Text="Select the folder that holds your project. It does not have to be on GitHub yet - backd8 can set that up for you."/>
        <ScrollViewer Grid.Row="2" x:Name="p1Scroll" VerticalScrollBarVisibility="Auto" Focusable="False"><StackPanel Margin="0,0,4,0">
         <StackPanel x:Name="spBan"/>
         <TextBlock Style="{DynamicResource Lbl}" Text="Project folder:"/>
         <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="6"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Grid><TextBox x:Name="tbPath"/><TextBlock x:Name="phPath" Text="Type or paste the folder path" Foreground="{DynamicResource Hint}" IsHitTestVisible="False" Margin="5,0,0,0" VerticalAlignment="Center"/></Grid>
          <Button x:Name="btnBrowse" Grid.Column="2"/></Grid>
         <StackPanel x:Name="pEmpty">
          <TextBlock Style="{DynamicResource Lbl}" Text="Recent projects:"/>
          <Grid><ListBox x:Name="lbRecent" Height="112" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/><TextBlock x:Name="recentNone" Text="No recent projects yet." Foreground="{DynamicResource Hint}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid>
          <TextBlock Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource Hint}" Text="Double-click a project to open it. You can also drop a folder anywhere on this window. Nothing changes until you press a button, and every edit can be undone."/></StackPanel>
         <StackPanel x:Name="pPlain" Visibility="Collapsed">
          <TextBlock x:Name="wpFolder" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <TextBlock TextWrapping="Wrap" Margin="0,0,0,8" Text="This folder is not a git project yet. What would you like to do?"/>
          <RadioButton x:Name="rbInit" GroupName="plain" IsChecked="True"><StackPanel><TextBlock x:Name="rbInitT" FontWeight="Bold"/><TextBlock TextWrapping="Wrap" Text="backd8 adds a hidden .git folder inside it in a second; your files are not changed. Afterwards you can save commits with any date and publish them to GitHub."/></StackPanel></RadioButton>
          <RadioButton x:Name="rbOther" GroupName="plain"><StackPanel><TextBlock x:Name="rbOtherT" FontWeight="Bold"/><TextBlock TextWrapping="Wrap" Text="Go back and pick another folder."/></StackPanel></RadioButton>
          <GroupBox x:Name="gInit" Header="Where should it be published? (optional - you can do this later)" Margin="0,4,0,0"><StackPanel>
           <TextBlock TextWrapping="Wrap" Margin="0,0,0,4" Text="Create a new empty project at github.com/new, then paste its address here."/>
           <Grid><TextBox x:Name="tbInit"/><TextBlock x:Name="phInit" Text="https://github.com/you/my-project.git" Foreground="{DynamicResource Hint}" IsHitTestVisible="False" Margin="5,0,0,0" VerticalAlignment="Center"/></Grid>
           <TextBlock x:Name="wpErr" Foreground="{DynamicResource ErrFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Assertive"/>
           <Button x:Name="bInitNew" Style="{DynamicResource LinkBtn}" HorizontalAlignment="Left" Margin="0,4,0,0"/></StackPanel></GroupBox></StackPanel>
         <StackPanel x:Name="pReady" Visibility="Collapsed">
          <GroupBox Header="Selected project"><StackPanel><TextBlock x:Name="p1Name" FontWeight="Bold" TextWrapping="Wrap"/><TextBlock x:Name="p1Info" TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></GroupBox>
          <CheckBox x:Name="chkIgnore" Margin="0,8,0,0" IsChecked="True" Visibility="Collapsed"><StackPanel><TextBlock x:Name="chkIgnoreT" FontWeight="Bold"/><TextBlock x:Name="chkIgnoreD" TextWrapping="Wrap"/></StackPanel></CheckBox>
          <TextBlock x:Name="p1Next" TextWrapping="Wrap" Margin="0,8,0,0"/></StackPanel>
         <StackPanel x:Name="pState" Visibility="Collapsed" Margin="0,8,0,0"><TextBlock x:Name="stateHelp" TextWrapping="Wrap" Margin="0,0,0,8"/><StackPanel x:Name="spActs1"/></StackPanel>
        </StackPanel></ScrollViewer></Grid>

       <!-- page 3: details of the chosen action -->
       <Grid x:Name="p3">
        <!-- 3a: Express = save my changes (one page) -->
        <Grid x:Name="p3x" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
         <TextBlock Style="{DynamicResource PageTitle}" x:Name="xTitle" Text="Save your changes"/>
         <TextBlock Grid.Row="1" x:Name="xSummary" Margin="0,6,0,6" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
         <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Focusable="False"><StackPanel Margin="0,0,4,0">
          <TextBlock x:Name="xMsgLbl" Text="What did you change? (this is the commit message)" Margin="0,0,0,3"/>
          <Grid><TextBox x:Name="nMsg" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="50" VerticalContentAlignment="Top" FontFamily="Courier New, Lucida Console"/><TextBlock x:Name="phNMsg" Text="For example: Add the login page" Foreground="{DynamicResource Hint}" IsHitTestVisible="False" Margin="5,3,0,0"/></Grid>
          <TextBlock x:Name="xSuggest" Foreground="{DynamicResource Hint}" Margin="0,2,0,6" TextWrapping="Wrap"/>
          <TextBlock Text="Date of this commit:" Margin="0,0,0,4"/>
          <UniformGrid Columns="2">
           <RadioButton x:Name="rbNow" GroupName="when" Tag="now" Margin="0,0,8,4"><StackPanel><TextBlock x:Name="rbNowT" FontWeight="Bold"/><TextBlock Text="Use the current time." TextWrapping="Wrap"/></StackPanel></RadioButton>
           <RadioButton x:Name="rbYest" GroupName="when" Tag="yesterday" Margin="0,0,0,4"><StackPanel><TextBlock x:Name="rbYestT" FontWeight="Bold"/><TextBlock Text="One day earlier than now." TextWrapping="Wrap"/></StackPanel></RadioButton>
           <RadioButton x:Name="rbWeek" GroupName="when" Tag="week" Margin="0,0,8,4"><StackPanel><TextBlock x:Name="rbWeekT" FontWeight="Bold"/><TextBlock Text="Seven days earlier." TextWrapping="Wrap"/></StackPanel></RadioButton>
           <RadioButton x:Name="rbMonth" GroupName="when" Tag="month" Margin="0,0,0,4"><StackPanel><TextBlock x:Name="rbMonthT" FontWeight="Bold"/><TextBlock Text="One month earlier." TextWrapping="Wrap"/></StackPanel></RadioButton>
           <RadioButton x:Name="rbCustom" GroupName="when" Tag="custom" Margin="0,0,8,4"><StackPanel><TextBlock x:Name="rbCustomT" FontWeight="Bold"/><TextBlock Text="Type any past date and time." TextWrapping="Wrap"/></StackPanel></RadioButton></UniformGrid>
          <StackPanel x:Name="nDtHost" Margin="0,0,0,0"/><TextBlock x:Name="nDateWarn" Foreground="{DynamicResource ErrFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,3,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Polite"/>
          <Grid Margin="0,8,0,3"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
           <Button x:Name="btnFiles" Style="{DynamicResource LinkBtn}" HorizontalAlignment="Left"/>
           <StackPanel Grid.Column="1" Orientation="Horizontal"><TextBlock x:Name="nCount" Foreground="{DynamicResource Hint}" VerticalAlignment="Center" Margin="0,0,8,0"/><Button x:Name="nAll" Style="{DynamicResource LinkBtn}"/><Button x:Name="nNone" Style="{DynamicResource LinkBtn}"/></StackPanel></Grid>
          <StackPanel x:Name="pFiles" Visibility="Collapsed"><Border Height="104">$(BvOpen 'BvSunkO' 'BvSunkI' '{DynamicResource Win}')<ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False"><StackPanel x:Name="spFiles" Margin="4,3"/></ScrollViewer>$($script:BvClose)</Border></StackPanel>
          <TextBlock x:Name="xWarn" Foreground="{DynamicResource WarnFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Polite"/>
          <StackPanel x:Name="nCard" Visibility="Collapsed" Margin="0,6,0,0"/>
          <Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
           <TextBlock x:Name="nHint" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,10,0" AutomationProperties.LiveSetting="Polite"/><Button x:Name="nBtn" Grid.Column="1"/></Grid>
         </StackPanel></ScrollViewer></Grid>

        <!-- 3b: older commits (edit one, or spread several) -->
        <Grid x:Name="p3e" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
         <TextBlock Style="{DynamicResource PageTitle}" x:Name="eTitle" Text="Change an older commit"/>
         <ScrollViewer Grid.Row="1" x:Name="p3Scroll" VerticalScrollBarVisibility="Auto" Focusable="False"><Grid x:Name="p3Host" Margin="0,6,2,0" MinHeight="470" Height="{Binding ViewportHeight, ElementName=p3Scroll}"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*" MinHeight="96"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <Grid Margin="0,0,0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/></Grid.ColumnDefinitions>
           <StackPanel Orientation="Horizontal"><ToggleButton x:Name="tgAll" MinWidth="44" Margin="0,0,3,0"/><ToggleButton x:Name="tgLocal" Margin="0,0,3,0"/><ToggleButton x:Name="tgEdited"/></StackPanel>
           <Grid Grid.Column="2"><TextBox x:Name="tbFind"/><TextBlock x:Name="phFind" Text="Search..." Foreground="{DynamicResource Hint}" IsHitTestVisible="False" Margin="5,0,0,0" VerticalAlignment="Center"/></Grid></Grid>
          <Grid Grid.Row="1" Margin="0,0,0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="92"/><ColumnDefinition Width="*"/><ColumnDefinition Width="84"/><ColumnDefinition Width="18"/></Grid.ColumnDefinitions>
           <Button x:Name="hSortMark" Style="{DynamicResource HdrBtn}" Padding="0"/><Button x:Name="hSortDate" Grid.Column="1" Style="{DynamicResource HdrBtn}"/><Button x:Name="hSortMsg" Grid.Column="2" Style="{DynamicResource HdrBtn}"/><Button x:Name="hSortId" Grid.Column="3" Style="{DynamicResource HdrBtn}"/></Grid>
          <Grid Grid.Row="2"><ListBox x:Name="lbHist" SelectionMode="Extended" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
           <TextBlock x:Name="tbHistEmpty" TextAlignment="Center" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="20" Visibility="Collapsed" IsHitTestVisible="False"/></Grid>
          <Grid Grid.Row="3" Margin="0,4,0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
           <StackPanel x:Name="legend" Orientation="Horizontal"/><TextBlock x:Name="tHistCount" Grid.Column="1" HorizontalAlignment="Right" Foreground="{DynamicResource Hint}"/></Grid>
          <GroupBox x:Name="gEdit" Grid.Row="4" Header="Selected commit"><Grid>
           <TextBlock x:Name="vNone" TextWrapping="Wrap" Text="Click a commit in the list to change its message or date. Select several with Ctrl or Shift to change their dates together."/>
           <Grid x:Name="vCommit" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel><TextBlock x:Name="eSelHead" FontWeight="Bold" TextWrapping="Wrap"/><TextBlock x:Name="eSelSub" Foreground="{DynamicResource Hint}" TextWrapping="Wrap" Margin="0,1,0,4"/></StackPanel>
            <Grid Grid.Row="1" Margin="0,0,0,3"><TextBlock Text="Message (the first line is the title):" VerticalAlignment="Center"/><Button x:Name="eMsgReset" Style="{DynamicResource LinkBtn}" HorizontalAlignment="Right"/></Grid>
            <TextBox Grid.Row="2" x:Name="eMsg" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="52" VerticalContentAlignment="Top" FontFamily="Courier New, Lucida Console"/>
            <Grid Grid.Row="3" Margin="0,6,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
             <StackPanel x:Name="ePickHost" VerticalAlignment="Center"/><StackPanel Grid.Column="1" Orientation="Horizontal" Margin="8,0,0,0" VerticalAlignment="Center"><Button x:Name="eDateReset" Style="{DynamicResource LinkBtn}"/><TextBlock x:Name="eTz" Foreground="{DynamicResource Hint}" Margin="8,0,0,0" VerticalAlignment="Center"/></StackPanel></Grid>
            <StackPanel Grid.Row="4"><TextBlock x:Name="eWarn" Foreground="{DynamicResource ErrFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Assertive"/><TextBlock x:Name="eHint" Foreground="{DynamicResource WarnFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Polite"/></StackPanel>
            <TextBlock Grid.Row="5" x:Name="eDiff" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" FontFamily="Courier New, Lucida Console"/>
            <Grid Grid.Row="6" Margin="0,6,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
             <TextBlock x:Name="eSaveState" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,10,0" AutomationProperties.LiveSetting="Polite"/>
             <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="eSave" Margin="0,0,6,0"/><Button x:Name="eDisc"/></StackPanel></Grid></Grid>
           <StackPanel x:Name="vMulti" Visibility="Collapsed"><TextBlock x:Name="mHead" FontWeight="Bold"/>
            <TextBlock Text="Give them new dates, oldest to newest, about 1 to 6 hours apart. Only the dates change - the messages stay as they are." TextWrapping="Wrap" Margin="0,2,0,6"/>
            <TextBlock Text="The oldest of them gets this date:" Margin="0,0,0,3"/><StackPanel x:Name="mPickHost"/>
            <TextBlock x:Name="mPrev" FontWeight="Bold" TextWrapping="Wrap" Margin="0,6,0,6" AutomationProperties.LiveSetting="Polite"/><Button x:Name="mBtn" HorizontalAlignment="Left"/></StackPanel>
          </Grid></GroupBox>
         </Grid></ScrollViewer></Grid>
       </Grid>

       <!-- page 4: publish: numbered steps that tick as they run -->
       <Grid x:Name="p4" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <TextBlock Style="{DynamicResource PageTitle}" x:Name="p4Title" Text="Publish to GitHub"/>
        <TextBlock Grid.Row="1" x:Name="p4Intro" Margin="0,6,0,8" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Focusable="False"><StackPanel Margin="0,0,4,0">
         <GroupBox x:Name="gPlan" Header="What would you like to do?"><StackPanel><StackPanel x:Name="spActs4" Margin="0,0,0,6"/><StackPanel x:Name="spPlan"/>
          <ProgressBar x:Name="planBar" Minimum="0" Maximum="100" Value="0" Margin="0,8,0,0" Visibility="Collapsed" AutomationProperties.Name="Progress"/>
          <Grid Margin="0,4,0,0"><TextBlock x:Name="planText" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/><Button x:Name="btnCancelRun" HorizontalAlignment="Right" Visibility="Collapsed"/></Grid></StackPanel></GroupBox>
         <StackPanel x:Name="pubFail" Visibility="Collapsed" Margin="0,8,0,0"><StackPanel Orientation="Horizontal"><ContentControl x:Name="failIcon" Margin="0,0,8,0" IsTabStop="False" VerticalAlignment="Top"/><StackPanel><TextBlock x:Name="failHead" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="420" AutomationProperties.LiveSetting="Assertive"/><TextBlock x:Name="failText" TextWrapping="Wrap" MaxWidth="420" Margin="0,3,0,0"/></StackPanel></StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0"><Button x:Name="btnRetry" Margin="0,0,6,0"/><Button x:Name="btnFailDetails"/></StackPanel>
          <TextBox x:Name="failRaw" IsReadOnly="True" Height="80" Margin="0,6,0,0" Visibility="Collapsed" FontFamily="Courier New, Lucida Console" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/></StackPanel>
         <StackPanel x:Name="pubWarnBox" Margin="0,8,0,0" Visibility="Collapsed"/>
         <GroupBox x:Name="gDecide" Header="GitHub already has a different version" Margin="0,8,0,0" Visibility="Collapsed"><StackPanel>
          <RadioButton x:Name="rbKeep" GroupName="decide" IsChecked="True"><StackPanel><TextBlock x:Name="rbKeepT" FontWeight="Bold"/><TextBlock x:Name="rbKeepD" TextWrapping="Wrap"/></StackPanel></RadioButton>
          <RadioButton x:Name="rbReplace" GroupName="decide"><StackPanel><TextBlock x:Name="rbReplaceT" FontWeight="Bold"/><TextBlock x:Name="rbReplaceD" TextWrapping="Wrap"/></StackPanel></RadioButton></StackPanel></GroupBox>
         <Button x:Name="btnGetLatest" HorizontalAlignment="Left" Margin="0,8,0,0" Height="26" Visibility="Collapsed"/>
         <StackPanel x:Name="pubConflict" Margin="0,8,0,0" Visibility="Collapsed"/>
         <GroupBox x:Name="gAcct" Header="Which GitHub account should this project use?" Margin="0,8,0,0" Visibility="Collapsed"><StackPanel><TextBlock x:Name="acctIntro" TextWrapping="Wrap" Margin="0,0,0,4"/><StackPanel x:Name="spAccounts"/><Button x:Name="btnUseAcct" HorizontalAlignment="Left" Margin="0,4,0,0"/></StackPanel></GroupBox>
         <StackPanel x:Name="pubProb" Margin="0,8,0,0" Visibility="Collapsed"><StackPanel Orientation="Horizontal"><ContentControl x:Name="probIcon" Margin="0,0,8,0" IsTabStop="False" VerticalAlignment="Top"/><TextBlock x:Name="probText" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="420" AutomationProperties.LiveSetting="Assertive"/></StackPanel>
          <StackPanel x:Name="probFix" Margin="0,6,0,0"><TextBlock Text="GitHub address of this project:" Margin="0,0,0,3"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="6"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="tbFix"/><Button x:Name="btnFixAddr" Grid.Column="2"/></Grid>
           <TextBlock x:Name="fixErr" Foreground="{DynamicResource ErrFg}" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Assertive"/></StackPanel>
          <Button x:Name="btnProbLink" HorizontalAlignment="Left" Margin="0,6,0,0"/></StackPanel>
         <GroupBox Header="GitHub status and sign-in" Margin="0,8,0,0"><StackPanel>
          <StackPanel Orientation="Horizontal"><ContentControl x:Name="pubIcon" Margin="0,0,8,0" IsTabStop="False" VerticalAlignment="Top"/><TextBlock x:Name="pubHead" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="440" AutomationProperties.LiveSetting="Polite"/></StackPanel>
          <TextBlock x:Name="pubDetail" TextWrapping="Wrap" Margin="0,4,0,0"/>
          <TextBlock x:Name="pubPend" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" Foreground="{DynamicResource WarnFg}"/>
          <TextBlock x:Name="pubMeta" TextWrapping="Wrap" Margin="0,4,0,0" Foreground="{DynamicResource Hint}"/>
          <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><ContentControl x:Name="accIcon" Margin="0,0,8,0" IsTabStop="False"/><TextBlock x:Name="eAcc" FontWeight="Bold" VerticalAlignment="Center" AutomationProperties.LiveSetting="Polite"/></StackPanel>
          <TextBlock x:Name="accWhere" Foreground="{DynamicResource Hint}" TextWrapping="Wrap" Margin="0,2,0,0"/>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0"><Button x:Name="btnSign" Margin="0,0,6,0"/><Button x:Name="btnCheck"/></StackPanel>
          <TextBox x:Name="eAdvice" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="54" Margin="0,6,0,0" VerticalContentAlignment="Top"/></StackPanel></GroupBox>
        </StackPanel></ScrollViewer></Grid>

       <!-- page 5: complete -->
       <Grid x:Name="p5" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <TextBlock Style="{DynamicResource PageTitle}" x:Name="finTitle" Text="backd8 is complete"/>
        <StackPanel Grid.Row="1" Margin="0,12,0,0"><StackPanel x:Name="finList"/><StackPanel x:Name="spActs5" Margin="0,8,0,0"/><TextBlock x:Name="finMsg" TextWrapping="Wrap" Margin="0,8,0,0"/>
         <StackPanel Orientation="Horizontal" Margin="0,12,0,0"><Button x:Name="btnOpenGh" Margin="0,0,6,0" Visibility="Collapsed"/><Button x:Name="btnAnother"/></StackPanel>
         <TextBlock Margin="0,16,0,0" TextWrapping="Wrap" Text="Click Finish to close backd8, or Back to keep working on this project."/></StackPanel></Grid>
      </Grid>
     </Grid>

     <!-- inline result (toast with next step, Undo) -->
     <Border x:Name="resBar" Grid.Row="2" Margin="10,0,10,4" Visibility="Collapsed">$(BvOpen 'BvEtchO' 'BvEtchI')
      <Grid Margin="6,5"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <ContentControl x:Name="resIcon" Margin="0,0,8,0" VerticalAlignment="Top" IsTabStop="False"/>
       <StackPanel Grid.Column="1"><TextBlock x:Name="resHead" FontWeight="Bold" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/><TextBlock x:Name="resDetail" TextWrapping="Wrap" Margin="0,2,0,0"/><WrapPanel x:Name="resActs" Margin="0,3,0,0"/></StackPanel>
       <Button x:Name="resDismiss" Grid.Column="2" Style="{DynamicResource SmallBtn}" VerticalAlignment="Top" MinWidth="0" Width="21" Content="r" FontFamily="Marlett"/></Grid>$($script:BvClose)</Border>

     <Border x:Name="logCard" Grid.Row="3" Margin="10,0,10,4" Visibility="Collapsed"><TextBox x:Name="eLog" IsReadOnly="True" Height="96" FontFamily="Courier New, Lucida Console" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" VerticalContentAlignment="Top"/></Border>

     <Grid Grid.Row="4" Margin="10,0,10,6"><Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="3*"/><ColumnDefinition Width="4*"/></Grid.ColumnDefinitions><Border BorderThickness="1,1,0,0" BorderBrush="{DynamicResource BvSunkOa}" Margin="0,0,2,0"><Border BorderThickness="0,0,1,1" BorderBrush="{DynamicResource BvSunkOb}" Padding="4,2"><TextBlock x:Name="stBranch" TextTrimming="CharacterEllipsis" AutomationProperties.LiveSetting="Polite"/></Border></Border><Border Grid.Column="1" BorderThickness="1,1,0,0" BorderBrush="{DynamicResource BvSunkOa}" Margin="0,0,2,0"><Border BorderThickness="0,0,1,1" BorderBrush="{DynamicResource BvSunkOb}" Padding="4,2"><TextBlock x:Name="stGit" TextTrimming="CharacterEllipsis" AutomationProperties.LiveSetting="Polite"/></Border></Border><Border Grid.Column="2" BorderThickness="1,1,0,0" BorderBrush="{DynamicResource BvSunkOa}"><Border BorderThickness="0,0,1,1" BorderBrush="{DynamicResource BvSunkOb}" Padding="4,2"><TextBlock x:Name="stPend" TextTrimming="CharacterEllipsis" AutomationProperties.LiveSetting="Polite"/></Border></Border></Grid>

     <Border Grid.Row="5" Margin="10,0,10,10"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Border Height="2" Margin="0,0,0,10">$(BvOpen 'BvEtchO' 'BvEtchI')$($script:BvClose)</Border>
      <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="lnkUndo" Style="{DynamicResource LinkBtn}" Margin="0,0,10,0"/><Button x:Name="lnkDetails" Style="{DynamicResource LinkBtn}"/></StackPanel>
       <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="btnBack"/><Button x:Name="btnNext" IsDefault="True" Margin="0,0,10,0"/><Button x:Name="btnCancel" IsCancel="True"/></StackPanel></Grid></Grid></Border>
    </Grid>$($script:BvClose)</Border>
  </Grid>

  <!-- busy dialog: classic progress -->
  <Grid x:Name="busy" Background="#50000000" Visibility="Collapsed">
   <Border Width="440" HorizontalAlignment="Center" VerticalAlignment="Center">$($script:DlgBorder)
    <StackPanel><Border Margin="3,3,3,0" Height="18" Background="{DynamicResource Navy}"><TextBlock Text="backd8 Setup" Foreground="{DynamicResource OnNavy}" FontFamily="Arial" FontWeight="Bold" VerticalAlignment="Center" Margin="4,0"/></Border>
     <StackPanel Margin="16,14,16,14"><TextBlock x:Name="busyTitle" Text="Working..." FontWeight="Bold" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
      <StackPanel x:Name="busySteps" Margin="0,8,0,0"/>
      <TextBlock x:Name="busyText" Margin="0,8,0,8" TextWrapping="Wrap"/>
      <ProgressBar x:Name="busyBar" Minimum="0" Maximum="100" Value="0" AutomationProperties.Name="Progress"/>
      <Button x:Name="btnCancelBusy" HorizontalAlignment="Right" Margin="0,12,0,0"/></StackPanel></StackPanel>$($script:BvClose)</Border></Grid>
 </Grid>
</Window>
"@
$script:win = [Windows.Markup.XamlReader]::Parse($script:MainXaml)
$script:win.Resources.MergedDictionaries.Add($script:Res)
foreach ($m in [regex]::Matches($script:MainXaml, 'x:Name="(\w+)"')) { $n = $m.Groups[1].Value; Set-Variable -Name $n -Value ($script:win.FindName($n)) -Scope Script }
$f = $script:win; $script:ActiveOwner = $f
$script:win.Icon = $null
#endregion















#region view glue: labels, tooltips, sidebar, banners, wizard pages, result bar, busy dialog
function Format-Plural([int]$n, [string]$one, [string]$many = '') { if ($n -eq 1) { "1 $one" } else { "$n $(if ($many) { $many } else { $one + 's' })" } }
function Is-Are([int]$n) { if ($n -eq 1) { 'is' } else { 'are' } }
function Fmt([datetime]$d) { $d.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
function Get-RelDate([datetime]$d) {
  $s = ((Get-Date) - $d).TotalSeconds
  if ($s -lt 0) { return 'in the future' }
  if ($s -lt 90) { return 'just now' }
  $m = [math]::Floor($s / 60); if ($m -lt 60) { return "$m minutes ago" }
  $h = [math]::Floor($m / 60); if ($h -lt 24) { return $(if ($h -eq 1) { '1 hour ago' } else { "$h hours ago" }) }
  $dd = [math]::Floor($h / 24); if ($dd -eq 1) { return 'yesterday' }; if ($dd -lt 14) { return "$dd days ago" }
  if ($dd -lt 60) { return "$([math]::Floor($dd / 7)) weeks ago" }
  if ($dd -lt 730) { return "$([math]::Floor($dd / 30)) months ago" }
  "$([math]::Floor($dd / 365)) years ago"
}
function New-TbI([string]$text, [string]$weight = 'Normal') { $t = New-Object Windows.Controls.TextBlock; $t.Text = $text; $t.FontWeight = $weight; $t }
function Set-MnTb($tb, [string]$label) {
  $tb.Inlines.Clear(); $i = $label.IndexOf('&')
  if ($i -lt 0 -or $i -ge $label.Length - 1) { [void]$tb.Inlines.Add((New-Object Windows.Documents.Run($label))); return }
  if ($i -gt 0) { [void]$tb.Inlines.Add((New-Object Windows.Documents.Run($label.Substring(0, $i)))) }
  $u = New-Object Windows.Documents.Run([string]$label[$i + 1]); $u.TextDecorations = [Windows.TextDecorations]::Underline; [void]$tb.Inlines.Add($u)
  if ($i + 2 -lt $label.Length) { [void]$tb.Inlines.Add((New-Object Windows.Documents.Run($label.Substring($i + 2)))) }
}
function Set-RadioMn($rb, $tb, [string]$label, [string]$desc) {
  Set-MnTb $tb $label; $k = ([string]$label[$label.IndexOf('&') + 1]).ToUpperInvariant(); Reg-Mn $k $rb
  Acc $rb (($label -replace '&', '') + ' - ' + $desc)
}
function Hdr-Text($b, [string]$text, [string]$col, [string]$cur) { $b.Content = $text + $(if ($script:eSort -and $script:eSort.Col -eq $col) { " $(if ($script:eSort.Desc) { $script:G.Down } else { $script:G.Up })" } else { '' }) }

# labels, tooltips and accessible names for every fixed control
foreach ($spec in @(
    @($btnBrowse, 'Bro&wse...', 'Choose the project folder in a folder dialog. You can also drop a folder on this window.'), @($btnAdv, '&Advanced...', 'Advanced options: the optional automatic back-dating of every new commit on this PC (Alt+A).'),
    @($btnHelp, '&Help', 'How backd8 works (F1).'), @($btnBack, '< &Back', 'Go back to the previous step.'), @($btnNext, '&Next >', 'Go to the next step.'), @($btnCancel, 'Cancel', 'Close backd8. You are asked first if changes would be lost.'),
    @($bInitNew, 'Open github.com/new', 'Open github.com/new in your browser to create an empty project to publish to.'), @($nAll, 'Select all', 'Tick every file in the list.'), @($nNone, 'Select none', 'Untick every file in the list.'),
    @($nBtn, 'Sa&ve only (publish later)', 'A commit is one saved version of your project. This saves the ticked files with your message and date, on this computer only. Nothing is sent to GitHub yet.'),
    @($eSave, '&Keep this change', 'Keep this message and date as a waiting change. Nothing is rewritten until you press Next (Apply).'), @($eDisc, '&Discard my change', 'Throw away your waiting change to this commit and show the original message and date again.'),
    @($eMsgReset, 'Reset', 'Put back the original message.'), @($eDateReset, 'Reset', 'Put back the original date and time.'),
    @($mBtn, 'Change dates of the&se commits', 'Give the selected commits new, ascending dates about 1 to 6 hours apart. Messages stay as they are.'),
    @($btnSign, 'Sign &in to GitHub...', 'Sign in to GitHub in a separate window (browser, GitHub CLI or an SSH test). backd8 never stores your password or token.'), @($btnCheck, '&Check again', 'Check again whether this PC may publish to GitHub (a harmless test).'),
    @($btnGetLatest, 'Get the late&st from GitHub', 'Download what is new on GitHub and combine it with your project. Nothing on GitHub is replaced or deleted.'), @($btnOpenGh, '&Open on GitHub', 'Open the project on github.com in your browser.'),
    @($lnkUndo, 'Undo last &edit', 'Put the project back to how it was before your last Apply (Ctrl+Z).'), @($lnkDetails, 'Show activity &log', 'Show or hide the activity log.'), @($btnCancelBusy, 'Cancel', 'Stop what backd8 is doing.'), @($btnCancelRun, 'Cancel', 'Stop what backd8 is doing. GitHub may or may not have received it - the status shows the truth.'), @($btnFiles, '', 'Show or hide the list of changed files.'), @($btnRetry, 'Retry', 'Try the failed step again.'), @($btnFailDetails, 'Details >>', 'Show or hide the technical text.'), @($btnUseAcct, '&Use this account', 'Remember this GitHub account for this project, so publishing never has to ask which account.'), @($btnFixAddr, 'Fix the a&ddress', 'Use the corrected GitHub address for this project.'), @($btnProbLink, 'Open github.com/new', 'Open GitHub in your browser.'), @($btnAnother, 'Do ano&ther', 'Go back to the first question and do something else.'),
    @($hSortMark, '', 'Sort by where the commit lives (GitHub or only this computer).'), @($hSortDate, 'When', 'Sort by date. Click again to reverse.'), @($hSortMsg, 'Commit message', 'Sort by message.'), @($hSortId, 'Commit ID', 'Sort by commit ID.'),
    @($tgAll, 'All', 'Show every commit.'), @($tgLocal, 'Not on GitHub yet', 'Show only commits that exist only on this computer.'), @($tgEdited, 'Edited', 'Show only commits with a waiting change.'),
    @($capMin, '', 'Minimize'), @($capMax, '', 'Maximize or restore'), @($capClose, '', 'Close backd8'), @($resDismiss, '', 'Dismiss this message'))) {
  $c = $spec[0]; $lbl = $spec[1]; if ($lbl) { Set-Mn $c $lbl } ; if ($lbl -eq '') { } ; Tip $c $spec[2]
  if (-not $lbl) { Acc $c $spec[2].Split('.')[0] }
}
Set-RadioMn $rbInit $rbInitT '&Turn this folder into a project' 'backd8 adds a hidden .git folder; your files are not changed.'; Set-RadioMn $rbOther $rbOtherT 'Choose a &different folder' 'Go back and pick another folder.'
Set-RadioMn $rbNow $rbNowT 'N&ow' 'Use the current time.'; Set-RadioMn $rbYest $rbYestT '&Yesterday' 'One day earlier than now.'; Set-RadioMn $rbWeek $rbWeekT '1 &week ago' 'Seven days earlier.'; Set-RadioMn $rbMonth $rbMonthT '1 &month ago' 'One month earlier.'; Set-RadioMn $rbCustom $rbCustomT 'Pick a &date...' 'Type any past date and time.'
foreach ($rb in @($rbInit, $rbOther, $rbNow, $rbYest, $rbWeek, $rbMonth, $rbCustom, $rbKeep, $rbReplace)) { Tip $rb ([Windows.Automation.AutomationProperties]::GetName($rb)) }
$capMin.Add_Click({ $f.WindowState = 'Minimized' }); $capMax.Add_Click({ $f.WindowState = $(if ($f.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) }); $capClose.Add_Click({ $f.Close() })
$titleBar.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 2) { $f.WindowState = $(if ($f.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) } else { try { $f.DragMove() } catch {} } })
foreach ($c in @($tbPath, $tbInit, $tbFind, $nMsg, $eMsg, $eLog, $eAdvice)) { }
Acc $tbPath 'Project folder' 'Folder of your project. Press Enter to open it, or drop a folder on the window.'; Tip $tbPath 'Folder of your project (any folder inside it works). Press Enter to open it.'
Acc $tbInit 'GitHub address (optional)'; Tip $tbInit 'The address of an empty project you created on GitHub, for example https://github.com/you/my-project.git'
Acc $tbFind 'Search commits'; Tip $tbFind 'Type part of a message, author, date or commit ID (Ctrl+F).'
Acc $lbHist 'Your project history' 'List of commits. Use the arrow keys, Ctrl or Shift to select one or several.'; Tip $lbHist 'Hover a row for the full message and exact date. Select several commits with Ctrl or Shift to change their dates together. Ctrl+C copies commit IDs. Right-click for more.'
Acc $lbRecent 'Recent projects' 'Press Enter or double-click to open a project.'; Tip $lbRecent 'Projects you opened before. Double-click or press Enter to open one.'
Acc $nMsg 'Message for the new commit'; Tip $nMsg 'A short sentence about what you changed, for example "Add login page". The first line is the title.'
Acc $eMsg 'Commit message'; Tip $eMsg 'Change the message here, then press Keep this change. A change is kept if you click another commit.'
Acc $eLog 'Activity log'; Tip $eLog 'What backd8 did, step by step.'; Acc $eAdvice 'Advice for signing in'; Tip $eAdvice 'What to do if signing in does not work.'
Acc $eAcc 'GitHub sign-in status'; Tip $eAcc 'Whether this PC may publish to GitHub (checked with a harmless test when the project is opened).'
Acc $busyBar 'Progress'; Acc $spFiles 'Changed files'
$sideClock.Content = New-Icon 'clock' 22
$f.FontSize = $script:BodySize
foreach ($c in @($nMsg, $eMsg, $eLog, $eDiff, $failRaw)) { $c.FontFamily = $script:FontMono; $c.FontSize = $script:MonoSize }
$sideCountLbl.FontFamily = $script:FontCaps; $sideCountLbl.FontSize = $script:CapsSize; $sideCountLbl.FontWeight = 'Bold'; $sideCountLbl.Text = 'CHANGES WAITING'

# ---- sidebar steps (current = yellow + bold, done = white with a check)
$script:eAction = 'express'

$script:StepDefs = @(@('Choose your project', 'folder'), @('Change dates and messages', 'page'), @('Sign in to GitHub', 'key'), @('Publish to GitHub', 'globe'))
$script:SideRows = @()
for ($i = 0; $i -lt 4; $i++) {
  $g = New-Object Windows.Controls.Grid; $g.Margin = '0,0,0,7'
  foreach ($w in @('22', '*')) { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $w; $g.ColumnDefinitions.Add($c) }
  $ih = New-Object Windows.Controls.ContentControl; $ih.VerticalAlignment = 'Top'; $ih.IsTabStop = $false
  $tx = New-Object Windows.Controls.TextBlock; $tx.TextWrapping = 'Wrap'; $tx.Text = $script:StepDefs[$i][0]; [Windows.Controls.Grid]::SetColumn($tx, 1)
  $g.Children.Add($ih) | Out-Null; $g.Children.Add($tx) | Out-Null; $spSteps.Children.Add($g) | Out-Null
  $n = $i + 1; $g.Add_MouseLeftButtonUp({ param($s, $e) $k = [int]$s.Tag; if ($k -lt $script:wizPage -or $script:wizPage -eq 5) { Go-Page $k } }); $g.Tag = $n; $g.Background = [Windows.Media.Brushes]::Transparent
  $script:SideRows += [pscustomobject]@{ Grid = $g; Icon = $ih; Text = $tx; Index = $n }
}
$script:wizPage = 1

#endregion

#region banners (stacked on page 1): icon, title, detail, optional extra row, actions
function New-Banner {
  $o = [pscustomobject]@{ Border = $null; Icon = $null; Title = $null; Detail = $null; Extra = $null; Actions = $null; Err = $null }
  $x = '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,0,8" Visibility="Collapsed">' + (BvOpen 'BvEtchO' 'BvEtchI') +
    '<Grid Margin="6,5"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><ContentControl x:Name="ic" Margin="0,0,8,0" VerticalAlignment="Top" IsTabStop="False"/>' +
    '<StackPanel Grid.Column="1"><TextBlock x:Name="tt" FontWeight="Bold" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/><TextBlock x:Name="dd" TextWrapping="Wrap" Margin="0,2,0,0"/><WrapPanel x:Name="ex" Margin="0,6,0,0" Visibility="Collapsed"/>' +
    '<TextBlock x:Name="er" FontWeight="Bold" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed" AutomationProperties.LiveSetting="Assertive"/><WrapPanel x:Name="ac" Margin="0,6,0,0"/></StackPanel></Grid>' + $script:BvClose + '</Border>'
  $b = [Windows.Markup.XamlReader]::Parse($x); $spBan.Children.Add($b) | Out-Null
  SetRes $b.FindName('er') ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'
  $o.Border = $b; $o.Icon = $b.FindName('ic'); $o.Title = $b.FindName('tt'); $o.Detail = $b.FindName('dd'); $o.Extra = $b.FindName('ex'); $o.Actions = $b.FindName('ac'); $o.Err = $b.FindName('er'); $o
}
function Set-Banner($b, [string]$kind, [string]$glyph, [string]$title, [string]$detail) {
  $b.Icon.Content = (New-Icon (Kind-Icon $kind) 24); $b.Title.Text = $title; $b.Detail.Text = $detail; $b.Detail.Visibility = $(if ($detail) { 'Visible' } else { 'Collapsed' })
  [Windows.Automation.AutomationProperties]::SetLiveSetting($b.Title, $(if ($kind -eq 'danger') { 'Assertive' } else { 'Polite' }))
}
function New-Field([string]$placeholder, [double]$w, [string]$name) {
  $g = New-Object Windows.Controls.Grid; $g.Width = $w; $g.Margin = '0,0,6,4'
  $tb = New-Object Windows.Controls.TextBox; $ph = New-Tb $placeholder 11 'Hint' 'Normal' $false; $ph.IsHitTestVisible = $false; $ph.Margin = '5,0,0,0'; $ph.VerticalAlignment = 'Center'
  $g.Children.Add($tb) | Out-Null; $g.Children.Add($ph) | Out-Null; Acc $tb $name; Tip $tb $name
  [pscustomobject]@{ Grid = $g; Box = $tb; Ph = $ph }
}
$bnPre = New-Banner; $bnDet = New-Banner; $bnCfg = New-Banner; $bnHook = New-Banner; $bnLink = New-Banner; $bnSub = New-Banner
$bGitHelp = New-Button 'How to &install Git' 'normal'; $bGitHelp.Margin = '0,0,6,0'; Tip $bGitHelp 'How to install Git for Windows (the free tool that keeps your project history).'; $bnPre.Actions.Children.Add($bGitHelp) | Out-Null
$fName = New-Field 'Your name' 160 'Your name for git commits'; $fMail = New-Field 'you@example.com' 190 'Your email address for git commits'
$bSaveId = New-Button '&Save my name and email' 'normal'; $bSaveId.Margin = '0,0,0,4'; Tip $bSaveId 'Save your name and email for all projects on this PC (git config --global).'
foreach ($c in @($fName.Grid, $fMail.Grid, $bSaveId)) { $bnPre.Extra.Children.Add($c) | Out-Null }
$tbName = $fName.Box; $tbMail = $fMail.Box; $lIdErr = $bnPre.Err
$bCfgReset = New-Button '&Reset settings' 'normal'; Tip $bCfgReset "Move the damaged settings file aside so backd8 starts fresh (your projects and commits are not touched)."; $bnCfg.Actions.Children.Add($bCfgReset) | Out-Null
$bHookRemove = New-Button 'Re&move it' 'normal'; $bHookRemove.Margin = '0,0,6,0'; Tip $bHookRemove 'Remove the automatic back-dating hook from this PC.'; $bHookKeep = New-Button '&Keep it' 'normal'; Tip $bHookKeep 'Keep it and hide this notice.'
$bnHook.Actions.Children.Add($bHookRemove) | Out-Null; $bnHook.Actions.Children.Add($bHookKeep) | Out-Null
$fLink = New-Field 'https://github.com/you/my-project.git' 300 'GitHub address of your project'; $bLink = New-Button '&Connect' 'normal'; $bLink.Margin = '0,0,6,4'; Tip $bLink 'Link this project to the GitHub address you typed.'; $bNewRepo = New-Button 'Open github.com/new' 'normal'; $bNewRepo.Margin = '0,0,0,4'; Tip $bNewRepo 'Open github.com/new in your browser to create an empty project.'
foreach ($c in @($fLink.Grid, $bLink, $bNewRepo)) { $bnLink.Extra.Children.Add($c) | Out-Null }
$tbLink = $fLink.Box; $lLinkErr = $bnLink.Err
$script:Banners = @($bnPre, $bnDet, $bnCfg, $bnHook, $bnLink, $bnSub)
#endregion

#region result bar (inline toast with the next step and Undo), busy dialog with a blocky progress bar
$script:ResTimer = $null
function Show-Result([string]$kind, [string]$head, [string]$detail = '', [object[]]$Actions = @(), [bool]$Sticky = $false) {
  $resIcon.Content = (New-Icon (Kind-Icon $kind) 24); $resHead.Text = $head; $resDetail.Text = $detail; $resDetail.Visibility = $(if ($detail) { 'Visible' } else { 'Collapsed' })
  [Windows.Automation.AutomationProperties]::SetLiveSetting($resHead, $(if ($kind -eq 'danger') { 'Assertive' } else { 'Polite' }))
  $resActs.Children.Clear()
  foreach ($a in $Actions) { $b = New-Button $a.Text 'link'; $b.Margin = '0,0,12,0'; Tip $b ($a.Tip); if (-not $a.Tip) { Tip $b ($a.Text -replace '&', '') }; $b.Tag = $a.Click; $b.Add_Click({ $c = $this.Tag; $resBar.Visibility = 'Collapsed'; & $c }); [void]$resActs.Children.Add($b) }
  $resActs.Visibility = $(if ($Actions.Count) { 'Visible' } else { 'Collapsed' })
  $resBar.Visibility = 'Visible'
  if ($script:ResTimer) { $script:ResTimer.Stop() }
  if ($script:Confirm -and -not $Sticky -and $kind -ne 'danger') {
    $script:ResTimer = New-Object Windows.Threading.DispatcherTimer; $script:ResTimer.Interval = [TimeSpan]::FromSeconds($(if ($Actions.Count) { 25 } else { 10 }))
    $script:ResTimer.Add_Tick({ $resBar.Visibility = 'Collapsed'; $script:ResTimer.Stop() }); $script:ResTimer.Start()
  }
}
function Show-Toast([string]$text, [string]$kind = 'ok', [string]$detail = '') { Show-Result $(if ($kind -eq 'danger') { 'danger' } elseif ($kind -eq 'ok') { 'ok' } else { 'info' }) $text $detail }
$resDismiss.Add_Click({ $resBar.Visibility = 'Collapsed' })
$script:BgCancel = $false; $script:eCancelled = $false
function Stop-GitChildren {
  try {
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue); $kids = @{}
    foreach ($p in $all) { $k = [int]$p.ParentProcessId; if (-not $kids.ContainsKey($k)) { $kids[$k] = New-Object Collections.ArrayList }; [void]$kids[$k].Add([int]$p.ProcessId) }
    $q = New-Object Collections.Queue; $q.Enqueue([int]$PID); $seen = @{ [int]$PID = 1 }; $victims = @()
    while ($q.Count) { $x = $q.Dequeue(); if ($kids.ContainsKey($x)) { foreach ($c in $kids[$x]) { if (-not $seen.ContainsKey($c)) { $seen[$c] = 1; $victims += $c; $q.Enqueue($c) } } } }
    foreach ($v in $victims) { & taskkill.exe /PID $v /T /F 2>&1 | Out-Null }
  } catch {}
}
function Render-ERun {
  if (-not $script:eSteps) { $busySteps.Children.Clear(); return }
  $busySteps.Children.Clear()
  foreach ($s in $script:eSteps) {
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,3'
    $ih = New-Object Windows.Controls.ContentControl; $ih.Width = 18; $ih.IsTabStop = $false
    switch ($s[0]) { 'ok' { $ih.Content = New-Icon 'check' 14 } 'run' { $t = New-Tb '>>' 11 'Navy' 'Bold' $false; $ih.Content = $t } 'fail' { $ih.Content = New-Icon 'error' 14 } 'skip' { $ih.Content = New-Tb '-' 11 'Hint' 'Normal' $false } default { $ih.Content = New-Tb 'o' 11 'Hint' 'Normal' $false } }
    $tx = New-Tb $s[1] 11 'Text' $(if ($s[0] -eq 'run') { 'Bold' } else { 'Normal' }) $false
    $row.Children.Add($ih) | Out-Null; $row.Children.Add($tx) | Out-Null; $busySteps.Children.Add($row) | Out-Null
    Acc $row ("$($s[1]): " + $(switch ($s[0]) { 'ok' { 'done' } 'run' { 'working' } 'fail' { 'failed' } 'skip' { 'skipped' } default { 'waiting' } }))
  }
}
function Set-ERunStep([int]$i, [string]$state) { if ($script:eSteps) { $script:eSteps[$i][0] = $state; Render-ERun; $busyBar.Value = [math]::Min(100, 100.0 * @($script:eSteps | Where-Object { $_[0] -eq 'ok' }).Count / $script:eSteps.Count); if ($script:Confirm) { DoEvents } } }
function Start-ERun([string[]]$names) { $script:eRunning = $true; $script:eSteps = @(); foreach ($n in $names) { $script:eSteps += , @('todo', $n) }; Set-EBusy $true 'Saving and publishing...' $false; Render-ERun }
function Stop-ERun { $script:eRunning = $false; $script:eSteps = $null; Set-EBusy $false }
$script:eInline = $false; $script:ePlan = $null; $script:ePlanRunning = $false; $script:eQuiet = $false; $script:eLastFail = $null
function Set-EBusy([bool]$on, [string]$label = 'Working...', [bool]$cancellable = $false) {
  if ($on) {
    $script:eBusy = $true
    if ($script:eInline) { $planBar.Visibility = 'Visible'; $planBar.Value = 0; $planText.Text = $label; $btnCancelRun.Visibility = Vis $cancellable; $btnCancelRun.IsEnabled = $true; $btnNext.IsEnabled = $false; $btnBack.IsEnabled = $false }
    else {
      $busyTitle.Text = $label; if (-not $script:eSteps) { $busyText.Text = ''; $busySteps.Children.Clear() }; $busyBar.Value = 0
      $btnCancelBusy.Visibility = Vis $cancellable; $btnCancelBusy.IsEnabled = $true; $busy.Visibility = 'Visible'; $rootGrid.IsEnabled = $false
    }
  } else {
    if ($script:eRunning) { return }
    $script:eBusy = $false
    if ($script:eInline) { $btnCancelRun.Visibility = 'Collapsed'; $planText.Text = '' } else { $busy.Visibility = 'Collapsed'; $rootGrid.IsEnabled = $true }
    Update-EUi
  }
  if ($script:Confirm) { DoEvents }
}
function Invoke-Bg([string]$Label, [scriptblock]$Script, [object[]]$ArgList = @(), [bool]$Cancellable = $false) {
  if ($SelfTest -or $NoShow) { return (& $Script @ArgList) }
  Set-EBusy $true $Label $Cancellable; $script:BgCancel = $false; $script:eCancelled = $false
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript('param($root, $sb, $a) . (Join-Path $root "lib.ps1"); & ([scriptblock]::Create($sb)) @a').AddArgument($PSScriptRoot).AddArgument($Script.ToString()).AddArgument($ArgList)
  $t0 = Get-Date; $ar = $ps.BeginInvoke(); $cancelled = $false
  $bar = $(if ($script:eInline) { $planBar } else { $busyBar }); $txt = $(if ($script:eInline) { $planText } else { $busyText })
  try {
    while (-not $ar.IsCompleted) {
      DoEvents; Start-Sleep -Milliseconds 30
      $el = ((Get-Date) - $t0).TotalMilliseconds; $sweep = ($el / 40) % 100
      $list = $(if ($script:eInline) { $script:ePlan } else { $script:eSteps })
      if ($list) { $done = @($list | Where-Object { $_.State -eq 'ok' -or $_[0] -eq 'ok' }).Count; $bar.Value = [math]::Min(99, (100.0 * $done + $sweep) / @($list).Count); if ($script:eInline) { $txt.Text = "$Label  ($([int]($el / 1000)) s)" } }
      else { $bar.Value = $sweep; $txt.Text = "$([int]($el / 1000)) s" }
      if ($script:BgCancel -and -not $cancelled) { $cancelled = $true; $script:eCancelled = $true; if (-not $list) { $txt.Text = 'Cancelling...' }; [void]$ps.BeginStop($null, $null) }
      if ($cancelled) { Stop-GitChildren }
    }
    $out = $null; $err = $null
    try { $out = @($ps.EndInvoke($ar)) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $err = $e.Message }
    if ($cancelled) { throw 'Cancelled by you. GitHub may or may not have received it - the status in the window shows the truth.' }
    if ($err) { throw $err }
    if ($out.Count -eq 1) { $out[0] } else { $out }
  } finally { try { $ps.Dispose(); $rs.Dispose() } catch {}; Set-EBusy $false }
}$btnCancelBusy.Add_Click({ $script:BgCancel = $true; $btnCancelBusy.IsEnabled = $false }); $btnCancelRun.Add_Click({ $script:BgCancel = $true; $btnCancelRun.IsEnabled = $false })
#endregion





function Render-Plan {
  $spPlan.Children.Clear(); if (-not $script:ePlan) { return }
  $i = 0
  foreach ($s in $script:ePlan) {
    $i++; $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,4'
    $ih = New-Object Windows.Controls.ContentControl; $ih.Width = 20; $ih.IsTabStop = $false; $ih.VerticalAlignment = 'Top'
    switch ($s.State) { 'ok' { $ih.Content = New-Icon 'check' 14 } 'run' { $ih.Content = New-Tb '>>' 11 'Navy' 'Bold' $false } 'fail' { $ih.Content = New-Icon 'error' 14 } default { $ih.Content = New-Tb "$i." 11 'Text' 'Normal' $false } }
    $tx = New-Tb $s.Text 11 'Text' $(if ($s.State -eq 'run') { 'Bold' } else { 'Normal' }) $true; $tx.MaxWidth = 430
    $row.Children.Add($ih) | Out-Null; $row.Children.Add($tx) | Out-Null; $spPlan.Children.Add($row) | Out-Null
    Acc $row ("Step $i, $($s.Text): " + $(switch ($s.State) { 'ok' { 'done' } 'run' { 'working' } 'fail' { 'failed' } default { 'waiting' } }))
  }
}
$legend.Children.Clear()
foreach ($lg in @(@('cloud', 'On GitHub'), @('pc', 'Only here'), @('pencil', 'Changed'), @('warn', 'Changed, on GitHub'))) {
  $ic = New-Icon $lg[0] 13; $ic.Margin = '0,0,3,0'; $tx = New-Tb $lg[1] 11 'Hint' 'Normal' $false; $tx.Margin = '0,0,10,0'; $tx.VerticalAlignment = 'Center'
  $legend.Children.Add($ic) | Out-Null; $legend.Children.Add($tx) | Out-Null
}









#region logic
$script:eRepo = $null; $script:eCommits = @(); $script:eEdits = @{}; $script:eOrig = @{}; $script:eSel = $null; $script:eSelShas = @(); $script:eView = 'none'
$script:ePush = $null; $script:ePushErr = $null; $script:eBackups = @(); $script:eFilling = $false; $script:eBusy = $false; $script:eLoadErr = $null; $script:eLoading = $false
$script:eSort = $null; $script:eAccess = $null; $script:SignInHook = $null; $script:IdentityHook = $null; $script:eRunning = $false; $script:eSteps = $null
$script:eChanges = @(); $script:eChecks = @{}; $script:ePlain = $null; $script:eSubNote = $null; $script:RowMap = @{}; $script:FileRows = @(); $script:Pre = $null; $script:PreCache = $null
$script:eFilter = 'all'; $script:eDrafts = @{}; $script:eFetch = $null; $script:eWarnings = @(); $script:eOnGh = $null; $script:eTracked = $false; $script:eTotal = 0; $script:eParents = @{}
$script:eDetached = $false; $script:eIgnore = $null; $script:eIgnoreHide = $false; $script:eConflict = $null; $script:eNoiseOpen = $false; $script:eFinish = $null; $script:eBigList = 0
$ePath = $tbPath; $eFind = $tbFind; $ePrimary = $btnNext; $eSign = $btnSign; $eUndo = $lnkUndo; $eHead = $pubHead; $eInfo = $pubDetail; $eMeta = $pubMeta; $eDetL = $lnkDetails
$tgAll.IsChecked = $true

function Bind-Ph($tb, $ph) { $tb.Add_TextChanged({ $ph.Visibility = if ($tb.Text) { 'Collapsed' } else { 'Visible' } }.GetNewClosure()); $ph.Visibility = if ($tb.Text) { 'Collapsed' } else { 'Visible' } }
Bind-Ph $tbPath $phPath; Bind-Ph $tbInit $phInit; Bind-Ph $tbFind $phFind; Bind-Ph $nMsg $phNMsg; Bind-Ph $fName.Box $fName.Ph; Bind-Ph $fMail.Box $fMail.Ph; Bind-Ph $fLink.Box $fLink.Ph

function Add-ELog([string]$t) { $body = $t -replace "`r?`n", "`r`n    "; $eLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $body`r`n"); $eLog.ScrollToEnd() }
function EFail($err) { Add-ELog "ERROR: $($err.Exception.Message)"; Fail $err }
function Find-ECommit([string]$sha) { if ($sha -and $sha -ne '__new__') { @($script:eCommits | Where-Object { $_.Sha -eq $sha -or $_.Sha.StartsWith($sha) })[0] } }
function Norm-Msg([string]$m) { ("$m" -replace "`r`n", "`n").TrimEnd() }
function Get-EOrigMsg([string]$sha) { if (-not $script:eOrig.ContainsKey($sha)) { $script:eOrig[$sha] = Norm-Msg (Get-CommitMessage $script:eRepo $sha) }; $script:eOrig[$sha] }
function First-Line([string]$m) { ($m -split "`n")[0].TrimEnd("`r") }
function Get-RepoLeaf { if ($script:eRepo) { CT (Split-Path $script:eRepo -Leaf) 120 } else { '' } }
function Info-Text { "$($eHead.Text) $($eInfo.Text) $($eMeta.Text)" }
function Open-Url([string]$u) { if ($script:Confirm) { try { Start-Process $u } catch { Add-ELog "Could not open $u" } } }

# ---- prerequisites + hook state: computed in the background and cached, so activating the window never runs git on the UI thread
$script:PreScript = {
  param($repo)
  $g = Test-GitInstalled; $n = ''; $m = ''
  if ($g) {
    if ($repo) { try { $id = Get-GitIdentity $repo; $n = "$($id.Name)".Trim(); $m = "$($id.Email)".Trim() } catch {} }
    else { $n = "$(git config --global user.name 2>$null)".Trim(); $m = "$(git config --global user.email 2>$null)".Trim() }
  }
  $hs = $null; $ce = $null; try { $hs = Get-Status } catch { $ce = $_.Exception.Message }
  [pscustomobject]@{ Git = $g; Name = $n; Mail = $m; Ok = [bool]($g -and $n -and $m); Hook = $hs; CfgErr = $ce }
}
$script:PreAt = [datetime]::MinValue; $script:PreRun = $null
function Refresh-Pre { $script:PreCache = Invoke-Bg 'Checking this PC...' $script:PreScript @($script:eRepo); $script:PreAt = Get-Date; $script:Pre = $script:PreCache }
function Start-PreAsync {
  if ($script:PreRun -or $script:eBusy -or ((Get-Date) - $script:PreAt).TotalSeconds -lt 20) { return }
  if ($SelfTest -or $NoShow) { return }
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript('param($root, $sb, $a) . (Join-Path $root "lib.ps1"); & ([scriptblock]::Create($sb)) @a').AddArgument($PSScriptRoot).AddArgument($script:PreScript.ToString()).AddArgument(@($script:eRepo))
  $script:PreRun = @{ Ps = $ps; Rs = $rs; Ar = $ps.BeginInvoke() }
  $script:PreTimer = New-Object Windows.Threading.DispatcherTimer; $script:PreTimer.Interval = [TimeSpan]::FromMilliseconds(200)
  $script:PreTimer.Add_Tick({
      if ($script:PreRun -and $script:PreRun.Ar.IsCompleted) {
        $script:PreTimer.Stop()
        try { $o = @($script:PreRun.Ps.EndInvoke($script:PreRun.Ar)); if ($o.Count) { $script:PreCache = $o[0]; $script:Pre = $o[0]; $script:PreAt = Get-Date } } catch {}
        try { $script:PreRun.Ps.Dispose(); $script:PreRun.Rs.Dispose() } catch {}
        $script:PreRun = $null; if (-not $script:eBusy) { Update-EBanners }
      }
    })
  $script:PreTimer.Start()
}
function Update-EBanners {
  $I = $script:I; $pre = $script:PreCache; $script:Pre = $pre
  if (-not $pre) { return }
  if ($pre.Ok) { $bnPre.Border.Visibility = 'Collapsed' }
  else {
    $bnPre.Border.Visibility = 'Visible'
    if (-not $pre.Git) { Set-Banner $bnPre 'warn' $I.Warn 'Before we start: Git is missing' 'backd8 uses Git, the free tool that keeps your project history. Install it once, then restart backd8.'; $bGitHelp.Visibility = 'Visible'; $bnPre.Extra.Visibility = 'Collapsed' }
    else { Set-Banner $bnPre 'warn' $I.Warn 'Before we start: who are you?' 'Git writes your name and email into every commit. Tell it once - it is saved for all your projects on this PC.'; $bGitHelp.Visibility = 'Collapsed'; $bnPre.Extra.Visibility = 'Visible'; if (-not $tbName.Text) { $tbName.Text = $pre.Name }; if (-not $tbMail.Text) { $tbMail.Text = $pre.Mail } }
  }
  if ($pre.CfgErr) { Set-Banner $bnCfg 'warn' $I.Warn 'backd8 could not read its settings file' "It is damaged or locked by another program. Your projects and commits are fine. Press Reset settings to start fresh (the old file is kept)." ; $bnCfg.Border.Visibility = 'Visible' } else { $bnCfg.Border.Visibility = 'Collapsed' }
  $hs = $pre.Hook; $dis = $false; try { $dis = [bool](Load-Ui).hookNoticeDismissed } catch {}
  if ($hs -and $hs.Installed -and (($hs.Enabled -and -not $script:hookOnKeep) -or (-not $hs.Enabled -and -not $dis -and -not $script:hookKeepSession))) {
    $bnHook.Border.Visibility = 'Visible'
    if ($hs.Enabled) { Set-Banner $bnHook 'danger' $I.Warn 'Auto-backdating is ON for this PC' "Every new commit you make in other programs gets a made-up date. You don't need it in this window - remove it unless you want it."; Set-Mn $bHookKeep '&Keep it for now' }
    else { Set-Banner $bnHook 'info' $I.Info 'Auto-backdating is installed on this PC (currently OFF)' "It is an optional extra and not needed here. Remove it if you don't use it."; Set-Mn $bHookKeep '&Keep it' }
  } else { $bnHook.Border.Visibility = 'Collapsed' }
  if ($script:eDetached) { Set-Banner $bnDet 'warn' $I.Warn 'You are not on a branch' 'Git is pointing at a single commit, not a branch. Saving commits and applying edits are switched off. Switch to a branch in your usual git tool (for example: git switch main), then press F5.'; $bnDet.Border.Visibility = 'Visible' } else { $bnDet.Border.Visibility = 'Collapsed' }
  $needLink = [bool]($script:eRepo -and $script:ePush -and -not $script:ePush.Url)
  if ($needLink) { Set-Banner $bnLink 'warn' $I.Link 'Not connected to GitHub yet' 'To publish, create a new empty project at github.com/new and paste its address below. You can keep editing and saving commits without it.'; $bnLink.Extra.Visibility = 'Visible' }
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
      git config --global user.name $name; if ($LASTEXITCODE) { throw 'Git could not save your name.' }
      git config --global user.email $mail; if ($LASTEXITCODE) { throw 'Git could not save your email.' }
    }
    Add-ELog "Saved your name and email for git: $name <$mail>"; Show-Toast 'Saved your name and email' 'ok' 'Git will use them for every new commit.'
    if ($script:PreCache) { $script:PreCache.Name = $name; $script:PreCache.Mail = $mail; $script:PreCache.Ok = [bool]$script:PreCache.Git }
  } catch { Fail $_ }
  Update-EBanners; Update-EUi
}
#endregion

#region the summary (honest wording): GitHub's state and your waiting work are always shown together
function Get-PendingParts {
  $nF = $script:eChanges.Count; $nE = $script:eEdits.Count; $dirty = [bool](Get-EDirty)
  $staged = ($script:eView -eq 'commit' -and $script:eSel -and $script:eEdits.ContainsKey($script:eSel))
  $nTyped = $(if ($dirty -and -not $staged) { 1 } else { 0 }) + @($script:eDrafts.Keys).Count
  [pscustomobject]@{ Files = $nF; Edits = $nE; Typed = $nTyped; Total = $nF + $nE + $nTyped }
}
function Get-PendingText {
  $p = Get-PendingParts; if (-not $p.Total) { return $null }
  $a = @(); if ($p.Files) { $a += "$(Format-Plural $p.Files 'changed file') not saved as a commit" }; if ($p.Edits) { $a += "$(Format-Plural $p.Edits 'edited commit') not applied" }; if ($p.Typed) { $a += "$(Format-Plural $p.Typed 'unsaved typed change')" }
  "$(Format-Plural $p.Total 'change') not saved or published yet: $($a -join ', ')"
}
function Set-Pub([string]$kind, [string]$glyph, [string]$head, [string]$detail, [string]$meta = '', [string]$brief = '') {
  $pubIcon.Content = (New-Icon (Kind-Icon $kind) 24); $pubHead.Text = $head; $pubDetail.Text = $detail; $pubDetail.Visibility = Vis ([bool]$detail); $pubMeta.Text = $meta; $pubMeta.Visibility = Vis ([bool]$meta)
  $pt = Get-PendingText; $pubPend.Text = $(if ($pt) { $pt + '. Go Back to save or apply them first.' } else { '' }); $pubPend.Visibility = Vis ([bool]$pt)
  $st = $script:ePush; $bits = @()
  if ($st -and $st.Branch) { $bits += "Branch $(CT $st.Branch 80)" }; if ($st -and $st.Url) { $bits += (CT ($st.Url -replace '^(https?|ssh|git)://', '') 200) }
  $stBranch.Text = (@($bits | ForEach-Object { $_ -replace '^Branch ', '' }) -join '  |  '); $stBranch.ToolTip = $meta; $stGit.Text = $(if ($brief) { $brief } else { $head }); $stGit.ToolTip = "$head`r`n$detail`r`n$meta"
  $stPend.Text = $(if ($pt) { $pt } elseif ($script:eRepo) { $(if ($script:eNext -and $script:eNext.CanPush) { 'Nothing to change - ready to publish' } else { 'Nothing to change' }) } else { '' }); $stPend.ToolTip = $stPend.Text
}
function Update-EInfo {
  $st = $script:ePush; $I = $script:I; $n = @($script:eCommits).Count; $pend = (Get-PendingParts).Total
  $asOf = if ($script:eFetch -eq $false) { ' (as of your last check)' } else { '' }
  if (-not $script:eRepo) { Set-Pub 'idle' $I.Circle 'Nothing to publish yet' 'Choose a project folder first.' '' 'No project chosen'; return }
  if (-not $st) {
    if ($script:eDetached) { Set-Pub 'warn' $I.Warn 'You are not on a branch' "Git is pointing at a single commit. Switch to a branch (for example: git switch main) and press F5." "Folder: $($script:eRepo)" 'You are not on a branch'; return }
    Set-Pub 'danger' $I.Err "Can't read this project's GitHub state" "$($script:ePushErr)" "Folder: $($script:eRepo)" "Can't read GitHub state"; return
  }
  $rem = if ($st.Url) { "$($st.Remote)  $($st.Url)" } else { "none ('$($st.Remote)' not set)" }
  $meta = "Branch: $($st.Branch)    |    GitHub address: $rem"
  if (-not $st.Url) { Set-Pub 'warn' $I.Warn 'Not connected to GitHub' 'This project has no GitHub address yet, so there is nothing to publish to. Connect it on the first page.' $meta; return }
  if ($n -eq 0) { Set-Pub 'idle' $I.Circle 'No commits yet' 'Save your files as a commit first (the New commit row on the Change page), then publish.' $meta; return }
  if ($null -eq $st.Ahead) { Set-Pub 'info' $I.Cloud "Not on GitHub yet - publish to put it there$asOf" "Nothing has been published. Publishing sends your $(Format-Plural $n 'commit') to GitHub." $meta; return }
  $a = [int]$st.Ahead; $b = [int]$st.Behind
  if ($a -eq 0 -and $b -eq 0) { Set-Pub 'ok' $I.Check "GitHub is up to date with your last save$asOf" $(if ($pend) { 'The newest commit you saved is already on GitHub. Your waiting changes are not saved yet, so they are not on GitHub.' } else { 'GitHub has exactly what your computer has. Nothing to publish.' }) $meta "GitHub is up to date with your last save$asOf"; return }
  if ($b -eq 0) { Set-Pub 'info' $I.Upload "$(Format-Plural $a 'saved commit is' 'saved commits are') only on this computer" 'Publishing sends them. Nothing on GitHub is replaced.' $meta "$(Format-Plural $a 'commit') not on GitHub yet"; return }
  if ($a -eq 0) { Set-Pub 'warn' $I.Warn "GitHub has $(Format-Plural $b 'newer change' 'newer changes') than your computer" "Someone (maybe you, on another PC) published after you last looked. Get the latest from GitHub first: nothing on GitHub is replaced or deleted." "$meta    (ahead $a / behind $b)" "GitHub has $(Format-Plural $b 'newer change' 'newer changes')"; return }
  if ($st.RemoteOnly -gt 0 -or ($st.PSObject.Properties['OthersCommits'] -and $st.OthersCommits -gt 0)) { $ro = [math]::Max([int]$st.RemoteOnly, [int]$st.OthersCommits); Set-Pub 'danger' $I.Warn "GitHub has $(Format-Plural $ro 'commit' 'commits') you don't have locally" "That is someone else's work, or your own from another PC. Get the latest from GitHub first so it is combined with yours. Replacing GitHub's version would DELETE it." "$meta    (ahead $a / behind $b)" "GitHub has commits you don't have"; return }
  Set-Pub 'warn' $I.Warn 'GitHub still has the old version' "You changed commits that were already on GitHub, so its copy no longer matches yours. Publishing replaces GitHub's old version: its $(Format-Plural $b 'old commit') $(if ($b -eq 1) { 'disappears' } else { 'disappear' }) there, and anyone who copied them must download again." "$meta    (technically: ahead $a / behind $b - needs a force push)" 'GitHub still has the old version'
}
function Test-NeedsSignIn { $a = $script:eAccess; $pr = $(if ($a -and $a.PSObject.Properties['Problem']) { $a.Problem } else { $null }); [bool]($a -and $a.Transport -in 'https', 'ssh' -and $a.CanPush -eq $false -and -not $a.NeedsAccountChoice -and $pr -notin 'noaccess', 'saml', 'notfound') }
function Update-EAccessLabel {
  $a = $script:eAccess; $ik = 'info'
  $acct = $(if ($a -and $a.PSObject.Properties['AccountInUse'] -and $a.AccountInUse) { " (account $($a.AccountInUse))" } else { '' })
  if (-not $script:eRepo -or -not $a) { $eAcc.Text = 'GitHub sign-in: not checked yet' }
  elseif (-not $a.GitInstalled) { $eAcc.Text = 'Git is not installed'; $ik = 'error' }
  elseif (-not $a.Url) { $eAcc.Text = 'Not connected to GitHub' ; $ik = 'warn' }
  elseif ($a.Transport -eq 'local') { $eAcc.Text = 'Local remote - no sign-in needed'; $ik = 'check' }
  elseif ($a.CanPush -eq $true) { $eAcc.Text = $(if ($a.Transport -eq 'ssh') { 'SSH key accepted' } else { "Signed in to GitHub$acct" }); $ik = 'check' }
  elseif ($a.NeedsAccountChoice) { $eAcc.Text = 'Signed in - GitHub needs to know which account to use'; $ik = 'warn' }
  elseif ($a.CanPush -eq $false) { $eAcc.Text = $(if ($a.Transport -eq 'ssh') { 'SSH key not accepted' } else { 'NOT signed in to GitHub' }); $ik = 'error' }
  else { $eAcc.Text = 'Could not check sign-in'; $ik = 'warn' }
  $accIcon.Content = (New-Icon $ik 20)
  $accWhere.Text = $(if ($script:ePush -and $script:ePush.Url) { "GitHub address: $($script:ePush.Url)" } else { '' })
  $adv = @(); if ($a) { foreach ($l in @($a.Advice)) { if ($l) { $adv += $l } } }
  $eAdvice.Text = $(if ($adv.Count) { $adv -join "`r`n" } elseif ($ik -eq 'check') { 'Nothing to do - you are signed in.' } elseif ($script:eRepo) { 'Press "Sign in to GitHub..." if publishing says you are not signed in.' } else { '' })
  # the Sign in button exists only while signing in is really needed - it is derived from the latest check every time, never from a remembered flag
  $needSign = Test-NeedsSignIn
  $btnSign.Visibility = Vis ($needSign -or ($a -and $a.CanPush -eq $null -and $a.Transport -in 'https', 'ssh'))
  # problems that signing in cannot fix
  $prob = $(if ($a -and $a.PSObject.Properties['Problem']) { $a.Problem } else { $null })
  $pubProb.Visibility = 'Collapsed'
  if ($a -and $a.CanPush -ne $true -and $prob -eq 'notfound') {
    $pubProb.Visibility = 'Visible'; $probIcon.Content = (New-Icon 'warn' 24); $probText.Text = "You are signed in, but GitHub says this project does not exist (or your account cannot see it). Create an EMPTY project at github.com/new with exactly this name, or fix the address below."
    $probFix.Visibility = 'Visible'; Set-Mn $btnProbLink 'Open github.com/new'; $btnProbLink.Tag = 'https://github.com/new'; $btnProbLink.Visibility = 'Visible'
  } elseif ($a -and $a.CanPush -ne $true -and $prob -eq 'noaccess') {
    $pubProb.Visibility = 'Visible'; $probIcon.Content = (New-Icon 'warn' 24); $probText.Text = $(if (@($a.Advice).Count -and $a.Advice[0]) { "$($a.Advice[0])" } else { 'You are signed in, but this GitHub account may not write to the project. Ask the owner to add you as a collaborator, use another account, or fork it.' })
    $probFix.Visibility = 'Collapsed'; $btnProbLink.Visibility = 'Collapsed'
  } elseif ($a -and $a.CanPush -ne $true -and $prob -eq 'saml') {
    $pubProb.Visibility = 'Visible'; $probIcon.Content = (New-Icon 'warn' 24); $probText.Text = "Your organisation uses single sign-on (SSO). Authorise your GitHub sign-in for the organisation, then check again."
    $probFix.Visibility = 'Collapsed'; $btnProbLink.Visibility = 'Visible'; Set-Mn $btnProbLink 'Open GitHub SSO help'; $btnProbLink.Tag = 'https://docs.github.com/en/authentication/authenticating-with-saml-single-sign-on'; $btnProbLink.Visibility = 'Visible'
  }
  # which account? (several saved GitHub accounts and the address names none)
  $gAcct.Visibility = Vis ([bool]($a -and $a.NeedsAccountChoice -and @($a.Accounts).Count -gt 0))
  if ($gAcct.Visibility -eq 'Visible') {
    $key = (@($a.Accounts) -join '|') + '/' + $script:ePush.Url
    if ($script:acctKey -ne $key) {
      $script:acctKey = $key; $spAccounts.Children.Clear(); $owner = ''; try { $owner = "$(Get-GitHubOwner $script:ePush.Url)" } catch {}
      $acctIntro.Text = "You have more than one GitHub account saved on this PC, and the address does not say which one owns this project."
      foreach ($nm in @($a.Accounts)) { $rb = New-Object Windows.Controls.RadioButton; $rb.GroupName = 'acct'; $rb.Margin = '0,0,0,3'; $rb.Content = "$((CT "$nm" 60) -replace '_', '__')$(if ($owner -and $nm -ieq $owner) { '  (owner of this project - recommended)' })"; $rb.Tag = "$nm"; $rb.IsChecked = [bool]($owner -and $nm -ieq $owner); Acc $rb "GitHub account $nm"; Tip $rb "Use the GitHub account $nm for this project."; [void]$spAccounts.Children.Add($rb) }
      if (-not @($spAccounts.Children | Where-Object { $_.IsChecked }).Count -and $spAccounts.Children.Count) { $spAccounts.Children[0].IsChecked = $true }
    }
  } else { $script:acctKey = '' }
}function Set-EAccess($a, [bool]$LogAdvice = $true) {
  $script:eAccess = $a; Set-WfAccess $a; Update-EAccessLabel; Show-WfState
  if ($a -and $LogAdvice) { Add-ELog $eAcc.Text; foreach ($l in @($a.Advice)) { if ($l) { Add-ELog "Tip: $l" } } }
}
function Update-EAccess {
  if (-not $script:eRepo) { return }
  try { $r = $script:eRepo; Set-EAccess (Invoke-Bg 'Checking GitHub sign-in...' { param($p) Get-GitHubAccess $p } @($r) $true) }
  catch { $script:eAccess = $null; Update-EAccessLabel; Add-ELog "Could not check GitHub access: $($_.Exception.Message)" }
}
#endregion

#region state helpers
function Get-ECheckedFiles { @($script:FileRows | Where-Object { $_.Box.IsChecked -and $_.Box.IsEnabled } | ForEach-Object { $_.Path }) }

function Get-ENewProblem { if ($script:nWhen -ne 'now') { $v = $nPick.Problem; if ($v) { return $v } }; $null }
# the reason the typed change on the open commit cannot be kept (or $null)
function Get-EValidation {
  if ($script:eView -ne 'commit' -or -not $script:eSel) { return $null }
  if (-not (Norm-Msg $eMsg.Text).Trim()) { return "The message can't be empty." }
  $ePick.Problem
}
function Get-EDirty {
  if ($script:eView -ne 'commit' -or -not $script:eSel) { return $false }
  $c = Find-ECommit $script:eSel; if (-not $c) { return $false }
  $ed = $script:eEdits[$c.Sha]
  $baseMsg = if ($ed -and $null -ne $ed.message) { Norm-Msg $ed.message } else { Get-EOrigMsg $c.Sha }
  $baseDate = if ($ed -and $ed.date) { [datetime]$ed.date } else { $c.Date }
  $now = Norm-Msg $eMsg.Text; $d = $ePick.Value
  if ($d -eq [datetime]::MinValue) { return $true }
  $d = $d.AddMilliseconds(-$d.Millisecond)
  [bool](($now -cne $baseMsg) -or ([math]::Abs(($d - $baseDate).TotalSeconds) -ge 1))
}
function Show-EView([string]$v) { $script:eView = $v; $vNone.Visibility = Vis ($v -eq 'none'); $vCommit.Visibility = Vis ($v -eq 'commit'); $vMulti.Visibility = Vis ($v -eq 'multi'); $gEdit.Header = switch ($v) { 'commit' { 'Change this commit' } 'multi' { 'Change several commits' } default { 'Selected commit' } } }
$script:nWhen = 'now'
$script:WhenRbs = @{ now = $rbNow; yesterday = $rbYest; week = $rbWeek; month = $rbMonth; custom = $rbCustom }
$nPick = $null; $ePick = $null; $mPick = $null
$ePick = New-Dt (Get-Date); $ePickHost.Children.Add($ePick.Panel) | Out-Null
$mPick = New-Dt (Get-Date).AddDays(-30); $mPickHost.Children.Add($mPick.Panel) | Out-Null
$nPick = New-Dt (Get-Date).AddDays(-1); $nDtHost.Children.Add($nPick.Panel) | Out-Null; $nDtHost.Visibility = 'Collapsed'
function Set-NewWhen([string]$mode, $dt = $null) {
  $script:nWhen = $mode; $script:eFilling = $true
  foreach ($k in $script:WhenRbs.Keys) { $script:WhenRbs[$k].IsChecked = ($k -eq $mode) }
  $script:eFilling = $false
  $now = Get-Date
  $v = switch ($mode) { 'yesterday' { $now.AddDays(-1) } 'week' { $now.AddDays(-7) } 'month' { $now.AddMonths(-1) } default { $null } }
  if ($dt) { $nPick.Value = [datetime]$dt } elseif ($v) { $nPick.Value = $v }
  $nDtHost.Visibility = Vis ($mode -ne 'now'); Update-EUi
}

#endregion





#region the wizard decides from engine state: which actions apply, what the steps will be, a suggested message
function Get-EActions {
  $loaded = [bool]$script:eRepo; $st = $script:ePush; $n = @($script:eCommits).Count; $files = $script:eChanges.Count
  $hasUrl = [bool]($st -and $st.Url); $a = $(if ($st) { $st.Ahead } else { $null }); $b = $(if ($st) { [int]$st.Behind } else { 0 })
  $unpub = [bool]($hasUrl -and $n -and ($null -eq $a -or $a -gt 0))
  $det = [bool]$script:eDetached
  $r = [ordered]@{}
  $expressOk = (-not $det) -and ($files -gt 0 -or $unpub)
  $r.express = @{ Ok = $expressOk; Name = $(if ($files -gt 0) { if ($hasUrl) { 'Save my changes and put them on GitHub' } else { 'Save my changes' } } elseif ($unpub) { 'Put my saved commits on GitHub' } else { 'Save my changes and put them on GitHub' })
    Desc = $(if ($det) { 'Not available: you are not on a branch (switch to one in your git tool, then press F5).' } elseif ($files -gt 0) { "$(Format-Plural $files 'file has' 'files have') changed. Write a short message, and backd8 saves them as a commit$(if ($hasUrl) { ' and sends it to GitHub' }). Recommended." } elseif ($unpub) { "You saved $(if ($null -eq $a) { Format-Plural $n 'commit' } else { Format-Plural $a 'commit' }) that GitHub does not have yet. backd8 sends $(if ($a -eq 1) { 'it' } else { 'them' })." } else { 'Not needed: no files have changed and GitHub has your last save.' }) }
  $r.edit = @{ Ok = ($n -gt 0 -and -not $det); Name = 'Change an older commit (message or date)'; Desc = $(if ($det) { 'Not available: you are not on a branch.' } elseif ($n -gt 0) { 'Fix a typo in an old message or give a commit a different date. A backup is kept, and you can undo it.' } else { 'Not available yet: this project has no commits.' }) }
  $r.spread = @{ Ok = ($n -ge 2 -and -not $det); Name = 'Spread my commits over a period of time'; Desc = $(if ($det) { 'Not available: you are not on a branch.' } elseif ($n -ge 2) { 'Pick several commits and give them new dates, in order, about 1 to 6 hours apart, starting when you choose.' } else { 'Not available yet: you need at least two commits.' }) }
  $r.get = @{ Ok = [bool]($hasUrl -and $b -gt 0); Name = 'Get the latest from GitHub'; Desc = $(if ($hasUrl -and $b -gt 0) { "GitHub has $(Format-Plural $b 'newer change'). Download $(if ($b -eq 1) { 'it' } else { 'them' }) and combine with your project. Nothing on GitHub is replaced. Recommended." } elseif ($hasUrl) { 'Not needed: GitHub has nothing newer than your project.' } else { 'Not available: this project is not connected to GitHub yet.' }) }
  $r.undo = @{ Ok = [bool](@($script:eBackups).Count -gt 0); Name = 'Undo my last change'; Desc = $(if (@($script:eBackups).Count) { "Put the project back to how it was before your last Apply ($(Format-Plural @($script:eBackups).Count 'backup' 'backups') available)." } else { 'Not available: there is no backup to go back to yet.' }) }
  $r
}
function Get-DefaultAction {
  $a = Get-EActions; $st = $script:ePush
  if ($a.get.Ok -and $st -and $st.Ahead -eq 0) { return 'get' }
  if ($a.express.Ok) { return 'express' }
  if ($a.get.Ok) { return 'get' }
  if ($a.edit.Ok) { return 'edit' }
  if ($a.undo.Ok) { return 'undo' }
  'edit'
}
# a sensible commit message from what changed
function Get-ChangeSuggestion {
  $ch = @($script:eChanges | Where-Object { -not ($_.PSObject.Properties['Noise'] -and $_.Noise) -and $_.Kind -ne 'nested' }); if (-not $ch.Count) { $ch = @($script:eChanges) }
  if (-not @($script:eCommits).Count) { return 'First version' }
  if (-not $ch.Count) { return '' }
  $leaf = { param($p) ($p -split '[\\/]')[-1] }
  $kinds = @($ch | ForEach-Object { $_.Kind } | Sort-Object -Unique); $verb = if ($kinds.Count -eq 1 -and $kinds[0] -eq 'new') { 'Add' } elseif ($kinds.Count -eq 1 -and $kinds[0] -eq 'deleted') { 'Remove' } else { 'Update' }
  $first = & $leaf $ch[0].Path
  if ($ch.Count -eq 1) { return "$verb $first" }
  "$verb $first and $(Format-Plural ($ch.Count - 1) 'other file')"
}
# the numbered steps the publish page shows (and runs), derived from the same state as the buttons

$script:DraftKey = { param($r) "draft:" + (Norm "$r") }
function Get-SavedDraft { if (-not $script:eRepo) { return '' }; try { $d = (Load-Ui).drafts; if ($d) { return "$($d.PSObject.Properties[(& $script:DraftKey $script:eRepo)].Value)" } } catch {}; '' }
function Save-Draft { if (-not $script:eRepo -or -not $script:Confirm) { return }; try { $h = Ui-Hash; $d = @{}; if ($h['drafts']) { foreach ($p in $h['drafts'].PSObject.Properties) { $d[$p.Name] = $p.Value } }; $k = (& $script:DraftKey $script:eRepo); if ($nMsg.Text.Trim()) { $d[$k] = $nMsg.Text } else { [void]$d.Remove($k) }; $h['drafts'] = $d; Write-Ui $h } catch {} }
#endregion
















#region wizard pages and the central UI refresh
$script:sideKey = ''; $script:pubKind = ''; $script:navKey = ''; $script:wizStack = @(); $script:acctKey = ''
function Eff-Date($c) { $ed = $script:eEdits[$c.Sha]; if ($ed -and $ed.date) { [datetime]$ed.date } else { $c.Date } }
function Get-EDateHints([string]$sha, [datetime]$d) {
  $out = @()
  foreach ($p in @($script:eParents[$sha])) { $pc = Find-ECommit $p; if ($pc) { $pd = Eff-Date $pc; if ($d -lt $pd) { $out += "This is earlier than its parent commit ($(Fmt $pd)). Git allows it, but the history will look out of order." } } }
  foreach ($k in @($script:eParents.Keys)) { if (@($script:eParents[$k]) -contains $sha) { $cc = Find-ECommit $k; if ($cc) { $cd = Eff-Date $cc; if ($d -gt $cd) { $out += "This is later than a commit that comes after it ($(Fmt $cd)). Git allows it, but the history will look out of order."; break } } } }
  $out
}
function Get-RepoUrlShort { if ($script:ePush -and $script:ePush.Url) { CT ($script:ePush.Url -replace '^(https?|ssh|git)://', '') 200 } else { 'not connected' } }
function Update-ExpressPage {
  $plan = @(Get-EPlan); $n = Get-ENext; $files = $script:eChanges.Count
  $xTitle.Text = $(if ($files) { 'Save your changes' } else { 'Put your commits on GitHub' })
  $xSummary.Text = $(if ($plan.Count) { 'backd8 will: ' + ((1..$plan.Count | ForEach-Object { "$_. $($plan[$_ - 1].Text)" }) -join '   ') + $(if (Get-Dest) { "   Destination: $(Get-Dest)." }) } else { 'Write a message and tick the files that belong in this commit.' })
  foreach ($c in @($xMsgLbl, $nMsg, $xSuggest)) { $c.Visibility = Vis ([bool]$files) }; $phNMsg.Visibility = $(if ($files -and -not $nMsg.Text) { 'Visible' } else { 'Collapsed' })
  $sug = Get-ChangeSuggestion; $xSuggest.Text = $(if ($files -and $sug -and $nMsg.Text -eq $sug) { 'Suggested from the files you changed - edit it if you like.' } else { '' })
  $nB = @(Get-ECheckedFiles); $btnFiles.Content = "Files ($($nB.Count) of $($script:eChanges.Count) selected) - $(if ($pFiles.Visibility -eq 'Visible') { 'hide' } else { 'show' })"
  Acc $btnFiles "Files, $($nB.Count) of $($script:eChanges.Count) selected"
  $left = @($script:FileRows | Where-Object { -not $_.Box.IsChecked -and ($_.Risky -or $_.Box.IsEnabled -eq $false) })
  $noise = @($script:eChanges | Where-Object { $_.PSObject.Properties['Noise'] -and $_.Noise }).Count
  $w = @(); if ($left.Count) { $w += "Left out on purpose: $((@($left | Select-Object -First 3 | ForEach-Object { $_.Path }) -join ', '))$(if ($left.Count -gt 3) { " and $($left.Count - 3) more" }) (secrets, too big or not part of this project)." }; if ($noise) { $w += "$(Format-Plural $noise 'build or editor file is' 'build or editor files are') not included." }
  if ($script:eBigList) { $w += "$(Format-Plural $script:eBigList 'file') beyond the first 400 are not listed and will not be included." }
  $xWarn.Text = ($w -join ' '); $xWarn.Visibility = Vis ($w.Count -gt 0)
}
function Update-PlanPage {
  $running = $script:ePlanRunning
  if (-not $running -and -not $script:ePlanLocked) { $script:ePlan = @(Get-EPlan); Render-Plan }
  $plan = @($script:ePlan); $rep = [bool](@($plan | Where-Object { $_.Replace }).Count)
  $st = $script:ePush; $next = $script:eNext
  $p4Intro.Text = $(if ($running) { 'backd8 is working. You can cancel at any time.' } elseif ($script:eLastFail) { 'A step did not work. Nothing further was done.' } elseif (-not $plan.Count) { $(if ($next.Reason) { $next.Reason } else { 'There is nothing to do.' }) } else { 'These steps run in order. Press Publish to start (they also start by themselves when nothing needs a decision).' })
  $gDecide.Visibility = Vis ($rep -and -not $running)
  if ($rep -and $st) {
    $b = [int]$st.Behind; $a = [int]$st.Ahead
    $rbKeepD.Text = 'Do not publish now. Go Back to look at your changes first.'; $rbReplaceD.Text = $(if ($b -gt 0 -and $a -gt 0) { "GitHub's $(Format-Plural $b 'old commit') $(if ($b -eq 1) { 'is' } else { 'are' }) replaced by your $(Format-Plural $a 'commit'). Anyone who copied the old version must download again." } else { "The commits you changed are already on GitHub, so GitHub's copy of them is replaced by yours. Anyone who copied the old version must download again." })
    Set-RadioMn $rbKeep $rbKeepT "&Keep GitHub's version" 'Do not publish now. Go Back to look at your changes first.'
    Set-RadioMn $rbReplace $rbReplaceT "&Replace GitHub's version with mine" $(if ($b -gt 0 -and $a -gt 0) { "GitHub's $(Format-Plural $b 'old commit') $(if ($b -eq 1) { 'is' } else { 'are' }) replaced by your $(Format-Plural $a 'commit'). Anyone who copied the old version must download again." } else { "The commits you changed are already on GitHub, so GitHub's copy of them is replaced by yours. Anyone who copied the old version must download again." })
  }
  $btnGetLatest.Visibility = Vis ($next.NeedGet -and -not $running -and -not (@($plan | Where-Object { $_.Id -eq 'getlatest' }).Count))
  if (-not $script:lnkReplaceAdv) { $script:lnkReplaceAdv = New-Button "Advanced: replace &GitHub's version instead..." 'link'; Tip $script:lnkReplaceAdv "Only if you are sure GitHub's newer commits can be deleted. You are asked to confirm twice."; $script:lnkReplaceAdv.Margin = '0,6,0,0'; $script:lnkReplaceAdv.HorizontalAlignment = 'Left'; $btnGetLatest.Parent.Children.Insert(($btnGetLatest.Parent.Children.IndexOf($btnGetLatest) + 1), $script:lnkReplaceAdv); $script:lnkReplaceAdv.Add_Click({ if (-not $script:eBusy) { if (Do-EPush -Force) { Show-Finish } } }) }
  $script:lnkReplaceAdv.Visibility = Vis ($next.NeedGet -and $next.Diverged -and -not $running)
  $pubConflict.Visibility = Vis ([bool]$script:eConflict)
  $pubFail.Visibility = Vis ([bool]$script:eLastFail -and -not $running)
  if ($script:eLastFail) { $failIcon.Content = (New-Icon 'error' 24); $failHead.Text = $script:eLastFail.Heading; $failText.Text = $script:eLastFail.Next; $failRaw.Text = $script:eLastFail.Raw }
  Set-Mn $btnFailDetails $(if ($failRaw.Visibility -eq 'Visible') { '<< Details' } else { 'Details >>' })
}
function Update-EUi {
  $G = $script:G; $loaded = [bool]$script:eRepo; $st = $script:ePush; $nE = $script:eEdits.Count
  Update-WfLocal; $next = Get-ENext; $script:eNext = $next; $pg = $script:wizPage
  $mode = if ($loaded) { 'project' } elseif ($script:ePlain) { 'plain' } else { 'empty' }
  $pEmpty.Visibility = Vis ($mode -eq 'empty'); $pPlain.Visibility = Vis ($mode -eq 'plain'); $pReady.Visibility = Vis ($mode -eq 'project')
  $gInit.Visibility = Vis ([bool]$rbInit.IsChecked); $recentNone.Visibility = Vis ($lbRecent.Items.Count -eq 0)
  if ($loaded) {
    $p1Name.Text = Get-RepoLeaf
    $br = if ($st) { $st.Branch } else { 'unknown' }
    $p1Info.Text = "$($script:eRepo)`r`n$(Format-Plural $script:eTotal 'commit') on branch $br`r`nGitHub: $(Get-RepoUrlShort)" + $(if ($script:eChanges.Count) { "`r`n$(Format-Plural $script:eChanges.Count 'changed file') not saved as a commit yet" } else { '' })
    $ig = $script:eIgnore; $showIg = [bool]($ig -and $ig.Needed -and -not $script:eIgnoreHide)
    $chkIgnore.Visibility = Vis $showIg
    if ($showIg) { Set-RadioMn $chkIgnore $chkIgnoreT 'Leave &out build and editor files (recommended)' 'Adds a standard .gitignore.'; $chkIgnoreD.Text = "$(Format-Plural $ig.NoiseCount 'build or editor file') would be saved too. backd8 adds a standard .gitignore so they stay out of your commits."; Acc $chkIgnore 'Leave out build and editor files (recommended)'; Tip $chkIgnore 'Adds a standard .gitignore file when you press Next.' }
    $p1Next.Text = $(if ($script:PreCache -and -not $script:PreCache.Ok) { 'Tell git your name and email above, then press Next.' } else { 'Press Next to choose what to do.' })
  }
  $tbFind.IsEnabled = $loaded
  # ---- the editors (the pages themselves only show/hide these)
  $one = ($script:eView -eq 'commit') -and [bool]$script:eSel
  $eDisc.IsEnabled = $one -and $script:eEdits.ContainsKey($script:eSel)
  $eSave.IsEnabled = $one -and $next.Dirty -and -not $next.Invalid
  if ($one) {
    $c = Find-ECommit $script:eSel
    if ($c) {
      $staged = $script:eEdits.ContainsKey($c.Sha); $ed = $script:eEdits[$c.Sha]
      $eSelHead.Text = "Commit $($c.Short) - $(Get-RelDate $c.Date)"
      $eSelSub.Text = "by $($c.Author)  $($G.Dot)  " + $(if ($next.Dirty) { 'you have unsaved typing' } elseif ($staged) { 'changed - not applied to the project yet' } else { 'original' }) + $(if ($script:eOnGh -and $script:eOnGh.Contains($c.Sha)) { "  $($G.Dot)  already on GitHub" } else { '' })
      $eSaveState.Text = if ($next.Invalid) { '' } elseif ($next.Dirty) { 'Press Next - or Keep this change. Clicking another commit keeps your typing too.' } elseif ($staged) { 'Kept. It is written into your project when you press Next.' } else { 'Nothing changed yet.' }
      $eWarn.Text = "$($next.Invalid)"; $eWarn.Visibility = Vis ([bool]$next.Invalid)
      $curMsg = Norm-Msg $eMsg.Text; $orig = Get-EOrigMsg $c.Sha; $d = $ePick.Value
      $eMsgReset.IsEnabled = ($curMsg -cne $orig); $eDateReset.IsEnabled = ($d -eq [datetime]::MinValue) -or ([math]::Abs(($d.AddMilliseconds(-$d.Millisecond) - $c.Date).TotalSeconds) -ge 1)
      $hints = @(); if ($d -ne [datetime]::MinValue -and -not $next.Invalid) { $hints = @(Get-EDateHints $c.Sha $d) }
      $eHint.Text = ($hints -join "`r`n"); $eHint.Visibility = Vis ($hints.Count -gt 0)
      $dl = @()
      if ($curMsg -cne $orig) { $dl += "Message:  `"$(First-Line $orig)`"  ->  `"$(First-Line $curMsg)`"" + $(if (((First-Line $orig) -ceq (First-Line $curMsg))) { '  (the text below the title changed)' } else { '' }) }
      if ($d -ne [datetime]::MinValue -and $eDateReset.IsEnabled) { $dl += "Date:     $(Fmt $c.Date)  ->  $(Fmt $d)" }
      $eDiff.Text = ($dl -join "`r`n"); $eDiff.Visibility = Vis ($dl.Count -gt 0)
      $off = [TimeZoneInfo]::Local.GetUtcOffset($(if ($d -ne [datetime]::MinValue) { $d } else { $c.Date })); $eTz.Text = 'Your time zone: UTC' + $(if ($off -lt [timespan]::Zero) { '-' } else { '+' }) + $off.ToString('hh\:mm')
    }
  }
  $nB = @(Get-ECheckedFiles); $nCount.Text = "$($nB.Count) of $($script:eChanges.Count) selected"
  $nBtn.IsEnabled = $next.NewReady
  $np = Get-ENewProblem; $nDateWarn.Text = "$np"; $nDateWarn.Visibility = Vis ([bool]$np)
  $nHint.Text = if ($script:eDetached) { 'You are not on a branch - saving is switched off.' } elseif ($script:eChanges.Count -and -not $nB.Count) { 'Tick at least one file.' } elseif ($script:eChanges.Count -and -not $nMsg.Text.Trim()) { 'Write a short message to continue.' } elseif ($np) { 'Fix the date first.' } elseif ($script:nWhen -ne 'now') { "Will be dated $(Fmt $nPick.Value)." } else { 'Will be dated now.' }
  Tip $nBtn $(if ($nBtn.IsEnabled) { 'A commit is one saved version of your project. This saves the ticked files with your message and date, on this computer only. Nothing is sent to GitHub yet.' } else { "Not yet: $($nHint.Text)" })
  Tip $eSave $(if ($eSave.IsEnabled) { 'Keep this message and date as a waiting change. Nothing is rewritten until you press Next.' } elseif ($next.Invalid) { "Not yet: $($next.Invalid)" } else { 'Nothing changed yet - edit the message or date first.' })
  Tip $eDisc $(if ($eDisc.IsEnabled) { 'Throw away your waiting change to this commit and show the original message and date again.' } else { 'You have not kept a change to this commit yet.' })
  $eUndo.Visibility = Vis $loaded; $eUndo.IsEnabled = $loaded -and @($script:eBackups).Count -gt 0
  Tip $eUndo $(if ($eUndo.IsEnabled) { 'Put the project back to how it was before your last Apply (Ctrl+Z). Refused if the branch changed since; you can then undo anyway.' } else { 'Nothing to undo: no backup of this branch exists yet.' })
  $eSign.IsEnabled = $loaded -and $next.HasRemote; $btnCheck.IsEnabled = $eSign.IsEnabled
  Tip $eSign $(if ($eSign.IsEnabled) { 'Sign in to GitHub in a separate window (browser, GitHub CLI or an SSH test). backd8 never stores your password or token.' } else { 'Connect a GitHub address first (page 1).' })
  # ---- per page
  if ($pg -eq 3 -and $script:eAction -eq 'express') { Update-ExpressPage }
  if ($pg -eq 4) { Update-PlanPage }
  Update-WfPanels
  Update-NavButtons $next $mode
  $nPend = (Get-PendingParts).Total
  $sideCount.Text = "$nPend"; $sideHelp.Text = Get-SideHelp
  $key = "$pg/$($script:eAction)"; if ($key -ne $script:sideKey) { Update-Side; $script:sideKey = $key }
  $sk = "$pg|$($script:eAction)|$($script:eView)|$($script:navKey)|$mode|$($bnPre.Border.Visibility)|$($bnLink.Border.Visibility)|$($bnHook.Border.Visibility)|$($bnCfg.Border.Visibility)|$($gDecide.Visibility)|$($gAcct.Visibility)|$($pubFail.Visibility)|$($pubProb.Visibility)|$($chkIgnore.Visibility)|$($btnSign.Visibility)|$($btnGetLatest.Visibility)|$($btnNext.IsEnabled)|$($eSave.IsEnabled)|$($eDisc.IsEnabled)|$($mBtn.IsEnabled)|$($nBtn.IsEnabled)"
  if ($sk -ne $script:scopeKey) { Apply-MnScope; $script:scopeKey = $sk }
  Update-EInfo
  Update-ECount
  Ensure-Tips
}

#endregion
#region history list (rows are built in code)
function Get-EView {
  $v = @($script:eCommits); $q = $tbFind.Text.Trim()
  if ($q) { $v = @($v | Where-Object { $_.Subject -like "*$q*" -or $_.Author -like "*$q*" -or $_.Sha.StartsWith($q.ToLower()) -or (Fmt $_.Date) -like "*$q*" -or ($script:eEdits[$_.Sha] -and $script:eEdits[$_.Sha].message -like "*$q*") }) }
  if ($script:eFilter -eq 'local') { $v = @($v | Where-Object { -not ($script:eOnGh -and $script:eOnGh.Contains($_.Sha)) }) }
  elseif ($script:eFilter -eq 'edited') { $v = @($v | Where-Object { $script:eEdits.ContainsKey($_.Sha) }) }
  if ($script:eSort) {
    $key = switch ($script:eSort.Col) { 'date' { { $_.Date } } 'msg' { { $_.Subject } } 'id' { { $_.Short } } 'mark' { { [int]($script:eOnGh -and $script:eOnGh.Contains($_.Sha)) } } default { { $_.Date } } }
    $v = @($v | Sort-Object -Property $key -Descending:$script:eSort.Desc)
  }
  $v
}
function New-HistRow([string]$tag) {
  $g = New-Object Windows.Controls.Grid
  foreach ($w in @(34, 92, 0, 84)) { $c = New-Object Windows.Controls.ColumnDefinition; if ($w) { $c.Width = New-Object Windows.GridLength($w) } else { $c.Width = New-Object Windows.GridLength(1, 'Star') }; $g.ColumnDefinitions.Add($c) }
  $mk = New-Object Windows.Controls.StackPanel; $mk.Orientation = 'Horizontal'
  $date = New-TbI ''; $subj = New-TbI ''; $subj.TextTrimming = 'CharacterEllipsis'; $subj.Margin = '0,0,8,0'
  $id = New-TbI ''; $id.FontFamily = $script:FontMono; $id.FontSize = $script:MonoSmall
  $i = 0; foreach ($c in @($mk, $date, $subj, $id)) { [Windows.Controls.Grid]::SetColumn($c, $i); $g.Children.Add($c) | Out-Null; $i++ }
  $it = New-Object Windows.Controls.ListBoxItem; $it.Content = $g; $it.Tag = $tag; $it.Style = $script:Res['RowItem']
  @{ Item = $it; Mark = $mk; Date = $date; Subj = $subj; Id = $id }
}
function Style-HistRow($r, $c) {
  $ed = $script:eEdits[$c.Sha]; $subj = $c.Subject; $date = $c.Date
  if ($ed) { if ($null -ne $ed.message) { $subj = First-Line $ed.message }; if ($ed.date) { $date = [datetime]$ed.date } }
  $onGh = [bool]($script:eOnGh -and $script:eOnGh.Contains($c.Sha)); $hasUrl = [bool]($script:ePush -and $script:ePush.Url)
  $r.Mark.Children.Clear()
  $loc = New-Object Windows.Controls.ContentControl; $loc.Width = 15; $loc.IsTabStop = $false
  if ($onGh) { $loc.Content = (New-Icon 'cloud' 13); $loc.ToolTip = 'On GitHub' } elseif ($hasUrl) { $loc.Content = (New-Icon 'pc' 13); $loc.ToolTip = 'Only on this computer - not published yet' }
  [void]$r.Mark.Children.Add($loc)
  if ($ed) {
    $e = New-Object Windows.Controls.ContentControl; $e.Width = 15; $e.IsTabStop = $false
    if ($onGh) { $e.Content = (New-Icon 'warn' 13); $e.ToolTip = 'Changed, but already on GitHub: publishing will replace it there' } else { $e.Content = (New-Icon 'pencil' 13); $e.ToolTip = 'Changed - not applied yet' }
    [void]$r.Mark.Children.Add($e)
  }
  $r.Date.Text = Get-RelDate $date; $r.Subj.Text = $(if ($c.IsMerge) { "[merge] $subj" } else { $subj }); $r.Id.Text = $c.Short
  $r.Subj.FontWeight = $(if ($ed) { 'Bold' } else { 'Normal' }); $r.Date.FontWeight = $(if ($ed -and $ed.date) { 'Bold' } else { 'Normal' })
  $where = if ($onGh) { 'On GitHub' } elseif ($hasUrl) { 'Only on this computer' } else { '' }
  $r.Item.ToolTip = "$($c.Short)  $(Fmt $date)  ($(Get-RelDate $date))  $($c.Author)`r`n$subj" + $(if ($where) { "`r`n$where" } else { '' }) + $(if ($ed) { $(if ($onGh) { "`r`n(changed - already on GitHub: publishing will replace it)" } else { "`r`n(changed - not applied yet)" }) } else { '' })
  Acc $r.Item "$subj, $(Get-RelDate $date), $($c.Author)$(if ($where) { ', ' + $where })$(if ($ed) { ', changed, not applied yet' })"
}
function Update-EItem([string]$sha) { $r = $script:RowMap[$sha]; if ($r) { $c = Find-ECommit $sha; if ($c) { Style-HistRow $r $c } } }
function Update-ECount {
  $n = $script:eCommits.Count; $shown = @($lbHist.Items | Where-Object { $_.Tag -ne '__new__' }).Count
  $tot = [math]::Max($script:eTotal, $n)
  $tHistCount.Text = if (-not $script:eRepo) { '' } else { $(if ($tot -gt $n) { "$(Format-Plural $tot 'commit') - showing the latest $n" } elseif ($shown -ne $n) { "$shown of $(Format-Plural $n 'commit')" } else { Format-Plural $n 'commit' }) + $(if (@($lbHist.SelectedItems).Count -gt 1) { ", $(@($lbHist.SelectedItems).Count) selected" } else { '' }) }
  $tbHistEmpty.Visibility = Vis ($lbHist.Items.Count -eq 0)
  $tbHistEmpty.Text = if (-not $script:eRepo) { '' } elseif ($n -eq 0) { "No commits yet and no changed files.`r`nAdd or change a file in the folder, then press F5." } elseif ($shown -eq 0) { $(if ($tbFind.Text.Trim()) { "No commit matches '$($tbFind.Text.Trim())'." } else { 'No commit matches this filter.' }) } else { '' }
  $nl = @($script:eCommits | Where-Object { -not ($script:eOnGh -and $script:eOnGh.Contains($_.Sha)) }).Count
  Set-Mn $tgAll "All $n"; Set-Mn $tgLocal "Not on GitHub yet $nl"; Set-Mn $tgEdited "Edited $($script:eEdits.Count)"
  $script:eFilling = $true; $tgAll.IsChecked = ($script:eFilter -eq 'all'); $tgLocal.IsChecked = ($script:eFilter -eq 'local'); $tgEdited.IsChecked = ($script:eFilter -eq 'edited'); $script:eFilling = $false
  Hdr-Text $hSortDate 'When' 'date'; Hdr-Text $hSortMsg 'Commit message' 'msg'; Hdr-Text $hSortId 'Commit ID' 'id'
}
function Fill-EList {
  $script:eFilling = $true
  try {
    $lbHist.Items.Clear(); $script:RowMap = @{}
    foreach ($c in (Get-EView)) {
      $r = New-HistRow $c.Sha; Style-HistRow $r $c; $script:RowMap[$c.Sha] = $r; [void]$lbHist.Items.Add($r.Item)
      if ($script:eSelShas -contains $c.Sha) { $r.Item.IsSelected = $true }
    }
  } finally { $script:eFilling = $false }
  Update-ECount
}
function Fill-EFiles {
  $spFiles.Children.Clear(); $script:FileRows = @(); $cap = 400; $shown = 0; $hidden = 0
  $noiseHost = $null; $noiseRows = @()
  $mk = { param($c)
    $big = [double]$c.SizeMB; $outside = [bool]($c.PSObject.Properties['Outside'] -and $c.Outside); $nested = ($c.Kind -eq 'nested'); $risky = [bool]$c.Risky; $noise = [bool]($c.PSObject.Properties['Noise'] -and $c.Noise)
    $cb = New-Object Windows.Controls.CheckBox; $cb.Tag = $c.Path; $cb.Margin = '0,1,0,1'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $kindText = switch ($c.Kind) { 'new' { 'New file' } 'deleted' { 'Deleted' } 'renamed' { "Renamed (was $($c.OldPath))" } 'nested' { 'Separate git project' } default { 'Changed' } }
    $tn = New-Tb (CT $c.Path 260) 11 'Text' 'Normal' $false; $tk = New-Tb "   $kindText" 11 'Hint' 'Normal' $false; $tk.VerticalAlignment = 'Center'
    $why = $null
    if ($nested) { $why = 'A separate git project inside this folder - it cannot be saved as part of this one.' }
    elseif ($outside) { $why = 'Reached through a shortcut (junction) to somewhere outside the project - it is not saved.' }
    elseif ($big -gt 100) { $why = "Too big for GitHub ($big MB; the limit is 100 MB). It cannot be saved in a commit." }
    if ($risky) { $w = New-Icon 'warn' 13; $w.Margin = '0,0,5,0'; $sp.Children.Add($w) | Out-Null; $rr = $(if ($c.PSObject.Properties['RiskReason'] -and $c.RiskReason) { $c.RiskReason } else { 'file name suggests passwords or keys' }); $tk.Text = "   $kindText - $rr"; SetRes $tk ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $cb.ToolTip = 'Possible secret: it starts unticked. Only include it if you are sure it is safe to publish.' }
    if ($big -gt 50 -and -not $why) { $tk.Text = "   $kindText - large file ($big MB; GitHub warns above 50 MB)"; SetRes $tk ([Windows.Controls.TextBlock]::ForegroundProperty) 'WarnFg' }
    if ($why) { $tk.Text = "   $why"; SetRes $tk ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $cb.IsEnabled = $false; $cb.ToolTip = $why }
    $sp.Children.Add($tn) | Out-Null; $sp.Children.Add($tk) | Out-Null; $cb.Content = $sp; Acc $cb "$($c.Path), $kindText$(if ($why) { ', ' + $why })"
    $cb.IsChecked = $(if ($why) { $false } elseif ($script:eChecks.ContainsKey($c.Path)) { [bool]$script:eChecks[$c.Path] } else { -not $risky -and -not $noise })
    $cb.Add_Click({ $script:eChecks[[string]$this.Tag] = [bool]$this.IsChecked; Update-EUi })
    @{ Cb = $cb; Row = [pscustomobject]@{ Path = $c.Path; Box = $cb; Risky = $risky; Text = $c.Path } }
  }
  foreach ($c in $script:eChanges) {
    $isNoise = [bool]($c.PSObject.Properties['Noise'] -and $c.Noise)
    if (-not $isNoise -and $shown -ge $cap) { $hidden++; continue }
    $o = & $mk $c; $script:FileRows += $o.Row
    if ($isNoise) { $noiseRows += $o.Cb } else { [void]$spFiles.Children.Add($o.Cb); $shown++ }
  }
  if ($noiseRows.Count) {
    $hdr = New-Button "Build and editor files ($($noiseRows.Count)) - not saved unless you tick them" 'link'; $hdr.Margin = '0,4,0,2'; Tip $hdr 'Folders like bin, obj, .vs and node_modules are rebuilt by tools. They start unticked. Click to show or hide them.'
    $nh = New-Object Windows.Controls.StackPanel; $nh.Margin = '16,0,0,0'; $nh.Visibility = Vis $script:eNoiseOpen; foreach ($cb in $noiseRows) { [void]$nh.Children.Add($cb) }
    $hdr.Add_Click({ $script:eNoiseOpen = -not $script:eNoiseOpen; $this.Tag.Visibility = Vis $script:eNoiseOpen }); $hdr.Tag = $nh
    [void]$spFiles.Children.Add($hdr); [void]$spFiles.Children.Add($nh)
  }
  if ($hidden) { $m = New-Tb "... and $(Format-Plural $hidden 'more file') not listed. They will NOT be included in this commit: save these first, then the rest in another commit." 11 'WarnFg' 'Bold'; $m.Margin = '0,4,0,0'; [void]$spFiles.Children.Add($m) }
  $script:eBigList = $hidden
  # a friendly card before the first commit when build files would be saved too
  $nCard.Children.Clear()
  $ig = $script:eIgnore
  if ($ig -and $ig.Needed -and -not $script:eIgnoreHide) {
    $kindName = switch ("$($ig.Kind)") { 'dotnet' { 'a Visual Studio / .NET project' } 'visualstudio' { 'a Visual Studio project' } 'node' { 'a Node.js project' } 'python' { 'a Python project' } default { 'a code project' } }
    $card = New-Object Windows.Controls.StackPanel; $card.Orientation = 'Horizontal'
    $card.Children.Add((New-Icon 'info' 20)) | Out-Null; $t = New-Tb "This looks like $kindName. Build files ($($ig.NoiseCount)) would be saved too." 11 'Text' 'Bold'; $t.Margin = '8,0,8,0'; $t.MaxWidth = 250; $t.VerticalAlignment = 'Center'; $card.Children.Add($t) | Out-Null
    $b1 = New-Button 'Add a .&gitignore' 'normal'; $b1.Margin = '0,0,4,0'; Tip $b1 'Adds a standard .gitignore so build files are left out of your commits.'; $b1.Add_Click({ Do-EAddIgnore }); $b2 = New-Button 'Not &now' 'normal'; Tip $b2 'Leave it for now.'; $b2.Add_Click({ $script:eIgnoreHide = $true; Fill-EFiles; Update-EUi })
    $card.Children.Add($b1) | Out-Null; $card.Children.Add($b2) | Out-Null; $nCard.Children.Add($card) | Out-Null
  }
  $nCard.Visibility = Vis ($nCard.Children.Count -gt 0)
}
function Do-EAddIgnore {
  try { $r = $script:eRepo; $k = $script:eIgnore.Kind; $wr = Invoke-Wf 'AddGitignore' @{ Kind = $k } 'Adding .gitignore...'; if (-not (Handle-WfResult $wr 'AddGitignore')) { return }; $msg = $wr.Result; Add-ELog "$msg"; $script:eIgnoreHide = $true; Do-ELoad $r -NoAccess; Show-Toast 'Added a .gitignore' 'ok' 'Build files are now left out. The .gitignore itself is a new file you can include in your commit.' } catch { EFail $_ }
}
function Clear-EDetail { $script:eSel = $null; $script:eSelShas = @(); $script:eLoading = $true; try { $eMsg.Text = '' } finally { $script:eLoading = $false }; $eWarn.Visibility = 'Collapsed'; Show-EView 'none' }
function Reset-ELoaded {
  $script:eFolder = ''; $script:eWf = $null; $script:eSub = ''; $script:eRepo = $null; $script:eCommits = @(); $script:eEdits = @{}; $script:eOrig = @{}; $script:ePush = $null; $script:ePushErr = $null; $script:eBackups = @(); $script:eAccess = $null; $script:eLoadErr = $null
  $script:eChanges = @(); $script:eChecks = @{}; $script:ePlain = $null; $script:eSubNote = $null; $script:eDrafts = @{}; $script:eWarnings = @(); $script:eOnGh = $null; $script:eTotal = 0; $script:eParents = @{}; $script:eDetached = $false; $script:eIgnore = $null; $script:eConflict = $null; $script:eFetch = $null; $script:eFinish = $null
  Clear-EDetail; Fill-EList; Fill-EFiles; Fill-Recent; Update-EAccessLabel; Update-EBanners; Update-EUi
}
function Fill-Recent {
  $lbRecent.Items.Clear()
  foreach ($p in @(Get-RecentList)) {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Children.Add((New-TbI (Split-Path $p -Leaf) 'Bold')) | Out-Null; $sp.Children.Add((New-TbI $p)) | Out-Null
    $it = New-Object Windows.Controls.ListBoxItem; $it.Content = $sp; $it.Tag = $p; $it.Style = $script:Res['RowItem']; $it.ToolTip = "Open $p"; Acc $it "$(Split-Path $p -Leaf), $p"; [void]$lbRecent.Items.Add($it)
  }
  $recentNone.Visibility = Vis ($lbRecent.Items.Count -eq 0)
}
# unsaved work that closing / switching folder would lose: waiting edits, unsaved typing (this commit and other kept drafts), a typed new-commit message
function Get-EPendingNote {
  $n = $script:eEdits.Count; $typed = [int](Get-PendingParts).Typed; $draft = [bool]($script:eChanges.Count -and $nMsg.Text.Trim())
  if (-not $n -and -not $draft -and -not $typed) { return $null }
  $a = @(); if ($n) { $a += "$(Format-Plural $n 'saved change') to old commits" }; if ($typed) { $a += "$(Format-Plural $typed 'change') you typed but did not keep" }; if ($draft) { $a += 'the message you typed for a new commit' }
  ($a -join ' and ')
}
#endregion



















#region opening a project: everything slow runs in the background runspace; a failed open never touches what is already loaded
$script:SnapScript = {
  param($path, $fetch, $keys, $ui)
  $root = Get-RepoRoot $path
  $r = @{ Root = $root; Fetched = $null }
  if ($fetch) { $r.Fetched = $false; try { $r.Fetched = [bool](Update-RemoteRefs $root 20000) } catch { } }
  $r.Commits = @(Get-CommitList $root 300)
  $tot = Git-Out $root @('rev-list', '--count', 'HEAD'); $r.Total = $(if (-not $tot.Code -and $tot.Out -and $tot.Out[0] -match '^\d+$') { [int]$tot.Out[0] } else { $r.Commits.Count })
  $r.Changes = @(); $r.ChangesErr = $null; try { $r.Changes = @(Get-WorkingChanges $root) } catch { $r.ChangesErr = $_.Exception.Message }
  $r.Push = $null; $r.PushErr = $null; try { $r.Push = Get-PushState $root } catch { $r.PushErr = $_.Exception.Message }
  $r.Detached = [bool](-not (Get-BranchName $root))
  $r.Backups = @(); try { $r.Backups = @(Get-Backups $root) } catch { }
  $r.OnGh = $null
  if ($r.Push -and $r.Push.TrackingSha) { $o = Git-Out $root @('rev-list', '--max-count=5000', $r.Push.TrackingSha); if (-not $o.Code) { $r.OnGh = @($o.Out | Where-Object { $_ }) } }
  $par = @{}; foreach ($l in (Git-Out $root @('log', '-n300', '--format=%H %P')).Out) { $x = @($l -split ' ' | Where-Object { $_ }); if ($x.Count) { $par[$x[0]] = @($x | Select-Object -Skip 1) } }; $r.Parents = $par
  $r.Identity = $null; try { $r.Identity = Get-GitIdentity $root } catch { }
  $bad = @(); foreach ($k in @($keys)) { if ($k -and (Git-Out $root @('merge-base', '--is-ancestor', $k, 'HEAD')).Code -ne 0) { $bad += $k } }; $r.BadKeys = $bad
  $r.Ignore = $null
  try { if (Get-Command Get-GitignoreKind -ErrorAction SilentlyContinue) { $has = Test-Path -LiteralPath (Join-Path $root '.gitignore'); $nz = @($r.Changes | Where-Object { $_.PSObject.Properties['Noise'] -and $_.Noise }).Count; $r.Ignore = [pscustomobject]@{ Needed = (-not $has -and $nz -gt 0); HasFile = $has; NoiseCount = $nz; Kind = (Get-GitignoreKind $root) } } } catch { }
  $r.Plan = $null; try { $r.Plan = Get-WorkflowPlan $root $(if ($ui) { $ui } else { @{} }) } catch { }
  [pscustomobject]$r
}
$script:TrustHook = $null
function Show-Untrusted([string]$path, [string]$msg) {
  $root = $path; try { $x = Test-IsRepo $path; if ($x.Root) { $root = $x.Root } } catch { }
  $names = @(); try { $names = @(Get-RiskyRepoConfig $root | ForEach-Object { CT "$_" 80 }) } catch { }
  $trust = $false
  if ($script:TrustHook) { $trust = [bool](& $script:TrustHook $root $names) }
  elseif ($script:Confirm) {
    $body = "Downloaded projects can contain hidden settings that make git run programs on your PC every time it looks at the folder. Only continue if you made this project, or you trust whoever gave it to you.`n`nSettings found: $($names -join ', ')"
    $trust = ((Ask 'backd8 Setup - untrusted project' 'This project can run programs on your PC' $body @('Choose another folder', 'I made this project / I trust it') 0 'warn' $msg 0) -eq 1)
  }
  if ($trust) { $script:eFolder = $root; $wr = Invoke-Wf 'Trust' @{} 'Trusting the project...'; if (Handle-WfResult $wr 'Trust') { Add-ELog "$($wr.Result)"; Do-ELoad $root -Fetch -Chosen $path }; return }
  Add-ELog "Not opened: this project's own git settings can run programs ($($names -join ', '))."
  if (-not $script:eRepo) { $script:eLoadErr = $msg; Update-EBanners; Update-EUi } else { $tbPath.Text = $script:eRepo }
}
function Do-ELoad([string]$path, [switch]$Quiet, [switch]$NoAccess, [string]$Chosen, [switch]$Fetch) {
  try {
    if (-not $path) { $path = $tbPath.Text.Trim().Trim('"') }
    $snap = Invoke-Bg $(if ($Fetch) { 'Opening the project and checking GitHub...' } else { 'Reading the project...' }) $script:SnapScript @($path, [bool]$Fetch, @($script:eEdits.Keys), @{ EditsStaged = [int]$script:eEdits.Count }) $true
    $root = $snap.Root
    $same = $script:eRepo -and (Norm $root) -eq (Norm $script:eRepo)
    if (-not $same -and $script:eRepo) {
      $pend = Get-EPendingNote
      if ($pend -and $script:Confirm) {
        if ((Ask 'backd8 Setup - open another folder' "Leave '$(Get-RepoLeaf)' and lose unsaved work?" "You have $pend that $(if ($pend -match '^1 ') { 'is' } else { 'are' }) not saved into git yet. They are lost if you continue." @('Discard and open the other folder', 'Keep working here') 1 'warn') -ne 0) { $tbPath.Text = $script:eRepo; return }
      }
    }
    if (-not $same) { $script:eEdits = @{}; $script:eSel = $null; $script:eSelShas = @(); $script:eOrig = @{}; $script:eChecks = @{}; $script:eDrafts = @{}; $script:eWarnings = @(); $script:eConflict = $null; $script:eIgnoreHide = $false; $script:eFinish = $null; $nMsg.Text = ''; Clear-EDetail }
    $script:eLoadErr = $null; $script:ePlain = $null; $script:eRepo = $root; $script:eFolder = $root; $script:eWf = $snap.Plan; $tbPath.Text = $root
    $script:eSubNote = $null; if ($Chosen -and (Norm $Chosen) -ne (Norm $root)) { $script:eSubNote = "You chose '$Chosen', which is inside the project '$root'. backd8 works on the whole project." }
    $script:eCommits = @($snap.Commits); $script:eTotal = [int]$snap.Total; $script:eChanges = @($snap.Changes); $script:ePush = $snap.Push; $script:ePushErr = $snap.PushErr; $script:eDetached = [bool]$snap.Detached
    $script:eBackups = @($snap.Backups); $script:eParents = $snap.Parents; $script:eTracked = [bool]($snap.Push -and $snap.Push.TrackingSha); $script:eIgnore = $snap.Ignore
    $script:eOnGh = $(if ($snap.OnGh) { New-Object 'System.Collections.Generic.HashSet[string]' (, [string[]]@($snap.OnGh)) } else { $null })
    if ($Fetch) { $script:eFetch = $snap.Fetched } elseif (-not $same) { $script:eFetch = $null }
    if ($snap.ChangesErr) { Add-ELog "Could not read changed files: $($snap.ChangesErr)" }
    if ($Fetch -and $snap.Fetched -eq $false -and $snap.Push -and $snap.Push.Url) { Add-ELog "Could not reach GitHub just now, so the GitHub status is as of your last check." }
    if ($snap.Identity -and $script:PreCache -and $script:PreCache.Git) { $script:PreCache.Name = "$($snap.Identity.Name)"; $script:PreCache.Mail = "$($snap.Identity.Email)"; $script:PreCache.Ok = [bool]$snap.Identity.Ok }
    # a saved change whose commit vanished (amend / rebase / reset outside backd8) is dropped, and the user is told
    $gone = @(); foreach ($k in @($snap.BadKeys)) { if ($script:eEdits.ContainsKey($k)) { $gone += $k.Substring(0, 7); [void]$script:eEdits.Remove($k); [void]$script:eOrig.Remove($k) }; if ($script:eDrafts.ContainsKey($k)) { [void]$script:eDrafts.Remove($k) } }
    if ($script:eSel -and -not (Find-ECommit $script:eSel)) { Clear-EDetail }
    Fill-EFiles; Fill-EList; Fill-Recent; Update-EBanners; Update-EUi
    Add-ELog "Opened $root - $(Format-Plural $script:eTotal 'commit')$(if ($script:eChanges.Count) { ", $(Format-Plural $script:eChanges.Count 'changed file') not committed" })."
    if ($gone.Count) { Add-ELog "Dropped your saved change to $($gone -join ', '): that commit no longer exists."; Show-Result 'warn' "Dropped $(Format-Plural $gone.Count 'saved change')" "The commit $($gone -join ', ') $(if ($gone.Count -eq 1) { 'no longer exists' } else { 'no longer exist' }) (the history was changed outside backd8), so your waiting change to $(if ($gone.Count -eq 1) { 'it' } else { 'them' }) was dropped." @() $true }
    if (-not $same) { $script:eAccess = $null; Update-EAccessLabel }
    if ($script:Confirm) { Save-Ui $null '' $root }
    if (-not $script:eSelShas -or -not $script:eSelShas.Count) { Show-EView 'none' }
    elseif ($script:eView -eq 'new' -and -not $script:eChanges.Count) { Clear-EDetail }
    Update-EUi
    Show-WfState
    if (-not $NoAccess) { Update-EAccess }
  } catch {
    if ("$($_.Exception.Message)" -like 'UNTRUSTED PROJECT:*') { Show-Untrusted $path "$($_.Exception.Message)"; return }
    if ($Quiet) { Add-ELog "Could not open: $($_.Exception.Message)"; return }
    if ($script:eRepo) { $tbPath.Text = $script:eRepo; if ($script:Confirm) { Add-ELog "ERROR: $($_.Exception.Message)"; Fail $_ } else { EFail $_ } }
    elseif ($script:Confirm) { $m = $_.Exception.Message; $script:eLoadErr = $m; Update-EBanners; Update-EUi; Add-ELog "ERROR: $m" }
    else { Reset-ELoaded; EFail $_ }
  }
}
# One entry point for every way of choosing a folder: browse, paste, recent list, drag and drop, last session.
function Open-Folder([string]$path, [switch]$Quiet, [switch]$NoAccess, [switch]$NoFetch) {
  try {
    if ($script:eBusy) { return }
    $path = "$path".Trim().Trim('"'); if (-not $path) { $script:eLoadErr = $null; $script:eSubNote = $null; Update-EBanners; return }
    if (Test-Path -LiteralPath $path -PathType Leaf) { throw "That path is a file, not a folder: $path. Choose the folder that contains your project." }
    if (-not (Test-GitInstalled)) { Update-EBanners; Add-ELog 'Git is not installed - see "Before we start".'; return }
    $t = Invoke-Bg 'Looking at the folder...' { param($p) Test-IsRepo $p } @($path)
    if (-not $t.Exists) { throw "Folder not found: $path" }
    if (-not $t.IsRepo) {
      $pend = Get-EPendingNote
      if ($script:eRepo -and $pend -and $script:Confirm -and (Ask 'backd8 Setup - open another folder' "Leave '$(Get-RepoLeaf)' and lose unsaved work?" "You have $pend that $(if ($pend -match '^1 ') { 'is' } else { 'are' }) not saved into git yet. They are lost if you continue." @('Discard and open the other folder', 'Keep working here') 1 'warn') -ne 0) { $tbPath.Text = $script:eRepo; return }
      Reset-ELoaded; $script:ePlain = $t.Folder; $tbPath.Text = $t.Folder; $wpFolder.Text = $t.Folder; $tbInit.Text = ''; $wpErr.Visibility = 'Collapsed'; $rbInit.IsChecked = $true
      Add-ELog "$($t.Folder) is not a git project yet."; $script:eFolder = $t.Folder; Refresh-Wf; return
    }
    Do-ELoad $t.Root -Quiet:$Quiet -NoAccess:$NoAccess -Chosen $t.Folder -Fetch:(-not $NoFetch)
  } catch {
    if ("$($_.Exception.Message)" -like 'UNTRUSTED PROJECT:*') { Show-Untrusted $path "$($_.Exception.Message)"; return }
    if ($Quiet) { Add-ELog "Could not open: $($_.Exception.Message)"; return }
    if ($script:eRepo) { $tbPath.Text = $script:eRepo; if ($script:Confirm) { Add-ELog "ERROR: $($_.Exception.Message)"; Fail $_ } else { EFail $_ } }
    elseif ($script:Confirm) { $m = $_.Exception.Message; $script:eLoadErr = $m; Update-EBanners; Update-EUi; Add-ELog "ERROR: $m" }
    else { Reset-ELoaded; EFail $_ }
  }
}
function Refresh-AfterCancel { if ($script:eRepo -and -not $script:eBusy -and -not $script:inCancelRefresh) { $script:inCancelRefresh = $true; try { Do-ELoad $script:eRepo -NoAccess } finally { $script:inCancelRefresh = $false } } }
function Do-EBrowse([string]$path) {
  try {
    if ($script:eBusy) { return }
    if (-not $path) {
      $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose the folder of your project'
      if ($tbPath.Text -and (Test-Path -LiteralPath $tbPath.Text -PathType Container)) { $d.SelectedPath = $tbPath.Text }
      if ($d.ShowDialog() -ne 'OK') { return }; $path = $d.SelectedPath
    }
  } catch { EFail $_; return }
  Open-Folder $path
}
function Do-EInit([string]$url) {
  try {
    if (-not $script:ePlain) { return }
    if (-not $PSBoundParameters.ContainsKey('url')) { $url = $tbInit.Text.Trim() }
    if ($url) { $prob = Get-RemoteUrlProblem $url; if ($prob) { $wpErr.Text = $prob; $wpErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw $prob }; return } }
    $wpErr.Visibility = 'Collapsed'; $folder = $script:ePlain
    $wr = Invoke-Wf 'InitProject' @{ Url = $url } 'Setting up the project...'; if (-not (Handle-WfResult $wr 'InitProject')) { return }
    Add-ELog "Turned $folder into a git project$(if ($url) { " linked to $(Hide-Secrets $url)" })."
    $script:ePlain = $null; Open-Folder $folder -NoFetch
    Show-Toast 'Your folder is now a git project' 'ok' 'Press Next to save your files as the first commit.'
  } catch { EFail $_ }
}
function Do-EConnect([string]$url) {
  try {
    if (-not $script:eRepo) { return }
    if (-not $PSBoundParameters.ContainsKey('url')) { $url = $tbLink.Text.Trim() }
    $prob = Get-RemoteUrlProblem $url
    if ($prob) { $lLinkErr.Text = $prob; $lLinkErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw $prob }; return }
    $lLinkErr.Visibility = 'Collapsed'
    $wr = Invoke-Wf $(if ($script:eWf -and $script:eWf.State -eq 'NoRemote') { 'ConnectRemote' } else { 'ChangeAddress' }) @{ Url = $url } 'Connecting...'; if (-not (Handle-WfResult $wr 'ConnectRemote')) { return }; Add-ELog "$($wr.Result)"
    $tbLink.Text = ''; $script:eAccess = $null
    Do-ELoad $script:eRepo -NoAccess -Fetch
    Show-Toast 'Connected to GitHub' 'ok' 'Next: save your changes, then publish.'
    Update-EAccess
  } catch { EFail $_ }
}
#endregion

#region selecting commits, editing, keeping or discarding a change
function Do-ESelect([string]$sha) {
  try {
    $items = @($lbHist.SelectedItems)
    $tags = @(if ($sha) { $sha } else { $items | ForEach-Object { [string]$_.Tag } })
    $prev = $script:eSel
    if ($prev -and (Get-EDirty) -and -not ($tags.Count -eq 1 -and $tags[0] -eq $prev)) {
      if (-not (Sync-EEdit)) {   # typed change is invalid: never drop it - keep it as a draft for that commit and say why
        $pc = Find-ECommit $prev; $why = Get-EValidation
        $script:eDrafts[$prev] = @{ msg = $eMsg.Text; date = $ePick.Date.Text; time = $ePick.Time.Text }
        Add-ELog "Kept your unsaved typing for $($pc.Short): $why"
        Show-Result 'warn' "Kept your unsaved typing for commit $($pc.Short)" "It is not saved as a change yet: $why Click that commit again to finish it." @() $true
      }
    }
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
    try {
      $ePick.Value = $c.Date; $ePick.Value = $d
      $eMsg.Text = $msg -replace "`r?`n", "`r`n"
      $dr = $script:eDrafts[$c.Sha]
      if ($dr) { $eMsg.Text = $dr.msg; $ePick.Date.Text = $dr.date; $ePick.Time.Text = $dr.time; [void]$script:eDrafts.Remove($c.Sha) }
    } finally { $script:eLoading = $false }
    $eWarn.Visibility = 'Collapsed'; Show-EView 'commit'
    Update-EUi
  } catch { EFail $_ }
}
function Update-EMulti {
  $n = @($script:eSelShas | Where-Object { $_ -ne '__new__' }).Count; if ($n -lt 2) { return }
  $s = $mPick.Value
  if ($s -eq [datetime]::MinValue) { $mPrev.Text = $mPick.Problem; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $mBtn.IsEnabled = $false; return }
  $prob = Get-DateProblem $s
  if ($prob) { $mPrev.Text = $prob; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $mBtn.IsEnabled = $false; return }
  $now = Get-Date; $worst = $s.AddMinutes(360 * ($n - 1)); $latest = $now.AddMinutes(-360 * ($n - 1))
  $idx = @($script:eSelShas | Where-Object { $_ -ne '__new__' } | ForEach-Object { $k = $_; $i = 0; foreach ($c in $script:eCommits) { if ($c.Sha -eq $k) { break }; $i++ }; $i })
  $gap = [bool](($idx | Measure-Object -Maximum).Maximum - ($idx | Measure-Object -Minimum).Minimum + 1 -ne $n)
  if ($worst -gt $now) { $mPrev.Text = "These $n commits could run past today when spaced up to 6 hours apart. Choose a first date no later than $(Fmt $latest)."; SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) 'ErrFg'; $mBtn.IsEnabled = $false }
  else { $mPrev.Text = "From $(Fmt $s): the newest of the $n lands between $(Fmt ($s.AddMinutes(60 * ($n - 1)))) and $(Fmt $worst) (1 to 6 hours between commits)." + $(if ($gap) { "`r`n(!) These commits are not next to each other. The commits between them keep their old dates, so the history will be interleaved." } else { '' }); SetRes $mPrev ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($gap) { 'WarnFg' } else { 'Text' }); $mBtn.IsEnabled = $true }
}
function Do-ESpread {
  try {
    $shas = @($script:eSelShas | Where-Object { $_ -ne '__new__' }); if ($shas.Count -lt 1) { return }
    $cs = @($shas | ForEach-Object { Find-ECommit $_ } | Where-Object { $_ } | Sort-Object { $_.Date })
    $dates = $null; $last = $null
    foreach ($try in 1..8) { try { $dates = New-DateSpread -Start $mPick.Value -Count $cs.Count; break } catch { $last = $_ } }
    if (-not $dates) { throw $last }
    $before = @{}; foreach ($k in $script:eEdits.Keys) { $before[$k] = $script:eEdits[$k] }
    for ($i = 0; $i -lt $cs.Count; $i++) {
      $c = $cs[$i]; $ed = $script:eEdits[$c.Sha]; if (-not $ed) { $ed = @{} }
      $ed.date = $dates[$i]; $script:eEdits[$c.Sha] = $ed; Update-EItem $c.Sha
    }
    Add-ELog "Re-dated $($cs.Count) commit(s): $(Fmt $dates[0]) ... $(Fmt $dates[-1]). Press Next (Apply) to write them."
    $script:spreadUndo = $before
    Show-Result 'ok' "New dates set for $(Format-Plural $cs.Count 'commit')" 'Next: press Next to apply them to the project.' @(@{ Text = '&Undo'; Tip = 'Put the previous waiting changes back.'; Click = { $script:eEdits = @{}; foreach ($k in $script:spreadUndo.Keys) { $script:eEdits[$k] = $script:spreadUndo[$k] }; Fill-EList; Update-EUi } })
    Update-EUi
  } catch { EFail $_ }
}
# keep what is typed as a waiting change. Returns $true when the state is kept (or unchanged), $false when the typing cannot be kept.
function Sync-EEdit([switch]$Strict) {
  $c = Find-ECommit $script:eSel
  if (-not $c) { if ($Strict) { throw 'Select a commit first.' }; return $true }
  $new = Norm-Msg $eMsg.Text
  if (-not $new.Trim()) { $eWarn.Text = "The message can't be empty - this change is not kept."; $eWarn.Visibility = 'Visible'; if ($Strict) { throw 'The commit message cannot be empty.' }; return $false }
  $d = $ePick.Value; $prob = $ePick.Problem
  if ($prob) { $eWarn.Text = $prob; $eWarn.Visibility = 'Visible'; if ($Strict) { throw $prob }; return $false }
  $d = $d.AddMilliseconds(-$d.Millisecond)
  $eWarn.Visibility = 'Collapsed'
  $ed = @{}
  if ($new -cne (Get-EOrigMsg $c.Sha)) { $ed.message = $new }
  if ([math]::Abs(($d - $c.Date).TotalSeconds) -ge 1) { $ed.date = $d }
  if ($ed.Count) { $script:eEdits[$c.Sha] = $ed; Add-ELog "Saved change for $($c.Short): $((@($ed.Keys) | Sort-Object) -join ' + ')." }
  else { [void]$script:eEdits.Remove($c.Sha); if ($Strict) { Add-ELog "$($c.Short) is the same as the original - nothing to keep." } }
  [void]$script:eDrafts.Remove($c.Sha)
  Update-EItem $c.Sha; Update-EUi; $true
}
function Do-EStage { try { [void](Sync-EEdit -Strict) } catch { EFail $_ } }
function Do-EDiscard {
  try {
    $sha = $script:eSel
    if (-not $sha -or -not $script:eEdits.ContainsKey($sha)) { return }
    [void]$script:eEdits.Remove($sha); Add-ELog "Discarded your change to $($sha.Substring(0, 7))."
    Update-EItem $sha; Do-ESelect $sha
  } catch { EFail $_ }
}
function Do-EResetMsg { $c = Find-ECommit $script:eSel; if ($c) { $eMsg.Text = (Get-EOrigMsg $c.Sha) -replace "`r?`n", "`r`n"; Update-EUi } }
function Do-EResetDate { $c = Find-ECommit $script:eSel; if ($c) { $ePick.Value = $c.Date; Update-EUi } }
#endregion

#region saving a new commit, applying edits, undo
function Do-ENewCommit {
  try {
    if (-not $script:eRepo) { return }
    if ($script:eDetached) { throw 'You are not on a branch, so a commit cannot be saved. Switch to a branch in your git tool, then press F5.' }
    $files = @(Get-ECheckedFiles); $msg = $nMsg.Text
    if (-not $files.Count) { throw 'Choose at least one file to commit.' }
    if (-not $msg.Trim()) { throw 'Write a commit message first.' }
    $date = $null; if ($script:nWhen -ne 'now') { $date = $nPick.Value; $p = $nPick.Problem; if ($p) { throw $p } }
    $risky = @($script:eChanges | Where-Object { $_.Risky -and $files -contains $_.Path })
    if ($risky.Count -and $script:Confirm) {
      if ((Ask 'backd8 Setup - save commit' 'Save files that may hold secrets?' "These files usually contain passwords or private keys. Once they are on GitHub, assume they are public.`n`n$(($risky | ForEach-Object { $_.Path }) -join "`n")" @('Include them anyway', 'Cancel') 1 'error') -ne 0) { Add-ELog 'Commit cancelled.'; return $false }
    }
    $r = $script:eRepo; $firstCommit = (@($script:eCommits).Count -eq 0); $allowRisky = [bool]($risky.Count -and $script:Confirm)
    $wp = @{ Message = $msg; Files = $files }; if ($date) { $wp.Date = $date }; if ($allowRisky) { $wp.AllowRisky = $true }; $wr = Invoke-Wf 'Commit' $wp 'Saving your new commit...'; if (-not (Handle-WfResult $wr 'Commit')) { return $false }; $c = $wr.Result
    Add-ELog "Committed $($c.Short): $($c.Subject)  (dated $(Fmt $c.Date))"
    $script:eChecks = @{}; $nMsg.Text = ''; Save-Draft; $script:eSelShas = @(); Set-NewWhen 'now'
    Do-ELoad $r -NoAccess:(-not $firstCommit)
    Show-Toast "Saved commit $($c.Short) ($(Fmt $c.Date))" 'ok' $(if ($script:ePush -and $script:ePush.Url) { 'It is on this computer only. Next: press Next to continue, then publish it to GitHub.' } else { 'It is on this computer only. To publish it, connect a GitHub address first (page 1).' })
    return $true
  } catch { EFail $_ }
  $false
}
$script:PrepApply = {
  param($repo, $keys)
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($k in $keys) { $full = (Git-Out $repo @('rev-parse', '--verify', '-q', "$k^{commit}")).Out | Select-Object -First 1; if ($full) { [void]$set.Add($full); foreach ($x in (Git-Out $repo @('rev-list', '--ancestry-path', "$full..HEAD")).Out) { if ($x) { [void]$set.Add($x) } } } }
  $id = Get-GitIdentity $repo; $others = @{}
  foreach ($l in (Git-Out $repo @('log', '-n', '5000', '--format=%H%x1f%an%x1f%ae')).Out) { $p = $l -split [string][char]0x1F; if ($p.Count -ge 3 -and $set.Contains($p[0]) -and $id.Email -and $p[2].ToLowerInvariant() -ne $id.Email.ToLowerInvariant()) { $w = "$($p[1]) <$($p[2])>"; $others[$w] = 1 + [int]$others[$w] } }
  $pushed = 0
  try {
    $s = Get-PushState $repo; $ref = if ($s.Upstream) { $s.Upstream } else { "refs/remotes/$($s.Remote)/$($s.Branch)" }
    if (-not (Git-Out $repo @('rev-parse', '--verify', '-q', "$ref^{commit}")).Code) { foreach ($k in $keys) { if ((Git-Out $repo @('merge-base', '--is-ancestor', $k, $ref)).Code -eq 0) { $pushed++ } } }
  } catch { }
  [pscustomobject]@{ Rewrite = $set.Count; Others = @($others.Keys | Sort-Object); OtherCount = [int](@($others.Values | Measure-Object -Sum).Sum); Pushed = $pushed }
}
function Do-EApply([switch]$NoConfirm) {
  try {
    if ($script:eDetached) { throw 'You are not on a branch, so edits cannot be applied. Switch to a branch in your git tool, then press F5.' }
    if (Get-EDirty) { if (-not (Sync-EEdit)) { throw "Your typed change cannot be kept yet: $(Get-EValidation)" } }
    if (-not $script:eRepo -or -not $script:eEdits.Count) { return $false }
    $nE = $script:eEdits.Count; $keys = @($script:eEdits.Keys)
    $prep = Invoke-Bg 'Checking what will be rewritten...' $script:PrepApply @($script:eRepo, $keys)
    $pushed = [int]$prep.Pushed; $rw = [int]$prep.Rewrite
    if ($script:Confirm -and -not $NoConfirm) {
      $lines = foreach ($k in $keys) { $c = Find-ECommit $k; $e = $script:eEdits[$k]; if ($c) { "$($c.Short)  $((@($e.Keys) | Sort-Object) -join ' + ')  $($c.Subject)" } }
      $later = [math]::Max(0, $rw - $nE)
      $m = "You changed $(Format-Plural $nE 'commit'). " + $(if ($later) { "Git also has to re-save $(Format-Plural $later 'later commit') that come$(if ($later -eq 1) { 's' }) after $(if ($nE -eq 1) { 'it' } else { 'them' }), so $(Format-Plural $rw 'commit') $(if ($rw -eq 1) { 'gets a new ID' } else { 'get new IDs' })." } else { "No later commits need re-saving, so only $(if ($nE -eq 1) { 'that commit gets' } else { 'those commits get' }) $(if ($nE -eq 1) { 'a new ID' } else { 'new IDs' })." }) + "`n`n- Your files are not touched.`n- A backup of the current history is kept: Undo last edit (Ctrl+Z) brings it back.`n- Nothing is sent to GitHub until you publish."
      if ($pushed) { $m += "`n`n$(Format-Plural $pushed 'changed commit is' 'changed commits are') already on GitHub. Afterwards GitHub and your PC disagree until you replace GitHub's version." }
      $chk = ''; $dng = -1
      if ($prep.OtherCount -gt 0) { $m += "`n`n$(Format-Plural $prep.OtherCount 'of these commits was' 'of these commits were') written by other people: $(@($prep.Others) -join ', '). Changing them changes what GitHub shows for their work."; $chk = 'I understand that I am changing commits written by other people'; $dng = 0 }
      $r = Ask 'backd8 Setup - apply edits' "Apply $(Format-Plural $nE 'edit' 'edits') to this project?" $m @("Apply $(Format-Plural $nE 'edit' 'edits')", 'Cancel') $(if ($pushed -or $dng -ge 0) { 1 } else { 0 }) 'warn' (($lines | Select-Object -First 12) -join "`n") -1 $dng $chk
      if ($r -ne 0) { Add-ELog 'Apply cancelled - your changes are still waiting.'; return $false }
    }
    $ed = @{}; foreach ($k in $keys) { $ed[$k] = $script:eEdits[$k] }
    $wr = Invoke-Wf 'ApplyEdits' @{ Edits = $ed } 'Applying your edits...' $true; if (-not (Handle-WfResult $wr 'Apply')) { return $false }; $res = $wr.Result
    $script:eEdits = @{}; $script:eOrig = @{}; $script:eDrafts = @{}; $script:eSel = $null; Clear-EDetail
    $warn = @($res.Warnings | Where-Object { $_ }); $script:eWarnings = $warn
    $out = "Edits applied: $($res.Edited) commit(s) edited, $($res.Rewritten) commit(s) got new hashes.`nNew head: $($res.NewHead.Substring(0, 7)).  Backup: $($res.Backup)`nUse 'Undo last edit' to go back."
    if ($res.SignaturesDropped -gt 0) { $out += "`nNote: $($res.SignaturesDropped) rewritten commit(s) were signed; the new commits are NOT signed (signatures cannot survive a rewrite)." }
    if (@($res.StaleRefs).Count) { $out += "`nNote: these branches/tags still point at the OLD commits (not rewritten): $(@($res.StaleRefs) -join ', '). Move or delete them yourself if they should follow the new history." }
    if ($pushed) { $out += "`nSome rewritten commits were already pushed: GitHub now needs its version replaced." }
    foreach ($w in $warn) { $out += "`nWarning: $w" }
    $auth = @($res.AuthorsAffected | Where-Object { $_ }); if ($auth.Count) { $out += "`nNote: commits written by other people were rewritten: $($auth -join ', ')."; $warn += "These commits were written by other people: $($auth -join ', '). What GitHub shows for their work changed." }
    Add-ELog $out
    Do-ELoad $script:eRepo -NoAccess
    if ($script:Confirm -and -not $NoConfirm) {
      $x = @("$(Format-Plural $res.Rewritten 'commit') $(if ($res.Rewritten -eq 1) { 'was' } else { 'were' }) rewritten ($($res.Edited) edited).")
      if ($pushed) { $x += "GitHub still has the old commits: publishing will replace them." } else { $x += 'Next: press Next to continue, then publish to GitHub.' }
      if ($res.SignaturesDropped -gt 0) { $x += "$(Format-Plural $res.SignaturesDropped 'rewritten commit was' 'rewritten commits were') signed. The new commits are NOT signed (signatures cannot survive a rewrite)." }
      if (@($res.StaleRefs).Count) { $x += "These branches/tags still point at the OLD commits: $(@($res.StaleRefs) -join ', '). Move them yourself if they should follow." }
      foreach ($w in $warn) { $x += "(!) $w" }
      Show-Result $(if ($warn.Count -or $res.SignaturesDropped -gt 0 -or @($res.StaleRefs).Count) { 'warn' } else { 'ok' }) "$(Format-Plural $res.Edited 'edit') applied" ($x -join "`r`n") @(@{ Text = '&Undo'; Tip = 'Put the project back to how it was before this Apply.'; Click = { Do-EUndo -NoConfirm } }) ([bool]($warn.Count -or @($res.StaleRefs).Count))
    }
    return $true
  } catch { EFail $_ }
  $false
}
function Do-EUndo([switch]$Force, [switch]$NoConfirm) {
  try {
    if (-not $script:eRepo) { return }
    if ($script:Confirm -and -not $NoConfirm) {
      $pend = Get-EPendingNote
      $m = "The project goes back to how it was before your last Apply. The re-saved commits are no longer on the branch.`n`n- This uses up the backup (press Undo again to go back one more step).`n- $(if ($pend) { "You have $pend - they are DISCARDED too." } else { 'No waiting changes are lost.' })`n- If the branch changed since the Apply, you will be asked again."
      if ((Ask 'backd8 Setup - undo' "Undo the last edit of '$(Get-RepoLeaf)'?" $m @('Undo it', 'Cancel') 1 'question') -ne 0) { return }
    }
    $msg = $null; $uerr = $null; $repo = $script:eRepo; $fo = [bool]$Force
    try { $wr = Invoke-Wf 'Undo' @{ Force = $fo } 'Restoring the previous history...'; if ($wr -and $wr.Ok) { $msg = $wr.Result } elseif ($wr) { $uerr = New-Err $wr.Message } } catch { $uerr = $_ }
    if ($uerr) {
      if ($uerr.Exception.Message -notlike 'The branch has changed since the last rewrite*') { throw $uerr.Exception.Message }
      Add-ELog "Undo refused: $($uerr.Exception.Message)"
      if (-not $script:Confirm) { return }
      $m = "Since the edit the branch changed (new commits, another edit or a reset).`n`nUndoing now moves the branch back and DROPS everything added since. Those newer commits would stay reachable ONLY through git's reflog (git reflog) until git cleans it up - backd8 does not back them up."
      if ((Ask 'backd8 Setup - undo refused' 'Undo anyway and drop the newer commits?' $m @('Undo anyway', 'Cancel') 1 'error' '' -1 0 'I understand the newer commits will be dropped from the branch') -ne 0) { Add-ELog 'Undo cancelled.'; return }
      $wr = Invoke-Wf 'Undo' @{ Force = $true } 'Restoring the previous history...'; if (-not (Handle-WfResult $wr 'Undo')) { return }; $msg = $wr.Result
    }
    $script:eEdits = @{}; $script:eOrig = @{}; $script:eDrafts = @{}; $script:eWarnings = @(); $script:eSel = $null; Clear-EDetail
    Add-ELog "$msg"
    Do-ELoad $script:eRepo -NoAccess
    Show-Toast 'Undone - your project is back as it was' 'info' 'Nothing was sent to GitHub. If GitHub already had the edited version, it now differs from yours.'
  } catch { EFail $_ }
}
#endregion

#region GitHub: sign in, get the latest, publish
function Offer-ESignIn([string]$why) {
  if ($script:SignInHook) { return $true }
  if (-not $script:Confirm) { return $false }
  (Ask 'backd8 Setup - sign in to GitHub' $why "Sign in now?`n`nA separate window opens (Git Credential Manager's browser login, the GitHub CLI or an SSH test). backd8 never stores a password or token." @('Sign in...', 'Not now') 0 'question') -eq 0
}
function Reset-AcctCache { try { if ($script:AcctCache) { $script:AcctCache.At = [datetime]::MinValue } } catch {} }
function Do-ESignIn {
  $a = $null
  try {
    if (-not $script:eRepo) { return $null }
    if (-not (Test-GitInstalled)) { throw $script:GitInstallHint }
    $r = $script:eRepo; Reset-AcctCache
    if ($script:SignInHook) { Add-ELog 'Signing in to GitHub (test hook)...'; $a = & $script:SignInHook $r }
    elseif ($script:Confirm) {
      Add-ELog 'Opening the GitHub sign-in window - finish it there, then come back...'
      try { $null = Invoke-Bg 'Waiting for the sign-in window - finish signing in there (Cancel just stops waiting)...' { param($p) Connect-GitHub $p } @($r) $true }
      catch { if ("$($_.Exception.Message)" -like 'Cancelled*') { Add-ELog 'Sign-in: stopped waiting.'; Show-Toast 'Stopped waiting for the sign-in' 'info' 'Press Check again when you have signed in.' } else { throw } }
      Reset-AcctCache; $a = Invoke-Bg 'Checking GitHub sign-in...' { param($p) Get-GitHubAccess $p } @($r) $true
    }
    else { Add-ELog 'Sign-in window skipped (non-interactive mode); only checking access.'; $a = Get-GitHubAccess $r }
    Set-EAccess $a
    if ($script:Confirm -and $a -and $a.CanPush -eq $true) { Show-Toast 'Signed in to GitHub' 'ok' 'The Sign in button is gone: backd8 will publish with this account.' }
  } catch { EFail $_ }
  $a
}
function Do-EUseAccount {
  try {
    $rb = @($spAccounts.Children | Where-Object { $_.IsChecked })[0]; if (-not $rb -or -not $script:eRepo) { return }
    $name = [string]$rb.Tag; $r = $script:eRepo
    $wr = Invoke-Wf 'ChooseAccount' @{ Account = $name } 'Remembering the GitHub account...'; if (-not (Handle-WfResult $wr 'ChooseAccount')) { return }
    Add-ELog "This project now uses the GitHub account $name."; Reset-AcctCache; $script:acctKey = ''
    Update-EAccess; Show-Toast "Using the GitHub account $name" 'ok' 'Publishing will use it without asking.'
  } catch { EFail $_ }
}
function Do-EFixAddress {
  try {
    $url = $tbFix.Text.Trim(); $prob = Get-RemoteUrlProblem $url
    if ($prob) { $fixErr.Text = $prob; $fixErr.Visibility = 'Visible'; if (-not $script:Confirm) { throw $prob }; return }
    $fixErr.Visibility = 'Collapsed'; $wr = Invoke-Wf $(if ($script:eWf -and $script:eWf.State -eq 'NoRemote') { 'ConnectRemote' } else { 'ChangeAddress' }) @{ Url = $url } 'Changing the address...'; if (-not (Handle-WfResult $wr 'ChangeAddress')) { return }; Add-ELog "$($wr.Result)"; $tbFix.Text = ''; $script:eAccess = $null; Reset-AcctCache
    Do-ELoad $script:eRepo -NoAccess -Fetch; Update-EAccess; Show-Toast 'GitHub address changed' 'ok' 'backd8 is checking the new address.'
  } catch { EFail $_ }
}function Show-Conflict($res) {
  $script:eConflict = $res; $pubConflict.Children.Clear()
  $sp = New-Object Windows.Controls.StackPanel
  $h = New-Object Windows.Controls.StackPanel; $h.Orientation = 'Horizontal'; $h.Children.Add((New-Icon 'warn' 24)) | Out-Null; $t = New-Tb "GitHub and your project both changed the same files" 12 'Text' 'Bold'; $t.Margin = '8,0,0,0'; $t.VerticalAlignment = 'Center'; $h.Children.Add($t) | Out-Null; $sp.Children.Add($h) | Out-Null
  $d = New-Tb "Nothing was changed - neither your project nor GitHub. backd8 cannot combine these automatically. Open the project folder and use a git tool (for example 'git pull' in a terminal, or GitHub Desktop) to combine them, then press F5 here." 11; $d.Margin = '0,6,0,6'; $sp.Children.Add($d) | Out-Null
  $tb = New-Object Windows.Controls.TextBox; $tb.IsReadOnly = $true; $tb.Height = 70; $tb.Text = ((@($res.Files)) -join "`r`n"); $tb.VerticalScrollBarVisibility = 'Auto'; $tb.VerticalContentAlignment = 'Top'; Acc $tb 'Files in conflict'; Tip $tb 'The files both sides changed.'; $sp.Children.Add($tb) | Out-Null
  $b = New-Button '&Open project folder' 'normal'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,6,0,0'; Tip $b 'Open the project folder in Windows Explorer.'; $b.Add_Click({ if ($script:Confirm -and $script:eRepo) { try { Start-Process explorer.exe $script:eRepo } catch {} } }); $sp.Children.Add($b) | Out-Null
  $pubConflict.Children.Add($sp) | Out-Null; Update-EUi
}
function Do-EGetLatest {
  try {
    $r = $script:eRepo; if (-not $r) { return $false }
    if (-not (Get-Command Merge-RemoteChanges -ErrorAction SilentlyContinue)) { throw "This copy of backd8 cannot get GitHub's changes yet. Run 'git pull' in the project folder, then press F5." }
    $wr = Invoke-Wf 'Sync' @{} 'Getting the latest from GitHub...' $true
    if ($wr -and $wr.ErrorClass -eq 'conflict') { Add-ELog 'Get latest: conflict'; Show-Conflict $wr.Result; Show-Result 'warn' 'GitHub and your project changed the same files' 'Nothing was changed. The files are listed below.' @() $true; return $false }
    if (-not (Handle-WfResult $wr 'Sync')) { return $false }; $res = $wr.Result
    Add-ELog "Get latest: $($res.Result) ($($res.Count))"
    if ($res.Result -eq 'conflict') { Show-Conflict $res; Show-Result 'warn' 'GitHub and your project changed the same files' 'Nothing was changed. The files are listed below.' @() $true; return $false }
    $script:eConflict = $null
    Do-ELoad $r -NoAccess -Fetch
    $next = $(if ($script:ePush -and $script:ePush.Ahead -gt 0) { 'Next: press Publish to send your commits.' } else { 'You are up to date.' })
    switch ($res.Result) {
      'nothing-on-github' { Show-Toast 'GitHub does not have this project yet' 'info' 'Nothing to get. Publishing will create it.' }
      'up-to-date' { Show-Toast 'Nothing new on GitHub' 'info' $next }
      'nothing-new' { Show-Toast 'GitHub only has the old versions of commits you changed' 'info' "There is nothing new to get. The next step is Replace GitHub's version, so GitHub gets your edited commits." }
      'fast-forward' { Show-Toast "Got $(Format-Plural $res.Count 'newer change') from GitHub" 'ok' $next }
      'merged' { Show-Toast "Got $(Format-Plural $res.Count 'newer change') and combined $(if ($res.Count -eq 1) { 'it' } else { 'them' }) with yours" 'ok' $next }
      'applied' { Show-Toast "A teammate's $(Format-Plural $res.Count 'commit was' 'commits were') added on top of your changed history" 'ok' "Next: Replace GitHub's version, so GitHub gets your edited commits together with theirs." }
      default { Show-Toast "Got the latest from GitHub" 'ok' $next }
    }
    return $true
  } catch { EFail $_ }
  $false
}
function Invoke-EPush([bool]$doForce, [bool]$discard, [bool]$retried) {
  $done = $false
  try {
    $r = $script:eRepo; $perr = $null; $out = $null; $sent = $(if ($script:ePush -and $null -ne $script:ePush.Ahead) { [int]$script:ePush.Ahead } else { @($script:eCommits).Count })
    try {
      if ($doForce -and $discard) { $out = Invoke-Bg "Replacing GitHub's version..." { param($p) Push-Repo $p -Force -DiscardRemote } @($r) $true; $wr = $null }   # advanced escape hatch (the model has no such action): only after the two explicit confirmations
      else { $wr = Invoke-Wf $(if ($doForce) { 'ReplaceRemote' } else { 'Publish' }) @{ Discard = [bool]$discard } $(if ($doForce) { "Replacing GitHub's version..." } else { 'Publishing to GitHub...' }) $true }
      if ($wr -and $wr.Ok) { $out = "$($wr.Result)" }
      elseif ($wr) { $perr = New-Err $(if ($doForce -and ($wr.From -eq 'NeedsSync' -or ($wr.Reason -eq 'guard' -and $wr.Message -like '*someone else*'))) { "Force push refused: GitHub holds commits that exist nowhere in this repository (written by someone else). $($wr.Message)" } else { $wr.Message }) }
    } catch { $perr = $_ }
    if (-not $perr) {
      Add-ELog "$out"; $done = $true; $script:eWarnings = @()
      if ($script:eAccess -and $script:eAccess.Transport -ne 'local') { $script:eAccess.CanPush = $true; Update-EAccessLabel }
      $script:eFinish = @{ Count = $sent; Replaced = $doForce }
      Do-ELoad $r -NoAccess
      Show-Toast 'Published to GitHub' 'ok' 'GitHub now has your last save.'
      if ("$out" -match 'moved to (\S+?)[\s\.]*(\r|\n|$)') { $script:movedUrl = $Matches[1]; Show-Result 'warn' 'GitHub says this project moved' "New address: $(CT $script:movedUrl 200). Publishing still worked." @(@{ Text = '&Update the address'; Tip = 'Use the new address for this project.'; Click = { try { Add-ELog (Set-RemoteUrl $script:eRepo $script:movedUrl); Do-ELoad $script:eRepo -NoAccess -Fetch } catch { EFail $_ } } }) $true }
    } else {
      $msg = $perr.Exception.Message
      if ($msg -like 'GitHub sign-in required*') {
        if ($retried) { throw $perr }
        Add-ELog "ERROR: $msg"
        if (Offer-ESignIn 'GitHub did not accept the upload: you are not signed in (or this account may not write to this project).') {
          $a = Do-ESignIn
          if ($a -and $a.CanPush -eq $true) { Add-ELog 'Signed in - retrying the upload once.'; return (Invoke-EPush $doForce $discard $true) }
          Add-ELog 'Still not signed in - nothing was uploaded.'
        } else { Add-ELog 'Upload cancelled: not signed in.' }
      }
      elseif ($msg -like '*newer change*' -and -not $doForce) {
        Add-ELog "ERROR: $msg"
        if ($script:Confirm) {
          if ((Ask 'backd8 Setup - GitHub has newer changes' 'GitHub has newer changes than you' "Someone (maybe you, on another PC) published after you last looked, so GitHub did not accept the upload.`n`nbackd8 can first get those changes and combine them with yours, then continue publishing. Nothing on GitHub is replaced." @('Get the latest and publish', 'Cancel') 1 'question') -eq 0) {
            if ((Do-EGetLatest) -and -not $retried) { return (Invoke-EPush $false $false $true) }
          } else { Add-ELog 'Cancelled: nothing was uploaded.' }
        } else { throw $perr }
      }
      elseif ($doForce -and -not $discard -and ($msg -like '*exist nowhere in this repository*' -or $msg -like '*written by someone else*')) {
        Add-ELog "ERROR: $msg"
        Do-ELoad $r -NoAccess
        $n = if ($msg -match 'has (\d+) commit' -or $msg -match 'remove (\d+) commit') { [int]$Matches[1] } else { 0 }; $byOthers = ($msg -like '*written by someone else*')
        if ($script:Confirm) {
          $m = $(if ($byOthers) { "$(if ($n) { Format-Plural $n 'commit' } else { 'Some commits' }) on GitHub $(if ($n -eq 1) { 'was' } else { 'were' }) written by OTHER PEOPLE (not your git identity).`n`nReplacing" } else { "$(if ($n) { Format-Plural $n 'commit' } else { 'Some commits' }) on GitHub $(if ($n -eq 1) { 'is' } else { 'are' }) in NO branch, tag or backup on this PC - most likely someone else's work.`n`nReplacing" }) + " GitHub's version DELETES $(if ($n -eq 1) { 'it' } else { 'them' }) for good. backd8 cannot bring $(if ($n -eq 1) { 'it' } else { 'them' }) back. Getting the latest from GitHub first keeps them."
          if ((Ask 'backd8 Setup - DELETE COMMITS ON GITHUB' "Delete $(if ($n) { Format-Plural $n 'commit' } else { 'commits' }) from GitHub that you don't have?" $m @("Delete and replace", 'Cancel, keep them') 1 'error' '' -1 0 "I know these commits will be deleted from GitHub") -eq 0) { return (Invoke-EPush $true $true $retried) }
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
    if ($script:eDetached) { throw 'You are not on a branch, so there is nothing to publish. Switch to a branch in your git tool, then press F5.' }
    # look at GitHub again right before publishing, so a stale "up to date" can never hide newer changes there
    try { $fx = Invoke-Bg 'Checking GitHub for newer changes...' { param($p) Update-RemoteRefs $p } @($script:eRepo) $true; $script:eFetch = [bool]$fx } catch { if ("$($_.Exception.Message)" -like 'Cancelled*') { throw }; $script:eFetch = $false }
    $s = Invoke-Bg 'Reading the GitHub state...' { param($p) Get-PushState $p } @($script:eRepo)
    $script:ePush = $s; Update-EInfo
    if ($script:Confirm -and $script:eEdits.Count) {
      $n = $script:eEdits.Count
      if ((Ask 'backd8 Setup - publish' "$(Format-Plural $n 'waiting change') will NOT be published" "Publishing only sends what is already in your project history. Your waiting changes are not applied yet. Go Back and press Next to apply them first if you want them on GitHub." @('Publish without them', 'Cancel') 1 'warn') -ne 0) { return $false }
    }
    if ($script:Confirm -and $s.Url -and $script:eAccess -and $script:eAccess.Transport -in 'https', 'ssh' -and $script:eAccess.CanPush -ne $true) {
      Update-EAccess
      if ($script:eAccess -and $script:eAccess.CanPush -eq $false) {
        if (-not (Offer-ESignIn 'This PC is not signed in to GitHub for this project, so publishing would fail.')) { Add-ELog 'Upload cancelled: not signed in.'; return $false }
        $a = Do-ESignIn
        if (-not $a -or $a.CanPush -ne $true) { Add-ELog 'Still not signed in - nothing was uploaded.'; return $false }
      }
    }
    if ($s.Url -and $s.Behind -gt 0 -and $s.Ahead -eq 0) {   # GitHub is simply ahead: never offer to replace it - get the latest instead
      Add-ELog "GitHub has $(Format-Plural $s.Behind 'newer change') - getting the latest is the next step, not publishing."
      if ($script:Confirm) {
        if ((Ask 'backd8 Setup - get the latest first' "GitHub has $(Format-Plural $s.Behind 'newer change') than your computer" "There is nothing of yours to publish yet. Get the latest from GitHub first: nothing on GitHub is replaced." @('Get the latest from GitHub', 'Cancel') 0 'question') -eq 0) { [void](Do-EGetLatest) }
      }
      return $false
    }
    $doForce = $false
    if ($s.Url -and $s.Behind -gt 0) {
      if ($script:Confirm) {
        $sameWho = $(if ($s.Behind -eq 1) { 'is' } else { 'are' })
        $m = "GitHub address: $($s.Url)`nBranch: $($s.Branch)  (remote '$($s.Remote)')`n`nGitHub still has an older version of this branch. If you continue:`n- GitHub's $(Format-Plural $s.Behind 'old commit') $sameWho REPLACED (deleted there).`n- Your $(Format-Plural $s.Ahead 'commit') $(if ($s.Ahead -eq 1) { 'takes' } else { 'take' }) $(if ($s.Ahead -eq 1) { 'its' } else { 'their' }) place.`n- Anyone who already copied this branch must download it again.`n- backd8 looks at GitHub again right before sending. If GitHub holds commits that exist nowhere on this PC, it stops and asks you again.`n- Your own backup of the old history stays on this PC (Undo last edit)."
        if ($s.Branch -in 'main', 'master' -or $s.Branch -match 'release|prod|stable|protected' -or $s.Remote -match 'upstream|prod') { $m += "`n`nReminder: '$($s.Branch)' on '$($s.Remote)' may be the main or a protected branch that other people rely on." }
        if ((Ask 'backd8 Setup - replace GitHub''s version' "Replace GitHub's version of '$($s.Branch)'?" $m @("Replace GitHub's version", 'Cancel') 1 'error' '' -1 0 "I understand GitHub will lose the old version of this branch") -ne 0) { Add-ELog 'Cancelled: GitHub was not changed.'; return $false }
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
    if ($script:eDetached) { throw 'You are not on a branch, so nothing can be saved or published. Switch to a branch in your git tool, then press F5.' }
    if (Get-EDirty) { if (-not (Sync-EEdit)) { throw "Your typed change cannot be kept yet: $(Get-EValidation)" } }
    $newReady = Get-ENewReady; $nE = $script:eEdits.Count
    if (-not $newReady -and -not $nE) { return }
    if (-not ($script:ePush -and $script:ePush.Url)) { throw 'This project is not connected to GitHub yet. Connect a GitHub address on page 1 first.' }
    $names = @(); if ($newReady) { $names += 'Save your new commit' }; if ($nE) { $names += 'Apply your edits' }; $names += 'Publish to GitHub'
    if ($script:Confirm) {
      $lines = @(); if ($newReady) { $lines += "- 1 new commit with $(Format-Plural (Get-ECheckedFiles).Count 'file'), dated $(if ($script:nWhen -ne 'now') { Fmt $nPick.Value } else { 'now' })" }
      if ($nE) { $lines += "- $(Format-Plural $nE 'edited commit') (every later commit gets a new ID; a backup is kept)" }
      $lines += "- Publish to $($script:ePush.Url)"
      if ($script:ePush.Behind -gt 0 -or $nE) { $lines += "`nIf GitHub already has the old version of an edited commit, you will be asked once more before it is replaced." }
      if ((Ask 'backd8 Setup - save and publish' 'Save everything and publish to GitHub?' ($lines -join "`n") @('Save and publish', 'Cancel') 0 'question') -ne 0) { Add-ELog 'Cancelled.'; return }
    }
    Start-ERun $names; $i = 0; $ok = $false
    try {
      if ($newReady) { Set-ERunStep $i 'run'; if (-not (Do-ENewCommit)) { Set-ERunStep $i 'fail'; return }; Set-ERunStep $i 'ok'; $i++ }
      if ($nE) { Set-ERunStep $i 'run'; if (-not (Do-EApply -NoConfirm)) { Set-ERunStep $i 'fail'; return }; Set-ERunStep $i 'ok'; $i++ }
      Set-ERunStep $i 'run'
      if (Do-EPush) { Set-ERunStep $i 'ok'; $ok = $true } else { Set-ERunStep $i 'fail'; Add-ELog 'Not published. Your commits and edits are saved on this PC; press the publish button when ready.' }
      if ($script:Confirm) { Start-Sleep -Milliseconds 700 }
    } finally { Stop-ERun }
    if ($ok) { Show-Finish }
  } catch { EFail $_; Stop-ERun }
}

function Show-Finish([object[]]$Steps = @()) {
  $fi = $script:eFinish; $st = $script:ePush
  $n = $(if ($fi) { [int]$fi.Count } else { 0 })
  $finTitle.Text = 'backd8 is complete'
  $finList.Children.Clear()
  foreach ($s in @($Steps)) { $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,3'; $ih = New-Object Windows.Controls.ContentControl; $ih.Width = 20; $ih.Content = (New-Icon 'check' 14); $row.Children.Add($ih) | Out-Null; $row.Children.Add((New-Tb $s.Text 11 'Text' 'Normal' $false)) | Out-Null; $finList.Children.Add($row) | Out-Null }
  $published = [bool](@($Steps | Where-Object { $_.Id -eq 'publish' }).Count -or -not @($Steps).Count)
  $finMsg.Text = $(if ($published) { "backd8 published $(if ($n) { Format-Plural $n 'commit' } else { 'your commits' }) to GitHub$(if ($st -and $st.Url) { " ($(Get-RepoUrlShort), branch $($st.Branch))" }).`r`n`r`n" + $(if ($fi -and $fi.Replaced) { "GitHub's old version of the branch was replaced by yours." } else { 'GitHub is up to date with your last save.' }) } else { 'Everything you asked for is done. Nothing was sent to GitHub.' })
  $url = if ($st -and $st.Url -match '^https?://github\.com/') { ($st.Url -replace '\.git$', '') } else { $null }
  $btnOpenGh.Visibility = Vis ([bool]($url -and $published)); $btnOpenGh.Tag = $url
  Nav-To 5
}
function Do-Another { if ($script:eBusy) { return }; $script:actDone = $false; $script:wizStack = @(); if ($script:eRepo) { Do-ELoad $script:eRepo -NoAccess }; Go-Page 2 }
function Enter-Actions {
  $acts = Get-EActions; $ok = @($acts.Keys | Where-Object { $acts[$_].Ok })
  if ($ok.Count -eq 1 -and $ok[0] -in 'express', 'edit') { $script:eAction = $ok[0]; $script:actDone = $true; Nav-To 3 } else { $script:actDone = $false; Nav-To 2 }
}


function Run-Plan {
  if ($script:ePlanRunning) { return }
  $script:eLastFail = $null; $script:ePlan = @(Get-EPlan)
  if (-not $script:ePlan.Count) { Update-EUi; return }
  $script:ePlanRunning = $true; $script:ePlanLocked = $true; $script:eInline = $true; $script:eQuiet = $true
  $ok = $true; $done = @()
  try {
    foreach ($s in $script:ePlan) {
      $s.State = 'run'; Render-Plan; if ($script:Confirm) { DoEvents }
      $r = $false
      switch ($s.Id) {
        'commit' { $r = [bool](Do-ENewCommit) }
        'apply' { $r = [bool](Do-EApply) }
        'getlatest' { $r = [bool](Do-EGetLatest) }
        'signin' { $a = Do-ESignIn; $r = [bool]($a -and $a.CanPush -eq $true); if (-not $r -and -not $script:eLastFail) { $script:eLastFail = @{ Heading = 'You are not signed in yet'; Next = 'Finish signing in (the sign-in window), then press Retry.'; Raw = '' } } }
        'publish' { $r = [bool](Do-EPush) }
      }
      if ($r) { $s.State = 'ok'; $done += $s; Render-Plan }
      else { $s.State = 'fail'; $ok = $false; if (-not $script:eLastFail) { $script:eLastFail = @{ Heading = 'You stopped here'; Next = 'Nothing further was done. Press Retry to try again, or Back to change something.'; Raw = '' } }; break }
    }
  } finally { $script:eInline = $false; $script:eQuiet = $false; $script:ePlanRunning = $false; $script:ePlanLocked = $false; $planBar.Visibility = 'Collapsed' }
  if ($ok) { if ($script:eWf -and $script:eWf.State -eq 'InSync') { Show-Finish $done } else { Show-WfState } }
  else { Render-Plan; if ($script:eLastFail -and "$($script:eLastFail.Raw)" -like 'Cancelled*') { Refresh-AfterCancel }; Update-EUi }
}
#endregion












#region the window is a VIEW of the engine's finite state machine (workflow.ps1): state -> page, actions -> buttons, every click -> Invoke-WorkflowAction
$script:eFolder = ''; $script:eWf = $null; $script:eSub = ''; $script:eSelAct = @{}; $script:eWfBusy = $false; $script:actKey = @{}
$script:WfPage = @{
  NoFolder = 1; FolderNotFound = 1; GitMissing = 1; NotAProject = 1; Untrusted = 1; NoIdentity = 1; Blocked = 1; Detached = 1; EmptyProject = 1
  ChangesPending = 3; EditsPending = 3
  NoRemote = 4; GitHubAhead = 4; NeedsSync = 4; NeedsReplace = 4; NeedsSignIn = 4; ChooseAccount = 4; NoWriteAccess = 4; RepoNotFound = 4; SSORequired = 4; HostKeyProblem = 4; Offline = 4; ReadyToPublish = 4
  InSync = 5
}
# the four sidebar steps are a projection of the states
$script:WfStep = @{
  NoFolder = 1; FolderNotFound = 1; GitMissing = 1; NotAProject = 1; Untrusted = 1; NoIdentity = 1; Blocked = 1; Detached = 1; EmptyProject = 1
  ChangesPending = 2; EditsPending = 2
  NoRemote = 3; NeedsSignIn = 3; ChooseAccount = 3; NoWriteAccess = 3; RepoNotFound = 3; SSORequired = 3; HostKeyProblem = 3; Offline = 3
  GitHubAhead = 4; NeedsSync = 4; NeedsReplace = 4; ReadyToPublish = 4; InSync = 4
}
function Get-StepDefs { @(@('Choose your project', 'folder'), @('Change dates and messages', 'page'), @('Sign in to GitHub', 'key'), @('Publish to GitHub', 'globe')) }

# ---- inputs -> action parameters (the guards in the model validate them; the view never decides)
function Get-WfUrl { switch ($script:eWf.State) { 'NotAProject' { $tbInit.Text.Trim() } 'NoRemote' { $tbLink.Text.Trim() } default { $tbFix.Text.Trim() } } }
function Get-WfParams {
  $p = @{ Message = $nMsg.Text; Files = @(Get-ECheckedFiles); Url = (Get-WfUrl); Name = $tbName.Text.Trim(); Email = $tbMail.Text.Trim(); Edits = $script:eEdits; Discard = $false; Kind = $(if ($script:eIgnore) { $script:eIgnore.Kind } else { $null }) }
  if ($script:nWhen -ne 'now') { $p.Date = $nPick.Value }
  $sel = @($spAccounts.Children | Where-Object { $_.IsChecked })[0]; if ($sel) { $p.Account = [string]$sel.Tag }
  $p
}
# pure re-derivation from the stored facts + the current inputs (no git, no network): keeps buttons truthful on every keystroke
function Update-WfLocal {
  $w = $script:eWf; if (-not $w) { return }
  $f = $w.Facts; $f.EditsStaged = [int]$script:eEdits.Count
  $s = Resolve-WorkflowState $f
  $acts = @(Get-WorkflowActions $s $f (Get-WfParams))
  $dateProblem = $(if ($script:nWhen -ne 'now') { $nPick.Problem } else { $null })
  $acts = @($acts | ForEach-Object { if ($_.Id -eq 'Commit' -and $dateProblem -and $_.Enabled) { $_.Enabled = $false; $_.Why = $dateProblem }; $_ })
  # every page keeps a working way out: if the model offers no "check again" / "choose a folder" action here, the view adds them (both are view-handled navigation)
  foreach ($esc in @(@('Recheck', 'Check again'), @('ChooseFolder', 'Choose another folder...'))) { if ($s -ne 'NoFolder' -and -not @($acts | Where-Object { $_.Id -eq $esc[0] }).Count) { $acts += [pscustomobject]@{ Id = $esc[0]; Label = $esc[1]; Kind = 'nav'; Next = @(); Enabled = $true; Why = $null } } }
  $rec = ($acts | Where-Object { $_.Kind -eq 'engine' } | Select-Object -First 1); if (-not $rec) { $rec = $acts | Select-Object -First 1 }
  $w.State = $s; $w.Title = $script:WfStates[$s].Title; $w.Help = $script:WfStates[$s].Help; $w.Actions = $acts
  $w.Recommended = $(if ($rec) { $rec.Id }); $w.RecommendedEnabled = [bool]($rec -and $rec.Enabled); $w.RecommendedWhy = $(if ($rec) { $rec.Why })
}
function Get-WfAct([string]$id) { @($script:eWf.Actions | Where-Object { $_.Id -eq $id })[0] }
# the publish destination as "owner/repo" when it is a GitHub address (else the last part of the address)
function Get-Dest {
  $u = ''; if ($script:eWf -and $script:eWf.Facts.Url) { $u = "$($script:eWf.Facts.Url)" }
  if ($u -match 'github\.com[:/]+([^/\s]+)/([^/\s]+?)(\.git)?/?$') { return (CT "$($Matches[1])/$($Matches[2])" 120) }
  if ($u) { $seg = @($u -split '[\\/]' | Where-Object { $_ -and $_ -notmatch ':$' }); $d = (@($seg | Select-Object -Last 2) -join '/') -replace '\.git$', ''; return (CT $d 120) }
  ''
}
# every button gets a tooltip (the accessible name when nothing better was set)
function Ensure-Tips {
  $stack = New-Object System.Collections.Stack; $stack.Push($f)
  while ($stack.Count) {
    $x = $stack.Pop()
    if (($x -is [Windows.Controls.Primitives.ButtonBase]) -and -not $x.ToolTip) { $n = [Windows.Automation.AutomationProperties]::GetName($x); if (-not $n) { $n = Get-Mn $x }; if ($n) { Tip $x $n } }
    foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($x)) { if ($c -is [Windows.DependencyObject]) { $stack.Push($c) } }
  }
}
function Get-ENext {
  $w = $script:eWf; $dirty = [bool](Get-EDirty); $inv = $(if ($dirty) { Get-EValidation } else { $null })
  if (-not $w) { return [pscustomobject]@{ Role = 'none'; Text = 'Choose a folder first'; Reason = 'Choose a project folder first.'; Enabled = $false; CanPush = $false; Force = $false; NeedGet = $false; Diverged = $false; Others = $false; NewReady = $false; Dirty = $dirty; Invalid = $inv; Edits = 0; HasRemote = $false; State = 'NoFolder' } }
  $rec = Get-WfAct $w.Recommended; $st = $w.State
  $role = switch ($w.Recommended) { 'Commit' { 'commit' } 'ApplyEdits' { 'apply' } 'Sync' { 'getnew' } 'ReplaceRemote' { 'force' } 'Publish' { 'push' } 'SignIn' { 'signin' } 'ChooseAccount' { 'account' } default { 'none' } }
  $text = $(if ($rec) { $rec.Label } else { 'Next' }); $reason = $w.RecommendedWhy
  if ($w.Recommended -eq 'ApplyEdits') { $text = "Apply my $(Format-Plural ([int]$script:eEdits.Count) 'edit' 'edits')" }
  if ($inv) { $role = 'invalid'; $reason = $inv }
  elseif ($st -in 'Detached', 'Blocked') { $role = 'blocked' }
  [pscustomobject]@{ Role = $role; Text = $text; Reason = $reason; Enabled = [bool]($w.RecommendedEnabled -and -not $inv); CanPush = ($st -eq 'ReadyToPublish'); Force = ($st -eq 'NeedsReplace'); NeedGet = ($st -in 'GitHubAhead', 'NeedsSync'); Diverged = ($st -in 'NeedsSync', 'NeedsReplace'); Others = ($st -eq 'NeedsSync')
    NewReady = [bool]($st -eq 'ChangesPending' -and ((Get-WfAct 'Commit').Enabled)); Dirty = $dirty; Invalid = $inv; Edits = [int]$script:eEdits.Count; HasRemote = [bool]$w.Facts.Linked; State = $st }
}
function Get-ENewReady { [bool]((Get-ENext).NewReady) }

# ---- the heavy plan (background runspace): on load/open/F5 and after every action
function Refresh-Wf([switch]$CheckAccess, [switch]$Fetch) {
  $script:eWf = Invoke-Bg 'Checking the project...' { param($p, $ui, $ca, $fe) Get-WorkflowPlan $p $ui @{} -CheckAccess:$ca -Fetch:$fe } @($script:eFolder, @{ EditsStaged = [int]$script:eEdits.Count }, [bool]$CheckAccess, [bool]$Fetch)
  Show-WfState
}
# projection of Get-GitHubAccess into the model's Access fact (same mapping as workflow.ps1) so the sign-in states appear as soon as the check is known
function Set-WfAccess($a) {
  $w = $script:eWf; if (-not $w -or -not $a -or -not $w.Facts.Linked) { return }
  $w.Facts.AccessDetail = "$($a.Detail)"
  $w.Facts.Access = if ($a.Transport -eq 'local') { 'Yes' } elseif ($a.CanPush -eq $true) { 'Yes' } elseif ($a.NeedsAccountChoice) { 'ChooseAccount' }
    elseif ($a.Problem -eq 'noaccess') { 'NoAccess' } elseif ($a.Problem -eq 'notfound') { 'NotFound' } elseif ($a.Problem -eq 'saml') { 'SSO' } elseif ($a.Problem -eq 'hostkey') { 'HostKey' }
    elseif ($a.CanPush -eq $false) { 'NotSignedIn' } elseif ($a.Problem -in 'network', 'temporary') { 'Offline' } else { 'Unknown' }
}
function Show-WfState {
  Update-WfLocal
  $w = $script:eWf; if (-not $w) { Go-Page 1; return }
  $st = $w.State
  if ($script:eSub -eq 'edit' -and $st -notin 'InSync', 'EditsPending') { $script:eSub = '' }
  $pg = [int]$script:WfPage[$st]
  if ($st -eq 'ChangesPending') { $script:eAction = 'express' } elseif ($st -eq 'EditsPending' -or ($script:eSub -eq 'edit' -and $st -eq 'InSync')) { $script:eAction = 'edit'; $pg = 3 }
  Go-Page $pg
}
function Go-Page([int]$n) {
  $script:wizPage = $n
  foreach ($i in 1, 3, 4, 5) { $p = Get-Variable -Name "p$i" -ValueOnly -Scope Script; $p.Visibility = Vis ($i -eq $n) }
  $p3x.Visibility = Vis ($n -eq 3 -and $script:eAction -eq 'express'); $p3e.Visibility = Vis ($n -eq 3 -and $script:eAction -ne 'express')
  $artHost.Child = (New-Art $(switch ($n) { 1 { 'p1' } 3 { $(if ($script:eAction -eq 'express') { 'p1' } else { 'p2' }) } 4 { 'p4' } default { 'p3' } }))
  $resBar.Visibility = 'Collapsed'
  if ($n -ne 4) { $script:eConflict = $null; $script:eLastFail = $null; $script:ePlanLocked = $false }
  if ($n -eq 3 -and $script:eAction -eq 'express' -and -not $nMsg.Text.Trim() -and $script:eChanges.Count) { $d = Get-SavedDraft; $nMsg.Text = $(if ($d) { $d } else { Get-ChangeSuggestion }) }
  if ($n -eq 3 -and $script:eAction -ne 'express') { $eTitle.Text = $(if ($script:eSub -eq 'edit') { 'Change an older commit' } else { 'Your edits are waiting' }) }
  Update-EUi
  if ($script:Confirm) { try { $t = switch ($n) { 1 { $btnBrowse } 3 { $(if ($script:eAction -eq 'express') { $nMsg } else { $lbHist }) } default { $btnNext } }; [void]$t.Focus() } catch {} }
}
function Update-Side {
  $step = $(if ($script:eWf) { [int]$script:WfStep[$script:eWf.State] } else { 1 }); if ($script:eSub -eq 'edit') { $step = 2 }
  $finished = ($script:eWf -and $script:eWf.State -eq 'InSync' -and $script:wizPage -eq 5)
  for ($i = 0; $i -lt 4; $i++) {
    $r = $script:SideRows[$i]; $n = $i + 1; $done = ($n -lt $step) -or $finished; $cur = ($n -eq $step) -and -not $finished
    $r.Text.Text = (Get-StepDefs)[$i][0]
    $r.Text.FontWeight = $(if ($cur) { 'Bold' } else { 'Normal' }); SetRes $r.Text ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($cur) { 'Yellow' } else { 'SideText' })
    if ($done) { $ck = New-Object Windows.Controls.TextBlock; $ck.Text = 'a'; $ck.FontFamily = New-Object Windows.Media.FontFamily('Marlett'); $ck.FontSize = 13; SetRes $ck ([Windows.Controls.TextBlock]::ForegroundProperty) 'SideText'; $ck.VerticalAlignment = 'Top'; $r.Icon.Content = $ck } else { $r.Icon.Content = (New-Icon (Get-StepDefs)[$i][1] 16) }
    Acc $r.Grid "Step $n of 4: $((Get-StepDefs)[$i][0]), $(if ($done) { 'done' } elseif ($cur) { 'current step' } else { 'not reached yet' })"
    $r.Grid.ToolTip = $(if ($cur) { 'You are here' } elseif ($done) { 'Done' } else { 'Not yet' })
  }
}
function Get-SideHelp { if ($script:eWf) { "$($script:eWf.Title). $($script:eWf.Help)" } else { 'Pick the folder that holds your work.' } }

# ---- the plan's actions as a Win98 "Setup Options" radio group (label + why-not description), recommended one pre-selected
function Render-Acts($panel, [string]$key) {
  $w = $script:eWf; $acts = @($w.Actions)
  $sig = "$($w.State)|$($w.Recommended)|" + (($acts | ForEach-Object { "$($_.Id):$($_.Enabled):$($_.Why)" }) -join ';')
  if ($script:actKey[$key] -ne $sig) {
    $script:actKey[$key] = $sig; $panel.Children.Clear(); $script:eSelAct[$key] = $null
    foreach ($a in $acts) {
      $rb = New-Object Windows.Controls.RadioButton; $rb.GroupName = "acts$key"; $rb.Tag = $a.Id; $rb.IsEnabled = [bool]$a.Enabled; $rb.Margin = '0,0,0,6'
      $sp = New-Object Windows.Controls.StackPanel; $sp.Children.Add((New-TbI ($a.Label + $(if ($a.Id -eq $w.Recommended -and $a.Enabled) { '  (recommended)' })) 'Bold')) | Out-Null
      $d = $(if (-not $a.Enabled) { "$($a.Why)" } elseif ($a.Kind -eq 'nav') { '' } else { '' }); if ($d) { $dt = New-TbI $d; $dt.TextWrapping = 'Wrap'; $dt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Hint'); $sp.Children.Add($dt) | Out-Null }
      $rb.Content = $sp; Acc $rb "$($a.Label)$(if (-not $a.Enabled) { ' - not available: ' + $a.Why })"; Tip $rb $(if (-not $a.Enabled) { "$($a.Why)" } else { $a.Label })
      $rb.Add_Click({ $script:eSelAct[$script:CurActKey] = [string]$this.Tag; Update-EUi })
      [void]$panel.Children.Add($rb)
    }
  }
  $script:CurActKey = $key
  $want = $script:eSelAct[$key]; $ids = @($acts | Where-Object { $_.Enabled } | ForEach-Object { $_.Id })
  if (-not $want -or $want -notin $ids) { $want = $(if ($w.RecommendedEnabled) { $w.Recommended } elseif ($ids.Count) { $ids[0] } else { '' }) }
  foreach ($rb in $panel.Children) { $rb.IsChecked = ([string]$rb.Tag -eq $want) }
  $script:eSelAct[$key] = $want
}
function Get-NextActId {
  $w = $script:eWf; if (-not $w) { return $null }
  $pg = $script:wizPage
  if ($w.State -eq 'NotAProject' -and $pg -eq 1) { return $(if ($rbOther.IsChecked) { 'ChooseFolder' } else { 'InitProject' }) }
  if ($pg -in 1, 4, 5 -and $script:eSelAct["p$pg"]) { return $script:eSelAct["p$pg"] }
  $w.Recommended
}
function Update-WfPanels {
  $w = $script:eWf; $pg = $script:wizPage
  if (-not $w) { return }
  $st = $w.State; $f = $w.Facts
  # page 1: states that are not the folder box / the "turn into a project" choice show Title/Help and their actions
  $pState.Visibility = Vis ($pg -eq 1 -and $st -in 'GitMissing', 'FolderNotFound', 'Untrusted', 'Blocked', 'Detached', 'EmptyProject')
  if ($pState.Visibility -eq 'Visible') { $stateHelp.Text = "$($w.Title). $($w.Help)"; Render-Acts $spActs1 'p1' }
  if ($pg -eq 1) { $p1Intro.Text = $(if ($st -eq 'NoFolder') { $w.Help } else { $w.Title }) }
  if ($pg -eq 4) {
    $p4Title.Text = $w.Title; $p4Intro.Text = $w.Help + $(if ((Get-Dest) -and $st -in 'ReadyToPublish', 'NeedsReplace', 'NeedsSignIn', 'ChooseAccount') { "  Destination: $(Get-Dest)." }); Render-Acts $spActs4 'p4'
    $needUrl = [bool](@($w.Actions | Where-Object { $_.Id -in 'ConnectRemote', 'ChangeAddress' }).Count)
    $probFix.Visibility = Vis $needUrl; if ($needUrl) { $pubProb.Visibility = 'Visible'; if (-not $probText.Text) { $probText.Text = $w.Help } }
    $gAcct.Visibility = Vis ($st -in 'ChooseAccount', 'NoWriteAccess' -and $script:eAccess -and @($script:eAccess.Accounts).Count)
    $btnSign.Visibility = Vis ([bool](Get-WfAct 'SignIn'))
    if ($st -eq 'SSORequired') { $pubProb.Visibility = 'Visible'; $probFix.Visibility = 'Collapsed'; $probText.Text = $w.Help; $btnProbLink.Visibility = 'Visible'; Set-Mn $btnProbLink 'Open GitHub SSO help'; $btnProbLink.Tag = 'https://docs.github.com/en/authentication/authenticating-with-saml-single-sign-on' }
  }
  if ($pg -eq 5) { $finTitle.Text = $w.Title; Render-Acts $spActs5 'p5' }
}
function Update-NavButtons($next, [string]$mode) {
  $pg = $script:wizPage; $w = $script:eWf; $id = Get-NextActId; $a = $(if ($id) { Get-WfAct $id } else { $null })
  $lbl = '&Next >'; $en = [bool]($a -and $a.Enabled); $tip = $(if ($a) { if ($a.Enabled) { $a.Label } else { "$($a.Why)" } } else { 'Nothing to do here.' })
  switch ($id) {
    'Commit' { $lbl = $(if ($next.HasRemote) { '&Publish >' } else { '&Save >' }); if ($en) { $tip = $(if ($next.HasRemote) { 'Save your files as a commit and send it to GitHub (you see each step).' } else { 'Save your files as a commit on this computer.' }) } }
    'ApplyEdits' { $lbl = 'A&pply >'; if ($en) { $tip = 'Write your waiting edits into the project (a backup is kept for Undo), then continue.' } }
    { $_ -in 'Publish', 'ReplaceRemote' } { $lbl = '&Publish >' }
  }
  if ($pg -eq 5 -and $id -notin 'EditOlder', 'ChooseFolder', 'Undo') { $lbl = '&Finish'; $en = $true; $tip = 'Close backd8.' }
  if ($pg -eq 5 -and $id) { $lbl = '&Next >' }
  if ($script:ePlanRunning -and $script:eLastFail) { $lbl = 'Retr&y'; $en = $true }
  if ($script:eBusy -or $script:ePlanRunning) { $en = $false }
  $k = "$lbl|$en"; if ($k -ne $script:navKey) { Set-Mn $btnNext $lbl; $script:navKey = $k }
  $btnNext.IsEnabled = $en; Tip $btnNext $tip
  $back = [bool]($script:eSub -or ($w -and $pg -ne 1 -and (Get-WfAct 'ChooseFolder'))) -and -not ($script:eBusy -or $script:ePlanRunning)
  $btnBack.IsEnabled = $back; Tip $btnBack $(if ($script:eSub) { 'Back to the previous page.' } elseif ($back) { 'Choose another folder.' } else { 'This is the first step.' })
  $script:ePrimaryBtn = $(if ($en) { $btnNext } else { $null })
}
#endregion

#region running actions through the model
function Invoke-Wf([string]$Id, [hashtable]$P = @{}, [string]$Label = 'Working...', [bool]$Cancellable = $false) {
  if ($script:eWfBusy) { return $null }                 # double-clicks are ignored while an action is running
  $script:eWfBusy = $true
  try {
    $ui = @{ EditsStaged = [int]$script:eEdits.Count }; $hook = $script:SignInHook
    $r = Invoke-Bg $Label { param($path, $id, $p, $ui, $hook) if ($hook) { Invoke-WorkflowAction $path $id $p $ui $hook } else { Invoke-WorkflowAction $path $id $p $ui } } @($script:eFolder, $Id, $P, $ui, $hook) $Cancellable
    if ($r -and $r.Plan) { $script:eWf = $r.Plan }
    $r
  } finally { $script:eWfBusy = $false }
}
# one place that turns a model result into the UI contract: stale = one-line notice, guard = inline message, error = plain headline + Details
function Handle-WfResult($r, [string]$what) {
  if (-not $r) { return $false }
  if ($r.Ok) { return $true }
  Add-ELog "$what refused ($($r.Reason)$(if ($r.ErrorClass) { "/$($r.ErrorClass)" })): $($r.Message)"
  switch ($r.Reason) {
    'stale' { if ($script:Confirm) { Show-Result 'info' 'The project changed meanwhile' $r.Message @() $true }; return $false }
    { $_ -in 'guard', 'prerequisite' } { if (-not $script:Confirm) { if ($what -like '*push*' -or $what -like '*replace*') { return $false }; throw $r.Message }; Show-Result 'warn' 'Not yet' $r.Message @() $true; return $false }
  }
  if ($r.ErrorClass) { Fail $r.Message }
  $false
}
function Do-WfAct([string]$id) {
  if ($script:eBusy -or $script:ePlanRunning) { return }
  try {
    switch ($id) {
      'ChooseFolder' { Do-EBrowse }
      'Recheck' { if ($script:eRepo) { Do-ELoad $script:eRepo -Fetch } elseif ($script:eFolder) { Open-Folder $script:eFolder } else { Refresh-Wf } }
      'DiscardEdits' { $script:eEdits = @{}; $script:eDrafts = @{}; Fill-EList; Show-WfState }
      'EditOlder' { $script:eSub = 'edit'; Show-WfState }
      'OpenNewRepoPage' { Open-Url 'https://github.com/new' }
      'ShowGitInstall' { $bGitHelp.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
      'ShowFinishOperation' { if ($script:Confirm) { [void](Ask 'backd8 Setup' 'Finish or abort the unfinished git operation' "A merge, rebase or cherry-pick is half done in this folder.`n`nOpen a terminal in the folder and run one of:`n  git merge --abort`n  git rebase --abort`n  git cherry-pick --abort`n`nThen press Check again." @('OK') 0 'info') } }
      'ShowSwitchBranch' { if ($script:Confirm) { [void](Ask 'backd8 Setup' 'Switch to a branch' "Open a terminal in the project folder and run:`n  git switch main`n(use your branch name), then press Check again." @('OK') 0 'info') } }
      'ShowSsoHelp' { Open-Url 'https://docs.github.com/en/authentication/authenticating-with-saml-single-sign-on' }
      'ShowHostKeyHelp' { if ($script:Confirm) { [void](Ask 'backd8 Setup' 'Verify the SSH host key' "Run once in a terminal:`n  ssh -T git@github.com`nCheck the fingerprint against GitHub's published list, answer yes, then press Check again. Or change the address to https." @('OK') 0 'info') } }
      'InitProject' { Do-EInit }
      'Trust' { $script:eFolder = $script:eFolder; Show-Untrusted $script:eFolder '' }
      'SaveIdentity' { Do-SaveIdentity }
      { $_ -in 'Commit', 'ApplyEdits' } { Run-Plan }
      'AddGitignore' { Do-EAddIgnore }
      { $_ -in 'ConnectRemote' } { Do-EConnect }
      'ChangeAddress' { Do-EFixAddress }
      'Sync' { [void](Do-EGetLatest) }
      'SignIn' { [void](Do-ESignIn) }
      'ChooseAccount' { Do-EUseAccount }
      'Undo' { Do-EUndo }
      { $_ -in 'Publish', 'ReplaceRemote' } { Run-Plan }
    }
  } catch { Add-ELog "ERROR: $($_.Exception.Message)"; if ($script:Confirm) { Show-Result 'danger' 'Something went wrong' 'Press Check again to look at the project again.' @(@{ Text = '&Check again'; Tip = 'Look at the project again.'; Click = { Do-WfAct 'Recheck' } }) $true } else { throw } }
}
function Do-Next { if ($script:eBusy -or $script:ePlanRunning) { return }; $id = Get-NextActId; if ($script:wizPage -eq 5 -and (-not $id -or $id -notin 'EditOlder', 'ChooseFolder', 'Undo')) { $f.Close(); return }; if ($id) { Do-WfAct $id } }
function Do-Back { if ($script:eBusy -or $script:ePlanRunning) { return }; if ($script:eSub) { $script:eSub = ''; Show-WfState } elseif ($script:eWf -and (Get-WfAct 'ChooseFolder')) { Do-WfAct 'ChooseFolder' } }
function Nav-To([int]$n) { Go-Page $n }
#endregion




function Get-EPlan {
  $w = $script:eWf; if (-not $w) { return @() }
  $f = $w.Facts; $st = $w.State; $steps = @()
  $typed = [bool](Get-EDirty) -and -not (Get-EValidation) -and -not ($script:eSel -and $script:eEdits.ContainsKey($script:eSel))
  $nEd = [int]$script:eEdits.Count + [int]$typed
  $commit = [bool]($st -eq 'ChangesPending' -and (Get-WfAct 'Commit').Enabled)
  if ($commit) { $steps += @{ Id = 'commit'; Text = "Save $(Format-Plural (Get-ECheckedFiles).Count 'file') as a commit"; State = 'todo' } }
  if ($nEd -and $st -in 'EditsPending', 'ChangesPending') { $steps += @{ Id = 'apply'; Text = "Apply $(Format-Plural $nEd 'edit') to older commits (a backup is kept)"; State = 'todo' } }
  if ($f.Linked) {
    $needGet = [bool]($f.Behind -gt 0 -and ($f.Ahead -eq 0 -or $f.Others -gt 0 -or $f.RemoteOnly -gt 0))
    if ($needGet) { $steps += @{ Id = 'getlatest'; Text = "Get GitHub's newer changes and combine them with yours"; State = 'todo' } }
    if ($f.Access -eq 'NotSignedIn') { $steps += @{ Id = 'signin'; Text = 'Sign in to GitHub (a sign-in window opens)'; State = 'todo' } }
    $onGhEdit = [bool]($nEd -and $script:eOnGh -and (@($script:eEdits.Keys | Where-Object { $script:eOnGh.Contains($_) }).Count))
    $unpub = [bool]($commit -or $nEd -or $f.Ahead -gt 0)
    $repl = [bool]($onGhEdit -or ($f.Behind -gt 0 -and $f.Ahead -gt 0 -and $f.Others -eq 0 -and $f.RemoteOnly -eq 0))
    if ($unpub -or $st -in 'NeedsReplace', 'ReadyToPublish') { $steps += @{ Id = 'publish'; Text = $(if ($repl) { "Replace GitHub's old version with yours (you are asked to confirm)" } else { 'Send your commits to GitHub' }); State = 'todo'; Replace = $repl } }
  }
  $steps
}


#region Advanced: the optional global auto-backdate hook (old model) - NOT part of the main flow. A classic dialog.
$script:AdvBody = @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="advRoot">
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <Border Margin="0,0,0,8">$(BvOpen 'BvEtchO' 'BvEtchI')<StackPanel Orientation="Horizontal" Margin="6,5"><ContentControl x:Name="aWarnIcon" Margin="0,0,8,0" VerticalAlignment="Top" IsTabStop="False"/>
  <StackPanel MaxWidth="580"><TextBlock Text="Optional extra - you do NOT need this to edit commits or publish" FontWeight="Bold" TextWrapping="Wrap"/>
   <TextBlock Text="Auto-backdating gives EVERY new commit you make on this PC (in any program, in any project) a made-up date while it is ON, starting at a date you choose and moving 1 to 6 hours forward per commit. Leave it off unless you really want that." TextWrapping="Wrap" Margin="0,3,0,0"/></StackPanel></StackPanel>$($script:BvClose)</Border>
 <GroupBox Grid.Row="1" Header="Status" Margin="0,0,0,6"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <TextBlock x:Name="aStatus" FontWeight="Bold" VerticalAlignment="Center" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
  <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="aInstall" Margin="0,0,6,0"/><Button x:Name="aToggle"/></StackPanel></Grid></GroupBox>
 <GroupBox Grid.Row="2" Header="First date for new commits in projects that are not listed below" Margin="0,0,0,6"><StackPanel Orientation="Horizontal"><StackPanel x:Name="aDefHost" Margin="0,0,8,0"/><Button x:Name="aSave" VerticalAlignment="Top" Margin="0,0,8,0"/><TextBlock x:Name="aSaved" VerticalAlignment="Center" TextWrapping="Wrap"/></StackPanel></GroupBox>
 <GroupBox Grid.Row="3" Header="Projects with their own date (each has its own clock)" Margin="0,0,0,6"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
  <StackPanel Orientation="Horizontal" Margin="0,0,0,6"><Button x:Name="aAdd" Margin="0,0,6,0"/><Button x:Name="aUpd" Margin="0,0,6,0"/><Button x:Name="aRem"/></StackPanel>
  <Grid Grid.Row="1"><ListBox x:Name="aList" ScrollViewer.HorizontalScrollBarVisibility="Disabled" MinHeight="90"/><TextBlock x:Name="aEmpty" Text="No project has its own date. Every project uses the date above." HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" IsHitTestVisible="False"/></Grid></Grid></GroupBox>
 <Grid Grid.Row="4"><Button x:Name="aReset" HorizontalAlignment="Left"/><Button x:Name="aClose" HorizontalAlignment="Right" IsCancel="True"/></Grid>
</Grid>
"@
$script:AdvCw = New-ClassicWindow 'backd8 Setup - Advanced: auto-backdate new commits' 700
$af = $script:AdvCw.Window; $af.SizeToContent = 'Manual'; $af.Height = 580; $af.Width = 700
$script:AdvGrid = [Windows.Markup.XamlReader]::Parse($script:AdvBody); $script:AdvCw.Body.Child = $script:AdvGrid
foreach ($m in [regex]::Matches($script:AdvBody, 'x:Name="(\w+)"')) { $n = $m.Groups[1].Value; Set-Variable -Name $n -Value ($script:AdvGrid.FindName($n)) -Scope Script }
$aWarnIcon.Content = (New-Icon 'warn' 24)
Set-Mn $aInstall '&Install on this PC'; Set-Mn $aToggle 'Turn &ON'; Set-Mn $aSave 'Save &date'; Set-Mn $aAdd 'Add a &project...'; Set-Mn $aUpd 'Change d&ate...'; Set-Mn $aRem '&Remove'; Set-Mn $aClose '&Close'; Set-Mn $aReset 'Reset &settings...'
Tip $aSave 'Save this as the first date for new commits.'; Tip $aAdd 'Give one project its own start date.'; Tip $aUpd 'Change the start date of the selected project.'; Tip $aRem 'Remove the selected project from this list (its commits are not changed).'; Tip $aClose 'Close this window.'; Tip $aReset "Move backd8's settings file aside and start fresh. Your projects and commits are not touched."
Acc $aList 'Projects with their own date'; Tip $aList 'Projects that have their own start date for auto-backdating.'
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
  try {
    if (Test-Path -LiteralPath $x -PathType Container) {
      $parts = $x.Split('\'); $cur = $parts[0].ToUpper() + '\'
      for ($i = 1; $i -lt $parts.Count; $i++) { if (-not $parts[$i]) { continue }; $m = @([IO.Directory]::GetFileSystemEntries($cur, $parts[$i])); if ($m.Count) { $cur = Join-Path $cur (Split-Path $m[0] -Leaf) } else { $cur = Join-Path $cur $parts[$i] } }
      return $cur
    }
  } catch {}
  $x
}
function Refresh-Adv {
  $G = $script:G
  try { $s = Get-Status; $c = $s.Config } catch { $aStatus.Text = "Settings problem: $($_.Exception.Message)"; $bInstall.IsEnabled = $false; $bToggle.IsEnabled = $false; $lv.Items.Clear(); $aReset.Visibility = 'Visible'; return }
  $aReset.Visibility = 'Visible'; $bInstall.IsEnabled = $true; $script:mOn = $s.Enabled
  $hasDate = [bool]($c.default.start -or (@($c.repos) | Where-Object { $_.start }))
  $aStatus.Text = if ($s.Enabled) { "(!) Auto-backdating is ON" } elseif ($s.Installed) { "Installed, currently OFF" } else { "Not installed" }
  SetRes $aStatus ([Windows.Controls.TextBlock]::ForegroundProperty) $(if ($s.Enabled) { 'ErrFg' } else { 'Text' })
  Set-Mn $bInstall $(if ($s.Installed) { '&Uninstall' } else { '&Install on this PC' }); Set-Mn $bToggle $(if ($s.Enabled) { 'Turn &OFF' } else { 'Turn &ON' }); $bToggle.IsEnabled = [bool]($s.Installed -and $hasDate)
  Tip $bToggle $(if (-not $s.Installed) { 'Install first.' } elseif (-not $hasDate) { 'Save a date first.' } elseif ($s.Enabled) { 'Stop re-dating new commits.' } else { 'Start re-dating EVERY new commit on this PC (you confirm first).' })
  $saved = if ($c.default.start) { [datetime]$c.default.start } else { $null }
  if ($saved -and -not $script:pDefInit) { $script:pDefInit = $true; $pDef.Value = if ($saved -gt (Get-Date)) { Get-Date } else { $saved } }
  $dirty = $saved -and ($pDef.Value -ne [datetime]::MinValue) -and ([math]::Abs(($pDef.Value - $saved).TotalMinutes) -ge 1)
  $aSaved.Text = if (-not $saved) { 'Not saved yet.' } elseif ($dirty) { "Saved: $(Fmt $saved) - you changed it, press Save date" } else { "Saved: $(Fmt $saved)" }
  $sel = if ($lv.SelectedItem) { [string]$lv.SelectedItem.Tag } else { $null }
  $ov = if ($s.Installed) { @(Get-OverridesCached) } else { @() }
  $lv.Items.Clear()
  foreach ($r in @($c.repos)) {
    $full = Show-Path $r.path; $leaf = Split-Path $full -Leaf; $par = Split-Path $full -Parent
    $note = ''
    if (-not (Test-Path -LiteralPath $r.path -PathType Container)) { $note = "(!) Folder not found" }
    elseif ($ov -contains (Norm $r.path)) { $note = "(!) Own hooks setting: not backdated" }
    elseif ($r.next -and ([datetime]$r.next) -gt (Get-Date)) { $note = "Caught up with today" }
    $g = New-Object Windows.Controls.Grid
    foreach ($w in @(0, 0)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength(1, 'Star'); $g.ColumnDefinitions.Add($cd) }
    $l = New-Object Windows.Controls.StackPanel; $l.Children.Add((New-TbI $leaf 'Bold')) | Out-Null; $l.Children.Add((New-TbI $par)) | Out-Null
    $rt = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($rt, 1)
    $rt.Children.Add((New-TbI "First date $(Fmt ([datetime]$r.start))  ->  next commit gets $(if ($r.next) { Fmt ([datetime]$r.next) } else { 'the first date' })")) | Out-Null
    if ($note) { $rt.Children.Add((New-TbI $note 'Bold')) | Out-Null }
    $g.Children.Add($l) | Out-Null; $g.Children.Add($rt) | Out-Null
    $it = New-Object Windows.Controls.ListBoxItem; $it.Content = $g; $it.Tag = $r.path; $it.Style = $script:Res['RowItem']; $it.ToolTip = $full; Acc $it "$leaf, $full"
    [void]$lv.Items.Add($it); if ($sel -and (Norm $r.path) -eq (Norm $sel)) { $it.IsSelected = $true }
  }
  $aEmpty.Visibility = Vis ($lv.Items.Count -eq 0); $bUpd.IsEnabled = $bRem.IsEnabled = [bool]$lv.SelectedItem
}
function Refresh { Refresh-Adv; $script:PreCache = $null; try { $script:PreCache = & $script:PreScript $script:eRepo } catch {}; $script:PreAt = Get-Date; Update-EBanners; $f.Title = $(if ($script:mOn) { 'backd8 Setup - auto-backdating is ON for this PC' } else { 'backd8 Setup' }) }

function Get-DateFromUser([string]$title, [string]$prompt, [datetime]$initial) {
  if (-not $script:Confirm -and -not $script:AskCapture) { return $initial }
  $cw = New-ClassicWindow $title 460; $w = $cw.Window
  $sp = New-Object Windows.Controls.StackPanel
  $sp.Children.Add((New-Tb $prompt 11 'Text' 'Bold')) | Out-Null
  $dt = New-Dt $initial; $dt.Panel.Margin = '0,10,0,0'; $sp.Children.Add($dt.Panel) | Out-Null
  $pr = New-Tb '' 11 'ErrFg' 'Bold'; $pr.Margin = '0,4,0,0'; $sp.Children.Add($pr) | Out-Null
  $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.HorizontalAlignment = 'Right'; $r.Margin = '0,14,0,0'
  $ok = New-Button '&Save date' 'normal' 90; $ca = New-Button 'Cancel' 'normal' 75; $ca.Margin = '6,0,0,0'; $ca.IsCancel = $true; $ok.IsDefault = $true
  $script:dtResult = $null; $script:dtField = $dt; $script:dtWin = $w; $script:dtPr = $pr
  $ok.Add_Click({ $p = $script:dtField.Problem; if ($p) { $script:dtPr.Text = $p } else { $script:dtResult = $script:dtField.Value; $script:dtWin.DialogResult = $true } })
  $cw.Close.Add_Click({ $script:dtWin.DialogResult = $false })
  $r.Children.Add($ok) | Out-Null; $r.Children.Add($ca) | Out-Null; $sp.Children.Add($r) | Out-Null; $cw.Body.Child = $sp
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
          $r = Ask 'backd8 Setup - install' 'Another git hooks folder is already set up' ("Git on this PC already runs hooks from:`n$cur`n`nIf backd8 replaces it, those hooks stop running in EVERY project.`n`nbackd8 cannot put the old folder back for you. To restore it later, run:`ngit config --global core.hooksPath `"$cur`"") @('Replace it', 'Keep it, do nothing') 1 'warn' $cur
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
        $body = "From now on, EVERY commit you make on this PC - in any project, with any program (git, VS Code, GitHub Desktop...) - is given a made-up date:`n`n  - first commit: $first, then +1 to 6 hours for each next commit`n  - $(Format-Plural $own 'project has' 'projects have') their own start date`n`nCommits you already made are not changed. You can turn it OFF here at any time. (This does not affect the main backd8 window.)"
        if ((Ask 'backd8 Setup - turn ON' 'Turn auto-backdating ON for the whole PC?' $body @('Turn ON', 'Cancel') 1 'warn') -ne 0) { return }
      }
    }
    Set-Enabled $on
  } catch { Fail $_ }; Refresh
}
function Do-Default { try { $p = $pDef.Problem; if ($p) { throw $p }; Set-StartDate '*' $pDef.Value } catch { Fail $_ }; Refresh }
function Do-Add([string]$path) {
  try {
    if (-not $path) { $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose the project folder'; if ($d.ShowDialog() -ne 'OK') { return }; $path = $d.SelectedPath }
    $root = Get-RepoRoot $path
    $init = if ((Get-Config).default.start) { [datetime](Get-Config).default.start } else { $pDef.Value }
    $when = Get-DateFromUser 'backd8 Setup - start date' "First date for new commits in '$(Split-Path $root -Leaf)'" $init
    if ($null -eq $when) { return }
    Set-StartDate $root $when
  } catch { Fail $_ }; Refresh
}
function Sel([string]$p) { if ($p) { $p } elseif ($lv.SelectedItem) { [string]$lv.SelectedItem.Tag } }
function Do-Update([string]$path) {
  $p = Sel $path; if (-not $p) { return }
  try {
    $cur = (Get-Config).repos | Where-Object { (Norm $_.path) -eq (Norm $p) } | Select-Object -First 1
    $when = Get-DateFromUser 'backd8 Setup - start date' "New first date for '$(Split-Path (Show-Path $p) -Leaf)'" $(if ($cur) { [datetime]$cur.start } else { $pDef.Value })
    if ($null -eq $when) { return }
    Set-StartDate $p $when
  } catch { Fail $_ }; Refresh
}
function Do-Remove([string]$path) {
  $p = Sel $path; if (-not $p) { return }
  try {
    if ($script:Confirm) {
      $nm = Split-Path (Show-Path $p) -Leaf
      if ((Ask 'backd8 Setup - remove' "Remove '$nm' from this list?" "Its commits are not changed. New commits there will use the date above instead.`n`n$(Show-Path $p)" @('Remove from list', 'Cancel') 1 'question') -ne 0) { return }
    }
    Remove-Repo $p
  } catch { Fail $_ }; Refresh
}
function Do-ResetSettings {
  try {
    if ($script:Confirm -and (Ask 'backd8 Setup - reset settings' 'Reset backd8 settings?' "The settings file is moved aside (not deleted) and backd8 starts fresh. Your projects and commits are not touched. Auto-backdating start dates are forgotten." @('Reset settings', 'Cancel') 1 'warn') -ne 0) { return }
    $m = Reset-Config; Add-ELog "$m"; $script:pDefInit = $false
    if ($script:Confirm) { Show-Toast 'Settings reset' 'ok' 'backd8 now uses fresh settings.' }
  } catch { Fail $_ }; Refresh
}
function Do-HookRemove {
  try {
    if ($script:Confirm -and (Ask 'backd8 Setup - remove auto-backdating' 'Remove auto-backdating from this PC?' "It stops changing the dates of new commits you make in other programs. Commits you already made are not changed. You can install it again from Advanced." @('Remove it', 'Cancel') 1 'question') -ne 0) { return }
    [void](Uninstall-Hooks); Add-ELog 'Removed auto-backdating from git.'; if ($script:Confirm) { Show-Toast 'Auto-backdating removed' 'ok' }
  } catch { Fail $_ }; Refresh
}
$bInstall.Add_Click({ Do-Install }); $bToggle.Add_Click({ Do-Toggle }); $bDef.Add_Click({ Do-Default })
$bAdd.Add_Click({ Do-Add }); $bUpd.Add_Click({ Do-Update }); $bRem.Add_Click({ Do-Remove }); $aReset.Add_Click({ Do-ResetSettings })
$lv.Add_SelectionChanged({ $bUpd.IsEnabled = $bRem.IsEnabled = [bool]$lv.SelectedItem })
$lv.Add_MouseDoubleClick({ Do-Update })
$lv.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Delete') { Do-Remove } elseif ($e.Key -eq 'Return') { Do-Update } })
$pDef.Date.Add_TextChanged({ if ($script:pDefInit) { Refresh-Adv } }); $pDef.Time.Add_TextChanged({ if ($script:pDefInit) { Refresh-Adv } })
function Show-Advanced { try { Refresh; $af.Owner = $f; $script:ActiveOwner = $af; [void]$af.ShowDialog() } catch { Fail $_ } finally { $script:ActiveOwner = $f; Update-EBanners } }
$af.Add_Closing({ param($s, $e) $e.Cancel = $true; $s.Hide(); $script:ActiveOwner = $f })
#endregion

#region events, keyboard, startup
function New-AppIcon {
  $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
  $dc.DrawRectangle((New-Object Windows.Media.SolidColorBrush((Hex '#000080'))), $null, (New-Object Windows.Rect(0, 0, 64, 64)))
  $dc.DrawRectangle((New-Object Windows.Media.SolidColorBrush((Hex '#C0C0C0'))), $null, (New-Object Windows.Rect(4, 4, 56, 56)))
  $ft = New-Object Windows.Media.FormattedText('b8', [Globalization.CultureInfo]::InvariantCulture, 'LeftToRight', (New-Object Windows.Media.Typeface('Arial')), 30, [Windows.Media.Brushes]::Black)
  $dc.DrawText($ft, (New-Object Windows.Point((64 - $ft.Width) / 2, (64 - $ft.Height) / 2))); $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap(64, 64, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($dv); $rtb.Freeze(); $rtb
}
try { $f.Icon = New-AppIcon; $af.Icon = $f.Icon } catch { }
function Show-Help {
  $body = "backd8 is a short wizard. Most of the time you only press Next.`n`n1. Choose your project: Browse, paste the folder path, double-click a recent project, or drop a folder on this window. The last project opens by itself.`n`n2. What would you like to do? The recommended choice is already selected: save your changes and put them on GitHub, change an older commit, spread commits over time, get the latest from GitHub, or undo.`n`n3. The details: for new work, write a message (backd8 suggests one) and choose a date. A commit is one saved version of your project.`n`n4. Publish: numbered steps tick off as they run. Nothing is sent to GitHub until you press Publish. If GitHub has newer changes you get them first; replacing GitHub's version always asks you twice.`n`nEvery edit keeps a backup (Undo last edit, Ctrl+Z).`n`nKeys: Enter or Ctrl+Enter = Next, Esc = Cancel (also stops a running step), F1 = this help, F5 = reload, Ctrl+F = search commits, Ctrl+Z = undo, Alt + underlined letter = press that button."
  [void](Ask 'backd8 Setup - how it works' 'How backd8 works' $body @('Close') 0 'info')
}
$btnBrowse.Add_Click({ Do-EBrowse })
$btnBack.Add_Click({ Do-Back }); $btnNext.Add_Click({ Do-Next }); $btnCancel.Add_Click({ $f.Close() })
$rbInit.Add_Click({ Update-EUi }); $rbOther.Add_Click({ Update-EUi }); $rbKeep.Add_Click({ Update-EUi }); $rbReplace.Add_Click({ Update-EUi })
$bInitNew.Add_Click({ Open-Url 'https://github.com/new' }); $bNewRepo.Add_Click({ Open-Url 'https://github.com/new' }); $bLink.Add_Click({ Do-EConnect })
$btnGetLatest.Add_Click({ if (-not $script:eBusy) { [void](Do-EGetLatest) } }); $btnOpenGh.Add_Click({ if ($btnOpenGh.Tag) { Open-Url ([string]$btnOpenGh.Tag) } })
$bGitHelp.Add_Click({ if ($script:Confirm) { if ((Ask 'backd8 Setup - install Git' 'Install Git for Windows' "Git is the free tool that stores your project history. Install it once:`n`n- Easiest: open a terminal and run:  winget install --id Git.Git -e`n- Or download the installer from git-scm.com/download/win`n`nThen close and reopen backd8." @('Open the download page', 'Close') 1 'info') -eq 0) { Open-Url 'https://git-scm.com/download/win' } } })
$bSaveId.Add_Click({ Do-SaveIdentity }); $bHookRemove.Add_Click({ Do-HookRemove }); $bCfgReset.Add_Click({ Do-ResetSettings })
$bHookKeep.Add_Click({ if ($script:PreCache -and $script:PreCache.Hook -and $script:PreCache.Hook.Enabled) { $script:hookOnKeep = $true } else { $script:hookKeepSession = $true; Set-UiValue 'hookNoticeDismissed' $true }; Update-EBanners })
$btnAdv.Add_Click({ if (-not $script:eBusy) { Show-Advanced } }); $btnHelp.Add_Click({ Show-Help })
$lbRecent.Add_MouseDoubleClick({ if ($lbRecent.SelectedItem -and -not $script:eBusy) { $p = [string]$lbRecent.SelectedItem.Tag; $tbPath.Text = $p; Open-Folder $p } })
$lbRecent.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return' -and $lbRecent.SelectedItem -and -not $script:eBusy) { $p = [string]$lbRecent.SelectedItem.Tag; $tbPath.Text = $p; Open-Folder $p; $e.Handled = $true } })
$lbHist.Add_SelectionChanged({ if (-not $script:eFilling) { Do-ESelect } })
$lbHist.Add_MouseDoubleClick({ if ($script:eView -eq 'commit') { [void]$eMsg.Focus() } elseif ($script:eView -eq 'new') { [void]$nMsg.Focus() } })
function Set-Sort([string]$col) { if ($script:eSort -and $script:eSort.Col -eq $col) { if ($script:eSort.Desc) { $script:eSort = @{ Col = $col; Desc = $false } } else { $script:eSort = $null } } else { $script:eSort = @{ Col = $col; Desc = $true } }; Fill-EList }
$hSortDate.Add_Click({ Set-Sort 'date' }); $hSortMsg.Add_Click({ Set-Sort 'msg' }); $hSortId.Add_Click({ Set-Sort 'id' }); $hSortMark.Add_Click({ Set-Sort 'mark' })
function Set-Filter([string]$k) { if ($script:eFilling) { return }; $script:eFilter = $k; Fill-EList }
$tgAll.Add_Click({ Set-Filter 'all' }); $tgLocal.Add_Click({ Set-Filter 'local' }); $tgEdited.Add_Click({ Set-Filter 'edited' })
function Copy-ESelected([bool]$withTitle) {
  $lines = foreach ($it in $lbHist.SelectedItems) { $c = Find-ECommit ([string]$it.Tag); if ($c) { if ($withTitle) { "$($c.Sha) $($c.Subject)" } else { $c.Sha } } }
  if ($lines) { try { [Windows.Clipboard]::SetText(($lines -join "`r`n")); Add-ELog "Copied $(Format-Plural @($lines).Count 'commit ID' 'commit IDs') to the clipboard."; Show-Toast 'Copied to the clipboard' 'info' } catch { } }
}
$cm = New-Object Windows.Controls.ContextMenu
foreach ($spec in @(@('Copy commit ID', { Copy-ESelected $false }), @('Copy ID and message', { Copy-ESelected $true }), @('Discard my change to this commit', { Do-EDiscard }))) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $spec[0]; $mi.Add_Click($spec[1]); [void]$cm.Items.Add($mi) }
$lbHist.ContextMenu = $cm
$nAll.Add_Click({ foreach ($i in $script:FileRows) { if ($i.Box.IsEnabled) { $i.Box.IsChecked = $true; $script:eChecks[$i.Path] = $true } }; Update-EUi })
$nNone.Add_Click({ foreach ($i in $script:FileRows) { $i.Box.IsChecked = $false; $script:eChecks[$i.Path] = $false }; Update-EUi })
$nMsg.Add_TextChanged({ Update-EUi })
foreach ($k in $script:WhenRbs.Keys) { $script:WhenRbs[$k].Add_Click({ if (-not $script:eFilling) { Set-NewWhen ([string]$this.Tag) } }) }
$nPick.Date.Add_TextChanged({ Update-EUi }); $nPick.Time.Add_TextChanged({ Update-EUi })
$btnFiles.Add_Click({ $pFiles.Visibility = Vis ($pFiles.Visibility -ne 'Visible'); Update-EUi })
$btnRetry.Add_Click({ if (-not $script:eBusy) { Run-Plan } }); $btnFailDetails.Add_Click({ $failRaw.Visibility = Vis ($failRaw.Visibility -ne 'Visible'); Update-EUi })
$btnAnother.Add_Click({ Do-Another }); $btnUseAcct.Add_Click({ if (-not $script:eBusy) { Do-EUseAccount } }); $btnFixAddr.Add_Click({ if (-not $script:eBusy) { Do-EFixAddress } })
$btnProbLink.Add_Click({ if ($btnProbLink.Tag) { Open-Url ([string]$btnProbLink.Tag) } })
$nBtn.Add_Click({ [void](Do-ENewCommit) })
$eMsg.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } })
$ePick.Date.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } }); $ePick.Time.Add_TextChanged({ if (-not $script:eLoading -and $script:eSel) { Update-EUi } })
$eSave.Add_Click({ Do-EStage }); $eDisc.Add_Click({ Do-EDiscard }); $eMsgReset.Add_Click({ Do-EResetMsg }); $eDateReset.Add_Click({ Do-EResetDate })
$mPick.Date.Add_TextChanged({ Update-EMulti }); $mPick.Time.Add_TextChanged({ Update-EMulti }); $mBtn.Add_Click({ Do-ESpread })
$tbFind.Add_TextChanged({ if ($script:eRepo) { Fill-EList } })
$btnSign.Add_Click({ [void](Do-ESignIn) }); $btnCheck.Add_Click({ if (-not $script:eBusy) { Update-EAccess } })
$lnkUndo.Add_Click({ if ($lnkUndo.IsEnabled -and -not $script:eBusy) { Do-EUndo } })
$lnkDetails.Add_Click({ $show = ($logCard.Visibility -ne 'Visible'); $logCard.Visibility = Vis $show; Set-Mn $lnkDetails $(if ($show) { 'Hide activity &log' } else { 'Show activity &log' }) })
$f.Add_PreviewKeyDown({ param($s, $e)
  if ($script:eBusy) { if ($e.Key -eq 'Escape') { $script:BgCancel = $true; $btnCancelBusy.IsEnabled = $false; $btnCancelRun.IsEnabled = $false; $e.Handled = $true }; return }
  $ac = [Windows.Input.Keyboard]::FocusedElement; $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
  $isText = ($ac -is [Windows.Controls.TextBox])
  if ($e.Key -eq 'F5') { if ($script:eRepo) { Do-ELoad $script:eRepo -Fetch } elseif ($script:ePlain) { Open-Folder $script:ePlain }; $e.Handled = $true }
  elseif ($e.Key -eq 'F1') { Show-Help; $e.Handled = $true }
  elseif ($ctrl -and $e.Key -eq 'F') { if ($tbFind.IsEnabled -and $script:wizPage -eq 3 -and $script:eAction -in 'edit', 'spread') { [void]$tbFind.Focus(); $tbFind.SelectAll() }; $e.Handled = $true }
  elseif ($ctrl -and $e.Key -eq 'Z' -and -not $isText) { if ($lnkUndo.IsEnabled) { Do-EUndo }; $e.Handled = $true }
  elseif ($e.Key -eq 'Escape') { if ($ac -eq $tbFind -and $tbFind.Text) { $tbFind.Clear(); $e.Handled = $true } }
  elseif ($e.Key -eq 'Return') {
    if ($ctrl) { if ($btnNext.IsEnabled) { Do-Next }; $e.Handled = $true; return }
    if ($ac -eq $tbPath) { Open-Folder $tbPath.Text; $e.Handled = $true }
    elseif ($ac -eq $tbInit) { Do-EInit; $e.Handled = $true }
    elseif ($ac -eq $tbLink) { Do-EConnect; $e.Handled = $true }
    elseif ($ac -eq $tbFix) { Do-EFixAddress; $e.Handled = $true }
    elseif ($ac -eq $tbName -or $ac -eq $tbMail) { Do-SaveIdentity; $e.Handled = $true }
    elseif ($ac -is [Windows.Controls.ListBoxItem] -and $ac.Parent -eq $lbRecent) { }
    elseif ($ac -is [Windows.Controls.ListBoxItem]) { if ($script:eView -eq 'commit') { [void]$eMsg.Focus() }; $e.Handled = $true }
  }
})
$f.Add_DragEnter({ param($s, $e) if (-not $script:eBusy -and $e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e.Effects = 'Copy' } else { $e.Effects = 'None' }; $e.Handled = $true })
$f.Add_Drop({ param($s, $e) if ($script:eBusy) { $e.Handled = $true; return }; foreach ($p in @($e.Data.GetData([Windows.DataFormats]::FileDrop))) { $d = if (Test-Path -LiteralPath $p -PathType Container) { $p } else { Split-Path $p -Parent }; if ($d) { $tbPath.Text = $d; Open-Folder $d; break } } })
$f.Add_Activated({ if (-not $script:eBusy -and $script:Confirm) { Start-PreAsync } })
$f.Add_Closing({
  param($sender, $ev)
  if ($script:eBusy) { $ev.Cancel = $true; return }
  if ($script:Confirm) {
    if (Get-EDirty) { try { [void](Sync-EEdit) } catch { } }
    $pend = Get-EPendingNote
    if ($pend -and (Ask 'backd8 Setup - close' 'Close and lose unsaved work?' "You have $pend that $(if ($pend -match '^1 ') { 'is' } else { 'are' }) not saved into git yet. They are lost if you close." @('Discard and close', 'Keep working') 1 'warn') -ne 0) { $ev.Cancel = $true; return }
    $on = $false; try { $on = (Get-Status).Enabled } catch {}
    if ($on) {
      $r = Ask 'backd8 Setup - auto-backdating is ON' 'Auto-backdating is still ON for this PC' "Every new commit you make anywhere on this PC keeps getting a made-up date until you turn it off." @('Turn it OFF and close', 'Keep it ON and close', 'Cancel') 0 'warn' '' 2
      if ($r -eq 2) { $ev.Cancel = $true; return }
      if ($r -eq 0) { try { Set-Enabled $false } catch { } }
    }
    Save-Ui $f 'main'
  }
})
$f.MinHeight = [math]::Min(560, [Windows.SystemParameters]::WorkArea.Height - 20); $f.MinWidth = [math]::Min(800, [Windows.SystemParameters]::WorkArea.Width - 20)
Restore-Bounds $f 'main'
$script:eFilling = $false
Set-NewWhen 'now'
try { $script:PreCache = & $script:PreScript $null; $script:PreAt = Get-Date; $script:Pre = $script:PreCache } catch { }
Fill-Recent
Reset-ELoaded
try { $script:eWf = Get-WorkflowPlan '' @{} } catch { }
Show-WfState
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
  Check ((Info-Text) -like '*up to date*' -and (Role) -eq 'none') 'info says in sync, nothing to do'
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
  Check ((Role) -eq 'apply' -and $eDisc.IsEnabled -and (Get-ENext).Text -like '*Apply my 1 edit*') 'Apply/Revert enabled after saving a change'
  $item = $script:RowMap[$cMid.Sha]
  Check ($item.Mark.Children.Count -ge 2 -and $item.Subj.Text -eq 'Edited by selftest') 'list marks the staged edit with the new subject'
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
  Check ((Info-Text) -like '*needs a force push*' -and (Role) -eq 'force' -and (Get-ENext).Text -like "*Replace GitHub's version*") 'info explains the force push need and the button offers to replace'

  # push: normal refused, force works
  $remoteBefore = Head $bare "refs/heads/$branch"
  Check ($remoteBefore -eq $startHead) 'remote still has the original history'
  Check ((Do-EPush) -eq $false) 'normal push of rewritten history is refused'
  Check ((Head $bare "refs/heads/$branch") -eq $remoteBefore) 'remote unchanged after refused push'
  $threw = $false; try { [void](Push-Repo $repo) } catch { $threw = $true }
  Check $threw 'Push-Repo without -Force refuses'
  Check ((Do-EPush -Force) -eq $true) 'force push works'
  Check ((Head $bare "refs/heads/$branch") -eq (Head $repo)) 'remote head equals local head after force push'
  Check ($script:ePush.Ahead -eq 0 -and $script:ePush.Behind -eq 0 -and (Info-Text) -like '*up to date*') 'in sync after force push'

  # undo
  Do-EUndo
  Check ((Head $repo) -eq $startHead) 'undo restores the original head'
  Check (@(Get-Backups $repo).Count -eq $backups0) 'backup consumed'
  Check ($script:ePush.Behind -gt 0 -and $script:ePush.Ahead -gt 0 -and $script:ePush.RemoteOnly -eq 0 -and (Get-ENext).Role -eq 'force') 'after undo the rewritten commits on the remote are still OUR commits (undone ref), so the next step is replace, not someone else''s work'

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
    Check ($script:eChanges.Count -ge 1) 'changed files are listed after the folder became a project'
    # a risky file starts unticked
    Set-Content -LiteralPath (Join-Path $script:eRepo '.env') -Value 'SECRET=1'
    Do-ELoad $script:eRepo -NoAccess
    $env = @($script:FileRows | Where-Object { $_.Path -eq '.env' })[0]
    Check ($env -and -not $env.Box.IsChecked -and $env.Risky) 'risky file is flagged and unticked'
    Check ($nMsg.Text -eq 'First version' -or $nMsg.Text -like 'Add *' -or $nMsg.Text -like 'Update *') 'the express page pre-fills a message suggested from the changed files'; $nMsg.Text = ''; Update-EUi
    Check (-not (Get-ENewReady) -and (Get-ENext).Role -eq 'commit' -and -not (Get-ENext).Enabled -and (Get-ENext).Reason -like 'Write what you changed*') "no message yet (role=$((Get-ENext).Role) enabled=$((Get-ENext).Enabled) state=$((Get-ENext).State) reason=[$((Get-ENext).Reason)] newready=$(Get-ENewReady))"
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
    Check ((Get-ENext).State -eq 'ChangesPending') 'model: a left-out file still counts as a pending change (state ChangesPending)'; Remove-Item -LiteralPath (Join-Path $script:eRepo '.env') -Force; Do-ELoad $script:eRepo -NoAccess
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
    Check ((Get-ENext).Role -eq 'force' -and (Get-ENext).Text -like "*Replace GitHub's version*") "next step: replace GitHub's old version (role=$((Get-ENext).Role) ahead=$($script:ePush.Ahead) behind=$($script:ePush.Behind) remoteOnly=$($script:ePush.RemoteOnly) others=$($script:ePush.OthersCommits) text=$((Get-ENext).Text) me=[$((Get-GitIdentity $script:eRepo).Email)] theirs=[$((git -C $script:eRepo log -n 5 --format=%ae $script:ePush.TrackingSha --not HEAD) -join '|')])"
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















# regression drivers for the data-safety audit (one Check per bug); runs only inside -SelfTest, in a throw-away repo
function Test-Safety {
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-safety FAILED: $what" } }
  $T = Join-Path ([IO.Path]::GetTempPath()) "backd8-safety-$PID"; Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $T | Out-Null
  $gi = @('-c', 'user.name=Sim User', '-c', 'user.email=sim@example.com')
  $uiBefore = $env:BACKD8_UI_STATE
  try {
    $r = Join-Path $T 'proj'; $bare = Join-Path $T 'origin.git'
    [void](git init -q -b main $r 2>&1); [void](git init -q --bare -b main $bare 2>&1); [void](git -C $r config user.name 'Sim User'); [void](git -C $r config user.email 'sim@example.com')   # the test must not depend on the machine's global identity
    function Cm([string]$msg, [string]$who = 'Sim User', [string]$mail = 'sim@example.com') { Set-Content -LiteralPath (Join-Path $r "f$([guid]::NewGuid().ToString('N').Substring(0, 6)).txt") 'x'; [void](git -C $r add -A 2>&1); [void](git -C $r -c "user.name=$who" -c "user.email=$mail" commit -q -m $msg 2>&1) }
    Cm 'first'; Cm 'second'
    $mf = Join-Path $T 'crlf.txt'; [IO.File]::WriteAllText($mf, "CRLF title`r`n`r`nbody line`r`n"); Set-Content -LiteralPath (Join-Path $r 'crlf.txt') 'y'; [void](git -C $r add -A 2>&1); [void](git -C $r @gi commit -q --cleanup=verbatim -F $mf 2>&1)
    Cm 'bob work' 'Bob' 'bob@example.com'; Cm 'newest'
    [void](git -C $r remote add origin $bare 2>&1); [void](git -C $r push -q -u origin main 2>&1)
    Reset-ELoaded; Do-ELoad $r -NoAccess -Fetch
    Check ($script:eRepo -and $script:eCommits.Count -eq 5) 'safety repo loaded'
    $c = @{}; foreach ($x in $script:eCommits) { $c[$x.Subject] = $x }

    # 1 failed open keeps staged edits and the loaded project
    Do-ESelect $c['second'].Sha; $eMsg.Text = 'second, reworded'; Do-EStage
    Check ($script:eEdits.Count -eq 1) 'edit staged'
    $threw = $false; try { Do-ELoad (Join-Path $T 'does-not-exist') } catch { $threw = $true }
    Check ($threw -and $script:eEdits.Count -eq 1 -and (Norm $script:eRepo) -eq (Norm $r)) '#1 Do-ELoad of a missing folder keeps the staged edit and the project'
    $threw = $false; try { Open-Folder (Join-Path $T 'does-not-exist') } catch { $threw = $true }
    Check ($threw -and $script:eEdits.Count -eq 1 -and $script:eRepo) '#1 Open-Folder of a missing folder keeps the staged edit and the project'
    Do-ELoad $r -NoAccess -Fetch; Check ($script:eEdits.Count -eq 1) '#1 F5 reload keeps staged edits'
    Do-EDiscard; Do-ESelect $c['second'].Sha; Do-EDiscard

    # 2 unsaved typing counts as pending work
    Do-ESelect $c['first'].Sha; $eMsg.Text = 'typed but not kept'
    Check ((Get-EPendingNote) -like '*typed*') '#2 Get-EPendingNote includes unsaved typing'

    # 3 an invalid typed change is kept as a draft when another commit is selected
    $ePick.Date.Text = (Get-Date).AddDays(5).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    Check ((Get-ENext).Role -eq 'invalid') '#8 invalid typed change gives role invalid with a reason'
    Check ((Get-ENext).Reason -like '*future*') '#8 the reason says the date is in the future'
    $threw = $false; try { Do-EPublishAll } catch { $threw = $true }
    Check ($threw) '#8 Save and publish refuses (with a reason) instead of doing nothing'
    Do-ESelect $c['newest'].Sha
    Check ($script:eDrafts.ContainsKey($c['first'].Sha) -and (Get-EPendingNote) -like '*typed*') '#3 the invalid typing was kept as a draft and still counts as pending'
    Do-ESelect $c['first'].Sha
    Check ($eMsg.Text -eq 'typed but not kept') '#3 selecting the commit again restores the draft text'
    $script:eDrafts = @{}; Do-ESelect $c['newest'].Sha; $script:eDrafts = @{}

    # 4 CRLF messages are never "edited" without typing
    Do-ESelect $c['CRLF title'].Sha
    Check (-not (Get-EDirty)) '#4 a CRLF commit is not dirty when nothing was typed'
    Do-EStage
    Check ($script:eEdits.Count -eq 0) '#4 an unchanged CRLF message stages no edit'

    # message-only edit never touches the date (seconds + offset)
    $before = (git -C $r log -1 --format=%ad --date=raw $c['second'].Sha)
    Do-ESelect $c['second'].Sha; $eMsg.Text = 'second, message only'; Do-EStage
    Check ($script:eEdits[$c['second'].Sha].ContainsKey('message') -and -not $script:eEdits[$c['second'].Sha].ContainsKey('date')) 'message-only edit carries no date'
    [void](Do-EApply)
    $after = (git -C $r log -1 --format=%ad --date=raw --grep='second, message only')
    Check ($before -eq $after) "message-only edit left the author date byte-identical ($before vs $after)"
    Do-EUndo

    # 5 a staged edit whose commit vanished is pruned on load
    Do-ELoad $r -NoAccess; $top = $script:eCommits[0]
    Do-ESelect $top.Sha; $eMsg.Text = 'edit on a commit that will vanish'; Do-EStage
    Check ($script:eEdits.Count -eq 1) '#5 edit staged on the top commit'
    [void](git -C $r reset -q --hard HEAD~1 2>&1)
    Do-ELoad $r -NoAccess
    Check ($script:eEdits.Count -eq 0 -and $eLog.Text -like '*Dropped your saved change*') '#5 orphaned staged edit is pruned and the user is told'
    [void](git -C $r reset -q --hard origin/main 2>&1); Do-ELoad $r -NoAccess

    # 6+7 GitHub moved on: fetch on load shows Behind; behind-only offers Get latest, never replace
    $other = Join-Path $T 'otherpc'; [void](git clone -q $bare $other 2>&1)
    Set-Content -LiteralPath (Join-Path $other 'from-other-pc.txt') 'hello'; [void](git -C $other add -A 2>&1); [void](git -C $other @gi commit -q -m 'pushed from another PC' 2>&1); [void](git -C $other push -q origin main 2>&1)
    Do-ELoad $r -NoAccess -Fetch
    Check ($script:ePush.Behind -eq 1 -and $script:ePush.Ahead -eq 0) "#6 loading fetches, so Behind reflects GitHub (Behind=$($script:ePush.Behind) Ahead=$($script:ePush.Ahead) fetched=$($script:eFetch) top=$(git -C $r log -1 --format=%s) remote=$(git -C $bare log -1 --format=%s))"
    Check ((Info-Text) -notlike '*up to date*') '#6 never says up to date for a stale remote'
    $nx = Get-ENext
    Check ($nx.Role -eq 'getnew' -and $nx.Text -like 'Get the latest*' -and -not $nx.Force) '#7 behind-only: the primary action is Get the latest, never Replace'
    $h0 = (git -C $bare rev-parse refs/heads/main)
    Check ((Do-EPush) -eq $false -and (git -C $bare rev-parse refs/heads/main) -eq $h0) '#7 publishing while only behind does nothing (no replace)'
    Check ((Do-EPush -Force) -eq $false -and (git -C $bare rev-parse refs/heads/main) -eq $h0) '#7 not even -Force replaces when Ahead is 0'
    Check ((Do-EGetLatest) -eq $true -and $script:ePush.Behind -eq 0) 'Get latest brings the remote commit in'
    Check ((Format-Plural 1 'old commit') -eq '1 old commit' -and (Format-Plural 3 'old commit') -eq '3 old commits' -and (Format-Plural 0 'commit') -eq '0 commits') '#grammar Format-Plural'

    # 9 cancel kills the whole process tree
    $p = Start-Process -FilePath cmd.exe -ArgumentList '/c', 'ping -n 40 127.0.0.1 > nul' -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue)
    Stop-GitChildren; Start-Sleep -Milliseconds 700
    $alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue); $kidAlive = @($kids | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }).Count
    Check (-not $alive -and $kidAlive -eq 0) '#9 Stop-GitChildren kills the child AND its children'

    # 10 damaged ui.json is kept as .bak and starts fresh; recent list is validated and de-duplicated
    $env:BACKD8_UI_STATE = Join-Path $T 'ui.json'; Set-Content $env:BACKD8_UI_STATE '{ this is not json'
    $u = Load-Ui
    Check ($u -is [pscustomobject] -and (Test-Path "$($env:BACKD8_UI_STATE).bak") -and (Get-Content "$($env:BACKD8_UI_STATE).bak" -Raw) -like '*not json*') '#10 corrupt ui.json is backed up and replaced by an empty state'
    ConvertTo-Json -InputObject @{ recent = @($r, $r.ToUpper(), (Join-Path $T 'gone')) } | Set-Content $env:BACKD8_UI_STATE
    Check (@(Get-RecentList).Count -eq 1) '#10 recent list drops missing folders and case-insensitive duplicates'

    # 11 apply warns when other people wrote the commits that would be rewritten
    $pre = & $script:PrepApply $r @($c['first'].Sha)
    Check ($pre.OtherCount -ge 1 -and (@($pre.Others) -join ',') -like '*Bob*') 'author check finds commits written by other people'
    $pre0 = & $script:PrepApply $r @($script:eCommits[0].Sha)
    Check ($pre0.OtherCount -eq 0) 'no author warning when only your own commits are rewritten'

    # dates: too early / future, worst-case spread preview, time parsing
    Check ((Get-DateProblem ([datetime]'1960-01-01')) -like '*too early*') 'dates before 1971 are refused inline'
    Check ((Get-DateProblem (Get-Date).AddDays(2)) -like '*future*') 'future dates are refused inline'
    Check ((Parse-TimeText '9pm') -eq (New-TimeSpan -Hours 21) -and (Parse-TimeText '9:30') -eq (New-TimeSpan -Hours 9 -Minutes 30) -and (Parse-TimeText '21:05') -eq (New-TimeSpan -Hours 21 -Minutes 5) -and $null -eq (Parse-TimeText '25:00')) 'time input accepts 9:30 / 21:05 / 9pm'
    Do-ELoad $r -NoAccess
    $script:eSel = $null; Show-EView 'multi'; $script:eSelShas = @($script:eCommits[0].Sha, $script:eCommits[1].Sha, $script:eCommits[2].Sha)
    $mPick.Value = (Get-Date).AddHours(-10); Update-EMulti
    Check (-not $mBtn.IsEnabled -and $mPrev.Text -like '*no later than*') 'spread preview checks the worst case (6 h steps) and says how far back to start'
    $mPick.Value = (Get-Date).AddDays(-30); $script:eSelShas = @($script:eCommits[0].Sha, $script:eCommits[3].Sha); Update-EMulti
    Check ($mBtn.IsEnabled -and $mPrev.Text -like '*not next to each other*') 'spread preview warns about non-contiguous selections'
    Clear-EDetail
  } finally {
    $env:BACKD8_UI_STATE = $uiBefore
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
  }
  'selftest-safety-ok'
}


# every Ask() call shape in this file: build the dialog through the capture hook, click each button with the same Add_Click handlers, and
# assert the returned index is the clicked button (regression for the "Cannot convert value 'primary' to type Int32" crash)
function Test-Dialogs {
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-dialogs FAILED: $what" } }
  function Find-Buttons($el, $acc) { foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($el)) { if ($c -is [Windows.Controls.Button]) { $acc.Add($c) }; if ($c -is [Windows.DependencyObject]) { Find-Buttons $c $acc } } }
  $shapes = @(
    @{ n = 'one-button info'; a = @{ Title = 'T'; Heading = 'Done'; Buttons = @('OK'); Default = 0; Icon = 'info' } },
    @{ n = 'question, default 0 + cancel last'; a = @{ Title = 'T'; Heading = 'Sign in now?'; Body = 'b'; Buttons = @('Sign in...', 'Not now'); Default = 0; Icon = 'question' } },
    @{ n = 'warn, default = cancel'; a = @{ Title = 'T'; Heading = 'Leave?'; Buttons = @('Discard and open the other folder', 'Keep working here'); Default = 1; Icon = 'warn' } },
    @{ n = 'apply with details'; a = @{ Title = 'T'; Heading = 'Apply 2 edits?'; Body = 'b'; Buttons = @('Apply 2 edits', 'Cancel'); Default = 1; Icon = 'warn'; Details = "abc1234 message`nabc1235 date" } },
    @{ n = 'danger button + tick-box'; a = @{ Title = 'T'; Heading = 'Replace?'; Buttons = @("Replace GitHub's version", 'Cancel'); Default = 1; Icon = 'error'; Danger = 0; CheckText = 'I understand' } },
    @{ n = 'three buttons, cancel = 2'; a = @{ Title = 'T'; Heading = 'ON'; Buttons = @('Turn it OFF and close', 'Keep it ON and close', 'Cancel'); Default = 0; Icon = 'warn'; Cancel = 2 } },
    @{ n = 'crash shape (details, one button)'; a = @{ Title = 'T'; Heading = 'Sorry'; Buttons = @('Close'); Default = 0; Icon = 'error'; Details = "stack`nline2" } }
  )
  $script:dlgTestN = 0
  foreach ($s in $shapes) {
    $args_ = $s.a; $n = @($args_.Buttons).Count; $script:dlgShape = $s.n; $script:dlgN = $n; $script:dlgHasChk = [bool]$args_.CheckText
    $script:AskCapture = {
      param($w, $def, $cancel)
      $btns = New-Object 'System.Collections.Generic.List[object]'; Find-Buttons $w.Content $btns
      $real = @($btns | Where-Object { $_.Parent -is [Windows.Controls.StackPanel] -and $_.Parent.Orientation -eq 'Horizontal' -and $_.Parent.HorizontalAlignment -eq 'Center' })
      if ($real.Count -lt $script:dlgN) { throw "selftest-dialogs FAILED: [$($script:dlgShape)] found $($real.Count) buttons, expected $($script:dlgN)" }
      $chk = $null; $cl = New-Object 'System.Collections.Generic.List[object]'; function Find-Check($el) { foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($el)) { if ($c -is [Windows.Controls.CheckBox]) { $script:foundChk = $c }; if ($c -is [Windows.DependencyObject]) { Find-Check $c } } }
      $script:foundChk = $null; Find-Check $w.Content
      for ($i = 0; $i -lt $script:dlgN; $i++) {
        if ($script:foundChk) { $script:foundChk.IsChecked = $true; $script:foundChk.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ToggleButton]::ClickEvent))) }
        $script:askRes = -99
        try { $real[$i].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } catch { if ($_.Exception.Message -notmatch 'DialogResult|dialog') { throw } }
        if ($script:askRes -ne $i) { throw "selftest-dialogs FAILED: [$($script:dlgShape)] clicking button $i returned $($script:askRes)" }
      }
      if ($script:foundChk) { }
      $def
    }
    $script:Confirm = $true
    try { $r = Ask @args_ } finally { $script:AskCapture = $null; $script:Confirm = $false }
    $script:dlgTestN++
  }
  # the crash dialog: plain headline, the stack only behind Details, Copy details present
  $script:crashSeen = $null
  $script:AskCapture = { param($w, $def, $cancel) $texts = @(); $btns = New-Object 'System.Collections.Generic.List[object]'; Find-Buttons $w.Content $btns; $script:crashSeen = @{ Buttons = @($btns | ForEach-Object { (Get-Mn $_) }); Window = $w }; $def }
  $script:Confirm = $true
  try { Show-Crash ([Management.Automation.ErrorRecord](New-Object Management.Automation.ErrorRecord((New-Object Exception 'boom: Cannot convert value "primary" to type System.Int32')), 'x', 'NotSpecified', $null)) } finally { $script:AskCapture = $null; $script:Confirm = $false }
  Check ($script:crashSeen -and (@($script:crashSeen.Buttons) -contains 'Details >>') -and (@($script:crashSeen.Buttons) -contains 'Copy')) 'crash dialog has Details >> and Copy'
  'selftest-dialogs-ok'
}
# the wizard decides from engine state; sign-in state is derived from the latest check (never remembered); access keys are unique per page
function Test-Wizard {
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-wizard FAILED: $what" } }
  $T = Join-Path ([IO.Path]::GetTempPath()) "backd8-wizard-$PID"; Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $T | Out-Null
  $gi = @('-c', 'user.name=Sim User', '-c', 'user.email=sim@example.com')
  try {
    $r = Join-Path $T 'proj'; $bare = Join-Path $T 'origin.git'
    [void](git init -q -b main $r 2>&1); [void](git init -q --bare -b main $bare 2>&1)
    foreach ($n in 1..3) { Set-Content (Join-Path $r "c$n.txt") "$n"; [void](git -C $r add -A 2>&1); [void](git -C $r @gi commit -q -m "commit $n" 2>&1) }
    [void](git -C $r remote add origin $bare 2>&1); [void](git -C $r push -q -u origin main 2>&1)
    Set-Content (Join-Path $r 'a.cs') 'a'; Set-Content (Join-Path $r 'b.cs') 'b'
    Reset-ELoaded; $script:eAccess = $null; Do-ELoad $r -NoAccess -Fetch
    Check ($script:eWf.State -eq 'ChangesPending' -and $script:eWf.Recommended -eq 'Commit' -and $script:wizPage -eq 3) 'the model says ChangesPending and the view shows the express page'
    Check ((Get-ChangeSuggestion) -eq 'Add a.cs and 1 other file') "smart commit message ($(Get-ChangeSuggestion))"
    Check ($nMsg.Text -like 'Add a.cs*') 'the express page is pre-filled with the suggestion'
    $nMsg.Text = ''; Update-EUi
    $c = Get-WfAct 'Commit'; Check (-not $c.Enabled -and $c.Why -like 'Write what you changed*' -and -not $btnNext.IsEnabled) "disabled Next carries the model's reason ($($c.Why))"
    $nMsg.Text = 'Wizard test commit'; $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'local'; CanPush = $true; Advice = @(); Accounts = @(); NeedsAccountChoice = $false; Problem = $null }
    $plan = @(Get-EPlan)
    Check ((@($plan | ForEach-Object { $_.Id }) -join ',') -eq 'commit,publish') 'plan for new files = save as a commit, then send to GitHub'
    Check ($btnNext.IsEnabled) 'Next is enabled once a message exists'
    $headBefore = (git -C $bare rev-parse refs/heads/main)
    Run-Plan
    Check ($script:eWf.State -eq 'InSync' -and $script:wizPage -eq 5 -and (git -C $bare rev-parse refs/heads/main) -eq (git -C $r rev-parse HEAD) -and (git -C $bare rev-parse refs/heads/main) -ne $headBefore) 'Run-Plan saved, published and the model reached InSync (complete page)'
    Check ((git -C $r log -1 --format=%s) -eq 'Wizard test commit') 'the commit carries the typed message'
    Check ($spActs5.Children.Count -ge 2) 'the InSync page offers the state''s actions (change an older commit, choose another folder, ...)'

    # sign-in state is derived from the newest check: the Sign in button disappears as soon as the model says Yes, and Publish becomes the next step
    Set-Content (Join-Path $r 'd.txt') 'd'; [void](git -C $r add -A 2>&1); [void](git -C $r @gi commit -q -m 'unpublished' 2>&1)
    Do-ELoad $r -NoAccess
    Check ($script:eWf.State -eq 'ReadyToPublish') 'one unpublished commit = ReadyToPublish'
    $script:eWf.Facts.Access = 'NotSignedIn'; $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $false; Advice = @('sign in'); Accounts = @(); NeedsAccountChoice = $false; Problem = $null }
    Show-WfState
    Check ($script:eWf.State -eq 'NeedsSignIn' -and (Get-ENext).Role -eq 'signin' -and $btnSign.Visibility -eq 'Visible' -and $script:wizPage -eq 4) 'signed out: the model says NeedsSignIn, the Sign in button is shown on the publish page'
    $script:SignInHook = { param($p) [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $true; Advice = @(); Accounts = @('sim'); NeedsAccountChoice = $false; Problem = $null; AccountInUse = 'sim' } }
    $null = Do-ESignIn; $script:SignInHook = $null
    Check ($script:eWf.State -eq 'ReadyToPublish' -and (Get-ENext).Role -eq 'push' -and (Get-ENext).Text -eq 'Publish to GitHub' -and $btnSign.Visibility -eq 'Collapsed' -and $eAcc.Text -like 'Signed in*') 'after sign-in: the Sign in button is gone and the primary step is Publish'
    $script:eWf.Facts.Access = 'ChooseAccount'; $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $false; Advice = @(); Accounts = @('alice', 'bob'); NeedsAccountChoice = $true; Problem = $null }
    Update-EAccessLabel; Show-WfState
    Check ($script:eWf.State -eq 'ChooseAccount' -and $gAcct.Visibility -eq 'Visible' -and $spAccounts.Children.Count -eq 2 -and (Get-ENext).Role -eq 'account') 'several saved accounts: a radio per account and the next step is to choose one'
    $script:eWf.Facts.Access = 'NotFound'; $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'https'; CanPush = $false; Advice = @(); Accounts = @(); NeedsAccountChoice = $false; Problem = 'notfound' }
    Update-EAccessLabel; Show-WfState
    Check ($script:eWf.State -eq 'RepoNotFound' -and $pubProb.Visibility -eq 'Visible' -and $probFix.Visibility -eq 'Visible') 'repository not found: explained, with an address editor'
    $script:eWf.Facts.Access = 'Unknown'; $script:eAccess = [pscustomobject]@{ GitInstalled = $true; Url = 'x'; Transport = 'local'; CanPush = $true; Advice = @(); Accounts = @(); NeedsAccountChoice = $false; Problem = $null }; Update-EAccessLabel; Show-WfState

    # access keys: unique on every page (and variant), registered only while their control is on screen
    foreach ($case in @(@(1, 'express'), @(3, 'express'), @(3, 'edit'), @(4, 'express'), @(5, 'express'))) {
      $script:eAction = $case[1]; Go-Page $case[0]; Apply-MnScope
      $d = @(Get-DuplicateKeys); Check ($d.Count -eq 0) "duplicate access keys on page $($case[0]) ($($case[1])): $($d -join '; ')"
    }
    Go-Page 3; Apply-MnScope; $on = @($script:MnReg | Where-Object { $_.On }); Check ($on.Count -ge 5 -and @($on | Where-Object { $_.Key -eq 'B' }).Count -le 1) "access keys are registered for the visible page ($($on.Count) active)"
  } finally { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
  'selftest-wizard-ok'
}
function Test-Trust {
  function Check($ok, [string]$what) { if (-not $ok) { throw "selftest-trust FAILED: $what" } }
  $T = Join-Path ([IO.Path]::GetTempPath()) "backd8-trust-$PID"; Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $T | Out-Null
  try {
    $r = Join-Path $T 'downloaded'; [void](git init -q -b main $r 2>&1); Set-Content (Join-Path $r 'a.txt') 'x'; [void](git -C $r add -A 2>&1); [void](git -C $r -c user.name=T -c user.email=t@example.com commit -q -m one 2>&1)
    Add-Content -LiteralPath (Join-Path $r '.git\config') "[core]`n`tfsmonitor = echo`n"
    Reset-ELoaded
    $script:TrustHook = { param($root, $names) $script:trustAsked = @($names); $false }; $script:trustAsked = $null
    Do-ELoad $r -NoAccess
    Check ($script:trustAsked -and (@($script:trustAsked) -join ',') -like '*core.fsmonitor*') 'the trust page lists the offending setting names'
    Check (-not $script:eRepo -and $script:eView -eq 'none' -and $script:eCommits.Count -eq 0) 'declined: the editor is not reached and nothing is loaded'
    Check ($bnSub.Border.Visibility -eq 'Visible' -and $bnSub.Title.Text -like '*run programs*') 'declined: a plain banner explains why the project was not opened'
    $script:TrustHook = { param($root, $names) $true }
    Do-ELoad $r -NoAccess
    Check ($script:eRepo -and (Norm $script:eRepo) -eq (Norm $r) -and $script:eCommits.Count -eq 1) 'trusted: only after the trust hook says yes does the project load'
    $script:TrustHook = $null
  } finally { $script:TrustHook = $null; Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
  'selftest-trust-ok'
}
try { Refresh } catch { }
if ($NoShow) { return }
if ($SelfTest) {
  # drive the same handlers the buttons call; uat.ps1 inspects the resulting config
  Do-Install; Do-Default; Do-Add $env:BACKD8_TEST_REPO; Do-Toggle
  $row = [string]$lv.Items[0].Tag; Do-Update $row; Do-Toggle; Do-Remove $row; Do-Install
  "selftest-ok rows=$($lv.Items.Count)"
  if ($env:BACKD8_TEST_REPO2) { Test-Editor $env:BACKD8_TEST_REPO2 } else { 'selftest-editor-skipped (BACKD8_TEST_REPO2 not set)' }
  if ($env:BACKD8_TEST_PLAIN) { Test-Flow $env:BACKD8_TEST_PLAIN $env:BACKD8_TEST_REPO2 } else { 'selftest-flow-skipped (BACKD8_TEST_PLAIN not set)' }
  Test-Dialogs
  Test-Wizard
  Test-Trust
  Test-Safety
  return
}
$script:ActiveOwner = $f
$script:App.Add_DispatcherUnhandledException({ param($s, $e) $e.Handled = $true; Show-Crash $e.Exception })
$f.Add_ContentRendered({
  if ($script:started) { return }; $script:started = $true
  try { [void]$f.Dispatcher }  catch {}
  if (-not (Test-GitInstalled)) { return }
  $u = Load-Ui; if ($u.lastRepo -and (Test-Path -LiteralPath ([string]$u.lastRepo) -PathType Container)) { $tbPath.Text = [string]$u.lastRepo; Open-Folder ([string]$u.lastRepo) -Quiet }
  Start-PreAsync
})
try { [void]$f.ShowDialog() } catch { Show-Crash $_ }











