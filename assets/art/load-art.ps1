# load-art.ps1 - dot-source me:   . "$PSScriptRoot\assets\art\load-art.ps1"
#
#   Get-ArtBitmap 'art-signin'        -> frozen System.Windows.Media.Imaging.BitmapImage (cached)
#   New-ArtImage  'icon-folder' [-Scale 2]  -> System.Windows.Controls.Image, NearestNeighbor already applied
#
# NAME is the PNG file name without extension, e.g. art-publish, icon-lock, icon-lock-32, glyph-dot-green, glyph-pencil-16.
#
# IMPORTANT: this is pixel art. Whenever you put the BitmapImage into your own Image / ImageBrush, set
#     [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, 'NearestNeighbor')
# (XAML: RenderOptions.BitmapScalingMode="NearestNeighbor" SnapsToDevicePixels="True" UseLayoutRounding="True")
# or WPF will blur it. Show it at native size or an integer multiple of it.

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$script:ArtRoot  = $PSScriptRoot
$script:ArtCache = @{}

function Get-ArtBitmap {
    param([Parameter(Mandatory)][string]$Name)
    $key = $Name.ToLowerInvariant() -replace '\.png$', ''
    if ($script:ArtCache.ContainsKey($key)) { return $script:ArtCache[$key] }
    $path = Join-Path $script:ArtRoot "$key.png"
    if (-not (Test-Path -LiteralPath $path)) { throw "Art '$Name' not found: $path" }
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.UriSource = New-Object System.Uri $path
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
    $bi.EndInit()
    $bi.Freeze()
    $script:ArtCache[$key] = $bi
    return $bi
}

function New-ArtImage {
    param([Parameter(Mandatory)][string]$Name, [int]$Scale = 1)
    $bi = Get-ArtBitmap $Name
    $img = New-Object System.Windows.Controls.Image
    $img.Source = $bi
    $img.Stretch = [System.Windows.Media.Stretch]::Fill
    $img.Width  = $bi.PixelWidth  * $Scale
    $img.Height = $bi.PixelHeight * $Scale
    $img.SnapsToDevicePixels = $true
    $img.UseLayoutRounding = $true
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
    return $img
}
