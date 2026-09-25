# Builds the RADAgent design-time package for one RAD Studio release and one IDE bitness, then
# copies the chat page and WebView2Loader.dll next to it (deploy-assets.ps1).
#
#   build.ps1 -Platform Win32 [-Version 22.0]
#
# -Version is the BDS version of the IDE: 21.0 = 10.4 Sydney, 22.0 = 11 Alexandria,
# 23.0 = 12 Athens, 37.0 = 13 Florence. Without it: %BDS%, else the newest installed release.
# The BPL is RADAgent<suffix>.bpl ({$LIBSUFFIX AUTO}: 270, 280, 290, 370).
param(
  [ValidateSet('Win32', 'Win64')][string]$Platform = 'Win32',
  [string]$Version = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'bds.ps1')
if ($Platform -eq 'Win64' -and -not (Test-Path (Join-Path $bds 'bin64\bds.exe'))) {
  Write-Host "[RADAgent] RAD Studio $Version has no 64-bit IDE; the Win64 package is not needed."
  exit 0
}

$dproj = Join-Path $root 'src\RADAgent.dproj'
$commonDir = ((cmd /c "call `"$rsvars`" >nul && set BDSCOMMONDIR") -split '=', 2)[1].Trim()
cmd /c "call `"$rsvars`" >nul && msbuild `"$dproj`" /nologo /v:minimal /p:Config=Release /p:Platform=$Platform"
if ($LASTEXITCODE -ne 0) { Fail "msbuild src\RADAgent.dproj /p:Platform=$Platform failed (BDS=$bds)." }

$bplDir = Join-Path $commonDir 'Bpl'
if ($Platform -eq 'Win64') { $bplDir = Join-Path $bplDir 'Win64' }
$bpl = Join-Path $bplDir "RADAgent$suffix.bpl"
if (-not (Test-Path $bpl)) { Fail "$bpl was not written." }
$wizard = Join-Path $root 'src\RADAgent.Wizard.pas'
if ((Get-Item -LiteralPath $bpl).LastWriteTime -lt (Get-Item -LiteralPath $wizard).LastWriteTime) {
  Fail "$bpl is older than RADAgent.Wizard.pas: it was not replaced (is the IDE still running?)."
}
$arch = 'x86'
if ($Platform -eq 'Win64') { $arch = 'x64' }
& (Join-Path $PSScriptRoot 'deploy-assets.ps1') -BplDir $bplDir -Arch $arch
Write-Host "[RADAgent] $bpl (RAD Studio $Version, $Platform)"
