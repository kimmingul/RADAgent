# Copies the chat page (src\chat) and the matching WebView2Loader.dll next to the built BPL:
#   <BplDir>\RADAgent\chat\*  and  <BplDir>\RADAgent\WebView2Loader.dll
# The BPL loads both from its own folder at run time.
param(
  [Parameter(Mandatory = $true)][string]$BplDir,
  [Parameter(Mandatory = $true)][ValidateSet('x86', 'x64')][string]$Arch
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'fetch-webview2.ps1')
$out = Join-Path $BplDir 'RADAgent'
$chat = Join-Path $out 'chat'
New-Item -ItemType Directory -Force -Path $chat | Out-Null
Copy-Item -Force -Recurse -Path (Join-Path $root 'src\chat\*') -Destination $chat
$loader = Join-Path $root "third_party\webview2\$Arch\WebView2Loader.dll"
try {
  Copy-Item -Force -Path $loader -Destination (Join-Path $out 'WebView2Loader.dll')
} catch {
  # The IDE keeps the loader loaded; an identical file already in place is fine.
  $dst = Join-Path $out 'WebView2Loader.dll'
  if (-not (Test-Path $dst) -or
      (Get-FileHash $dst).Hash -ne (Get-FileHash $loader).Hash) { throw }
}
Write-Host "[RADAgent] 채팅 페이지와 WebView2 로더 배치: $out"
