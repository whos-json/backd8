# Builds BackD8.exe with the C# compiler that ships with Windows (no SDK needed).
# Usage: build.ps1 [-Out <path-to-exe>]   (default: BackD8.exe next to this script)
param([string]$Out)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
if (-not $Out) { $Out = Join-Path $dir 'BackD8.exe' }
$src = Join-Path $dir 'BackD8.cs'
if (-not (Test-Path -LiteralPath $src)) { throw "Source not found: $src" }

$fw = Join-Path $env:WINDIR 'Microsoft.NET'
$candidates = 'Framework64', 'Framework' | ForEach-Object { Join-Path $fw "$_\v4.0.30319\csc.exe" }
$csc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw "csc.exe (.NET Framework 4.x C# compiler) not found. Looked in:`n  $($candidates -join "`n  ")" }

$outDir = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

& $csc /nologo /target:winexe /out:"$Out" /r:System.Windows.Forms.dll "$src"
if ($LASTEXITCODE) { throw "build failed (csc exit code $LASTEXITCODE)" }
"Built $Out"
