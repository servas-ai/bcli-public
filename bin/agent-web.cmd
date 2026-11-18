@echo off
rem agent-web launcher for cmd.exe and other Windows shells; runs agent-web.ps1 from the same folder.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-web.ps1" %*
exit /b %ERRORLEVEL%
