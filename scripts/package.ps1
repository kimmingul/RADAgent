# Builds the RADAgent setup: for every chosen RAD Studio release it builds the package (Win32, and
# Win64 where the 64-bit IDE exists), stages it with the chat page and WebView2Loader.dll, signs
# the BPLs with the Nanum Space certificate (USB token, scripts\release\signing.ps1), and compiles
# installer\RADAgent.iss with Inno Setup, which signs the setup and its uninstaller.
#
#   package.ps1                     every supported release installed on this PC, signed
#   package.ps1 -Versions 37.0      only RAD Studio 13
#   package.ps1 -NoSign             unsigned test build (no token needed)
#
# Output: dist\RADAgent-Setup-<version>.exe and its SHA-256. Close RAD Studio first.
param(
  [string[]]$Versions = @(),
  [switch]$NoSign
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$BdsFunctionsOnly = $true
. (Join-Path $PSScriptRoot 'bds.ps1')
# build.ps1 runs as a child scope and would see it.
Remove-Variable BdsFunctionsOnly
if (-not $NoSign) { . (Join-Path $PSScriptRoot 'release\signing.ps1') }

if (Get-Process -Name bds -ErrorAction SilentlyContinue) { Fail 'Close RAD Studio first: it locks the packages.' }
if ($Versions.Count -eq 0) { $Versions = InstalledBdsVersions }
if ($Versions.Count -eq 0) { Fail 'No supported RAD Studio found (10.4 Sydney or later).' }
foreach ($ver in $Versions) {
  if (-not $suffixes.ContainsKey($ver)) { Fail "BDS $ver is not supported." }
  if (-not (RootOf $ver)) { Fail "RAD Studio $ver is not installed on this PC." }
}

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) { Fail 'Inno Setup 6 (ISCC.exe) is required: winget install JRSoftware.InnoSetup' }
if (-not $NoSign) {
  $null = Get-SigningCertificate
  Unlock-SigningToken
}

# The omp release the setup downloads when omp is missing: the one RADAgent is tested with
# (TestedOmpVersion in RADAgent.OmpProbe), checked by the SHA-256 GitHub publishes for it.
$probe = Get-Content -LiteralPath (Join-Path $root 'src\RADAgent.OmpProbe.pas') -Raw
if ($probe -notmatch "TestedOmpVersion = '([0-9.]+)'") { Fail 'TestedOmpVersion not found in RADAgent.OmpProbe.pas.' }
$ompVersion = $Matches[1]
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/can1357/oh-my-pi/releases/tags/v$ompVersion" -Headers @{ 'User-Agent' = 'RADAgent-package' } -TimeoutSec 60
$asset = @($release.assets | Where-Object { $_.name -eq 'omp-windows-x64.exe' })
if ($asset.Count -ne 1 -or "$($asset[0].digest)" -notmatch '^sha256:([0-9a-f]{64})$') { Fail "No SHA-256 for omp $ompVersion omp-windows-x64.exe on GitHub." }
$ompSha256 = $Matches[1]

$stage = Join-Path $root 'artifacts\package'
$payload = Join-Path $stage 'payload'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $payload -Force

$bpls = @()
foreach ($ver in $Versions) {
  $bdsRoot = RootOf $ver
  $platforms = @('Win32')
  if (Test-Path (Join-Path $bdsRoot 'bin64\bds.exe')) { $platforms += 'Win64' }
  foreach ($platform in $platforms) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Platform $platform -Version $ver
    if ($LASTEXITCODE -ne 0) { Fail "Build failed: RAD Studio $ver $platform." }
    $rsvars = Join-Path $bdsRoot 'bin\rsvars.bat'
    $commonDir = ((cmd /c "call `"$rsvars`" >nul && set BDSCOMMONDIR") -split '=', 2)[1].Trim()
    $built = Join-Path $commonDir 'Bpl'
    if ($platform -eq 'Win64') { $built = Join-Path $built 'Win64' }
    $name = "RADAgent$($suffixes[$ver]).bpl"
    $target = Join-Path $payload "$ver\$platform"
    $null = New-Item -ItemType Directory -Path $target -Force
    Copy-Item -LiteralPath (Join-Path $built $name) -Destination $target
    # The chat page and the loader of this bitness, fresh from the sources.
    $arch = 'x86'
    if ($platform -eq 'Win64') { $arch = 'x64' }
    & (Join-Path $PSScriptRoot 'deploy-assets.ps1') -BplDir $target -Arch $arch | Out-Null
    $loader = Join-Path $target 'RADAgent\WebView2Loader.dll'
    if ((Get-AuthenticodeSignature -LiteralPath $loader).Status -ne 'Valid') { Fail "WebView2Loader.dll is not validly signed: $loader" }
    $bpls += Join-Path $target $name
  }
}

$version = [Diagnostics.FileVersionInfo]::GetVersionInfo($bpls[0]).FileVersion
foreach ($bpl in $bpls) {
  if ([Diagnostics.FileVersionInfo]::GetVersionInfo($bpl).FileVersion -ne $version) { Fail 'The packages carry different versions.' }
  if (-not $NoSign) { Invoke-CodeSign $bpl }
}

$dist = Join-Path $root 'dist'
$null = New-Item -ItemType Directory -Path $dist -Force
$setup = Join-Path $dist "RADAgent-Setup-$version.exe"
if (Test-Path -LiteralPath $setup) { Remove-Item -LiteralPath $setup -Force }
$arguments = @('/Q', "/DAppVersion=$version", "/DPayloadDir=$payload", "/DOutputDir=$dist",
  "/DOmpVersion=$ompVersion", "/DOmpSha256=$ompSha256")
if (-not $NoSign) { $arguments += @('/DSign=1', ('/Snanum=' + (Get-InnoSignCommand))) }
$arguments += (Join-Path $root 'installer\RADAgent.iss')
& $iscc @arguments
if ($LASTEXITCODE -ne 0) { Fail "Inno Setup failed (exit $LASTEXITCODE)." }
if (-not (Test-Path -LiteralPath $setup)) { Fail "Setup was not written: $setup" }
if (-not $NoSign -and -not (Test-NanumSignature $setup)) { Fail 'The setup is not signed and timestamped.' }

[pscustomobject]@{
  Setup = $setup
  Version = $version
  Releases = ($Versions -join ', ')
  Signed = -not $NoSign
  Omp = $ompVersion
  SHA256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
}
