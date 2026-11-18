@echo off
rem agent-web for Windows: runs agent-web-ps.ps1 from the same folder.
rem -ExecutionPolicy Bypass applies to this one process only, so agent-web also works
rem where the machine's execution policy is Restricted (default on a fresh Windows 11).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-web-ps.ps1" %*
exit /b %ERRORLEVEL%
