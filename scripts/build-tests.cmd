@echo off
setlocal
set "RSVARS=%BDS%\bin\rsvars.bat"
if not exist "%RSVARS%" set "RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if not exist "%RSVARS%" goto nobds
call "%RSVARS%"
if "%BDS%"=="" goto nobds
pushd "%~dp0..\tests"
if not exist dcu mkdir dcu
dcc64 -Q -B -NUdcu -NSSystem;Winapi;System.Win ProtocolTests.dpr
if errorlevel 1 goto fail
ProtocolTests.exe
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%
:nobds
echo [DelphiAgent] BDS를 찾지 못했습니다. 가정한 경로: C:\Program Files (x86)\Embarcadero\Studio\37.0
exit /b 1
:fail
popd
echo [DelphiAgent] 테스트 빌드 실패: dcc64 tests\ProtocolTests.dpr
exit /b 1
