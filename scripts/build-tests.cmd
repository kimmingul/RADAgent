@echo off
rem Builds and runs the protocol tests. Optional: -Version 22.0 (see build.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test.ps1" %*
exit /b %ERRORLEVEL%
