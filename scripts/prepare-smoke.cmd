@echo off
setlocal
set "SRC=%~dp0..\tests\smoke"
set "DST=%TEMP%\DelphiAgentSmoke"
if exist "%DST%" rmdir /S /Q "%DST%"
if exist "%DST%" goto locked
mkdir "%DST%"
copy /Y "%SRC%\Smoke.dpr" "%DST%\" >nul
copy /Y "%SRC%\Smoke.dproj" "%DST%\" >nul
copy /Y "%SRC%\MainForm.pas" "%DST%\" >nul
copy /Y "%SRC%\MainForm.dfm" "%DST%\" >nul
if not exist "%DST%\Smoke.dproj" goto fail
if not exist "%DST%\MainForm.pas" goto fail
echo [DelphiAgent] 준비 완료: %DST%\Smoke.dproj
exit /b 0
:locked
echo [DelphiAgent] %DST% 를 지우지 못했습니다. 그 프로젝트를 연 IDE를 닫고 다시 실행하세요.
exit /b 1
:fail
echo [DelphiAgent] 복사 실패: %SRC%
exit /b 1
