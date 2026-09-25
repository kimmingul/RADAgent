# Builds and runs tests\ProtocolTests.dpr (64-bit console) with one RAD Studio release.
#   test.ps1 [-Version 22.0]
param([string]$Version = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bds.ps1')
$tests = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests'
New-Item -ItemType Directory -Force -Path (Join-Path $tests 'dcu') | Out-Null
Push-Location $tests
try {
  cmd /c "call `"$rsvars`" >nul && dcc64 -Q -B -NUdcu -NSSystem;Winapi;System.Win ProtocolTests.dpr"
  if ($LASTEXITCODE -ne 0) { Fail "dcc64 tests\ProtocolTests.dpr failed (BDS=$bds)." }
  & (Join-Path $tests 'ProtocolTests.exe')
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
