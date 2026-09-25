@echo off
rem Builds RADAgent<suffix>.bpl for the Win64 IDE. Optional: -Version 22.0 (see build.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Platform Win64 %*
exit /b %ERRORLEVEL%
