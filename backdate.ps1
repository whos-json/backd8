# CLI + git hook entry. Usage:
#   backdate.ps1 install [-Force] | uninstall | on | off | status | list
#   backdate.ps1 set <repo-folder|*> <date> | remove <repo-folder> | hook
param([string]$Command = 'status', [string]$Arg1, [string]$Arg2, [switch]$Force)
. "$PSScriptRoot\lib.ps1"
try {
  switch ($Command) {
    'install'   { Install-Hooks -Force:$Force; 'Installed. Backdating stays OFF until you run: set * <date>, then on' }
    'uninstall' { Uninstall-Hooks }
    'on'        { Set-Enabled $true;  'Backdating ON - every commit on this PC is now backdated' }
    'off'       { Set-Enabled $false; 'Backdating OFF' }
    'set'       { Set-StartDate $Arg1 ([datetime]$Arg2); "Set $Arg1 -> $Arg2" }
    'remove'    { Remove-Repo $Arg1; "Removed $Arg1" }
    'list'      { $c = Get-Config; "default: $($c.default.start)"; @($c.repos) | Format-Table path, start, next -AutoSize | Out-String }
    'status'    { $s = Get-Status; "Hook installed: $($s.Installed)  (core.hooksPath = $($s.HooksPath))"; "Backdating:     $(if ($s.Enabled) {'ON'} else {'OFF'})" }
    'hook'      { Invoke-Hook }
    default     { throw "Unknown command '$Command'" }
  }
} catch { Write-Host "Error: $($_.Exception.Message)"; exit 1 }
