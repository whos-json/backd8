@echo off
rem Launcher: works even where PowerShell scripts are blocked by the execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0backdate.ps1" %*
exit /b %ERRORLEVEL%
