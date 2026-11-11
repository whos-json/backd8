# Tiny stand-in for GitHub used by tests\simulate.ps1: a real smart-HTTP git server (git http-backend) that demands
# HTTP Basic auth. Any username + the right token = signed in. Everything else gets 401, exactly like GitHub.
# Usage: fake-github.ps1 -Port 8765 -Root C:\data -Token ghp_xxx -Log C:\log.txt -Ready C:\ready.flag
param([int]$Port, [string]$Root, [string]$Token, [string]$Log, [string]$Ready)
$ErrorActionPreference = 'Stop'
$backend = Join-Path (& git --exec-path) 'git-http-backend.exe'
$l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$Port/"); $l.Start()
Set-Content $Ready 'ready'
while ($true) {
  $ctx = $l.GetContext(); $req = $ctx.Request; $res = $ctx.Response
  try {
    $user = $null
    $auth = $req.Headers['Authorization']
    if ($auth -like 'Basic *') {
      $pair = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($auth.Substring(6)))
      $i = $pair.IndexOf(':'); if ($i -ge 0 -and $pair.Substring($i + 1) -eq $Token) { $user = $pair.Substring(0, $i) }
    }
    Add-Content $Log "$($req.HttpMethod) $($req.Url.PathAndQuery) auth=$([bool]$user)"
    if (-not $user) { $res.StatusCode = 401; $res.AddHeader('WWW-Authenticate', 'Basic realm="GitHub"'); $res.Close(); continue }

    $psi = New-Object Diagnostics.ProcessStartInfo $backend
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $e = $psi.EnvironmentVariables
    $e['GIT_PROJECT_ROOT'] = $Root; $e['GIT_HTTP_EXPORT_ALL'] = '1'; $e['REMOTE_USER'] = $user; $e['REMOTE_ADDR'] = '127.0.0.1'
    $e['REQUEST_METHOD'] = $req.HttpMethod; $e['PATH_INFO'] = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
    $e['QUERY_STRING'] = $req.Url.Query.TrimStart('?'); $e['CONTENT_TYPE'] = [string]$req.ContentType
    if ($req.Headers['Content-Encoding']) { $e['HTTP_CONTENT_ENCODING'] = $req.Headers['Content-Encoding'] }
    if ($req.Headers['Git-Protocol']) { $e['GIT_PROTOCOL'] = $req.Headers['Git-Protocol']; $e['HTTP_GIT_PROTOCOL'] = $req.Headers['Git-Protocol'] }
    $body = New-Object IO.MemoryStream; if ($req.HasEntityBody) { $req.InputStream.CopyTo($body) }
    $e['CONTENT_LENGTH'] = [string]$body.Length
    $p = [Diagnostics.Process]::Start($psi)
    $body.Position = 0; $body.CopyTo($p.StandardInput.BaseStream); $p.StandardInput.Close()
    $out = New-Object IO.MemoryStream; $p.StandardOutput.BaseStream.CopyTo($out); $p.WaitForExit()
    $b = $out.ToArray(); $split = -1
    for ($k = 0; $k -lt $b.Length - 3; $k++) { if ($b[$k] -eq 13 -and $b[$k + 1] -eq 10 -and $b[$k + 2] -eq 13 -and $b[$k + 3] -eq 10) { $split = $k; break } }
    if ($split -lt 0) { $res.StatusCode = 500; $res.Close(); continue }
    $res.StatusCode = 200
    foreach ($h in ([Text.Encoding]::ASCII.GetString($b, 0, $split) -split "`r`n")) {
      $c = $h.IndexOf(':'); if ($c -lt 1) { continue }
      $name = $h.Substring(0, $c); $val = $h.Substring($c + 1).Trim()
      if ($name -eq 'Status') { $res.StatusCode = [int]($val -split ' ')[0] }
      elseif ($name -eq 'Content-Type') { $res.ContentType = $val }
      else { $res.AddHeader($name, $val) }
    }
    $n = $b.Length - $split - 4; $res.ContentLength64 = $n
    if ($n -gt 0) { $res.OutputStream.Write($b, $split + 4, $n) }
    $res.Close()
  } catch { try { $res.StatusCode = 500; $res.Close() } catch {} ; Add-Content $Log "ERROR $($_.Exception.Message)" }
}
