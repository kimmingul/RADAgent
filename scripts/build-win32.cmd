@echo off
setlocal
set "RSVARS=%BDS%\bin\rsvars.bat"
if not exist "%RSVARS%" set "RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if not exist "%RSVARS%" goto nobds
call "%RSVARS%"
if "%BDS%"=="" goto nobds
msbuild "%~dp0..\src\DelphiAgent.dproj" /nologo /v:minimal /p:Config=Release /p:Platform=Win32
if errorlevel 1 goto fail
set "BPLDIR=%BDSCOMMONDIR%\Bpl"
set "NEWBPL=%BPLDIR%\DelphiAgent.bpl"
set "INSTBPL=%BPLDIR%\DelphiAgent370.bpl"
if exist "%NEWBPL%" (
  copy /Y "%NEWBPL%" "%INSTBPL%" >nul
  if errorlevel 1 goto fail
  del /F /Q "%NEWBPL%"
  if exist "%NEWBPL%" goto fail
)
if not exist "%INSTBPL%" goto fail
powershell -NoProfile -Command "if ((Get-Item -LiteralPath '%INSTBPL%').LastWriteTime -lt (Get-Item -LiteralPath '%~dp0..\src\DelphiAgent.Wizard.pas').LastWriteTime) { exit 1 }"
if errorlevel 1 goto stale
exit /b 0
:stale
echo [DelphiAgent] DelphiAgent370.bpl이 교체되지 않았습니다. Wizard.pas보다 오래되었습니다.
echo [DelphiAgent] BDS=%BDS%
exit /b 1
:nobds
echo [DelphiAgent] BDS가 없습니다. 가정한 경로: C:\Program Files (x86)\Embarcadero\Studio\37.0
echo [DelphiAgent] 실패한 명령: call rsvars.bat
exit /b 1
:fail
echo [DelphiAgent] 실패한 명령: msbuild src\DelphiAgent.dproj /p:Config=Release /p:Platform=Win32
echo [DelphiAgent] BDS=%BDS%
exit /b 1