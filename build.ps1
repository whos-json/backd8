# Builds BackD8.exe with the C# compiler that ships with Windows (no SDK needed).
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /out:"$PSScriptRoot\BackD8.exe" /r:System.Windows.Forms.dll "$PSScriptRoot\BackD8.cs"
if ($LASTEXITCODE) { throw 'build failed' }
"Built $PSScriptRoot\BackD8.exe"
