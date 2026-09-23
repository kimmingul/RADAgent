# Downloads the pinned Microsoft.Web.WebView2 NuGet package and extracts WebView2Loader.dll
# for x86 and x64 into third_party\webview2\<arch>\. The loader is Microsoft-signed and
# redistributable; the WebView2 runtime itself is not shipped (Windows provides it).
param(
  [string]$Version = '1.0.4191.47'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'third_party\webview2'
$want = @{ 'x86' = (Join-Path $dest 'x86\WebView2Loader.dll'); 'x64' = (Join-Path $dest 'x64\WebView2Loader.dll') }
if ((Test-Path $want['x86']) -and (Test-Path $want['x64'])) { exit 0 }

$tmp = Join-Path $env:TEMP ("DelphiAgentWebView2-" + $Version)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pkg = Join-Path $tmp 'webview2.zip'
$url = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$Version/microsoft.web.webview2.$Version.nupkg"
Write-Host "[DelphiAgent] WebView2 SDK $Version 받는 중: $url"
Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($pkg)
try {
  foreach ($arch in @('x86', 'x64')) {
    $entry = $zip.Entries | Where-Object {
      $_.FullName -ieq "runtimes/win-$arch/native/WebView2Loader.dll" -or
      $_.FullName -ieq "build/native/$arch/WebView2Loader.dll" } | Select-Object -First 1
    if ($null -eq $entry) { throw "패키지에 $arch WebView2Loader.dll이 없습니다." }
    $target = $want[$arch]
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    $sig = Get-AuthenticodeSignature -FilePath $target
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
      Remove-Item -Force $target
      throw "서명이 올바르지 않습니다: $target ($($sig.Status))"
    }
    Write-Host "[DelphiAgent] $arch 로더: $target"
  }
} finally {
  $zip.Dispose()
  Remove-Item -Recurse -Force $tmp
}
