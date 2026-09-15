@echo off
setlocal
rem Native cmd.exe entry point for install.ps1. Arguments such as -Version
rem 0.1.4 and -InstallDir C:\Tools\px0 are passed through unchanged.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %ERRORLEVEL%
