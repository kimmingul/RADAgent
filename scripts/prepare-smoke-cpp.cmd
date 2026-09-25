@echo off
setlocal
set "SRC=%~dp0..\tests\smoke-cpp"
set "DST=%TEMP%\RADAgentSmokeCpp"
if exist "%DST%" rmdir /S /Q "%DST%"
if exist "%DST%" goto locked
mkdir "%DST%"
copy /Y "%SRC%\*.*" "%DST%\" >nul
if not exist "%DST%\SmokeCpp.cbproj" goto fail
if not exist "%DST%\MainForm.cpp" goto fail
echo [RADAgent] 준비 완료: %DST%\SmokeCpp.cbproj
exit /b 0
:locked
echo [RADAgent] %DST% 를 지우지 못했습니다. 그 프로젝트를 연 IDE를 닫고 다시 실행하세요.
exit /b 1
:fail
echo [RADAgent] 복사 실패: %SRC%
exit /b 1
