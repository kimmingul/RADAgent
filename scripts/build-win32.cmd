@echo off
setlocal
set "RSVARS=%BDS%\bin\rsvars.bat"
if not exist "%RSVARS%" set "RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if not exist "%RSVARS%" goto nobds
call "%RSVARS%"
if "%BDS%"=="" goto nobds
msbuild "%~dp0..\src\RADAgent.dproj" /nologo /v:minimal /p:Config=Release /p:Platform=Win32
if errorlevel 1 goto fail
set "BPLDIR=%BDSCOMMONDIR%\Bpl"
set "NEWBPL=%BPLDIR%\RADAgent.bpl"
set "INSTBPL=%BPLDIR%\RADAgent370.bpl"
if exist "%NEWBPL%" (
  copy /Y "%NEWBPL%" "%INSTBPL%" >nul
  if errorlevel 1 goto fail
  del /F /Q "%NEWBPL%"
  if exist "%NEWBPL%" goto fail
)
if not exist "%INSTBPL%" goto fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-assets.ps1" -BplDir "%BPLDIR%" -Arch x86
if errorlevel 1 goto fail
powershell -NoProfile -Command "if ((Get-Item -LiteralPath '%INSTBPL%').LastWriteTime -lt (Get-Item -LiteralPath '%~dp0..\src\RADAgent.Wizard.pas').LastWriteTime) { exit 1 }"
if errorlevel 1 goto stale
exit /b 0
:stale
echo [RADAgent] RADAgent370.bpl이 교체되지 않았습니다. Wizard.pas보다 오래되었습니다.
echo [RADAgent] BDS=%BDS%
exit /b 1
:nobds
echo [RADAgent] BDS가 없습니다. 가정한 경로: C:\Program Files (x86)\Embarcadero\Studio\37.0
echo [RADAgent] 실패한 명령: call rsvars.bat
exit /b 1
:fail
echo [RADAgent] 실패한 명령: msbuild src\RADAgent.dproj /p:Config=Release /p:Platform=Win32
echo [RADAgent] BDS=%BDS%
exit /b 1