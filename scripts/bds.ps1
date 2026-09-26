# Finds the RAD Studio to build with. Dot-source it after setting $Version ('' = %BDS%, else the
# newest installed release). Sets $Version, $bds (root folder), $suffix (package suffix) and
# $rsvars. Supported: 21.0 = 10.4 Sydney, 22.0 = 11 Alexandria, 23.0 = 12 Athens, 37.0 = 13.
# With $BdsFunctionsOnly = $true it only defines the helpers (RootOf, InstalledBdsVersions).
$suffixes = @{ '21.0' = '270'; '22.0' = '280'; '23.0' = '290'; '37.0' = '370' }
$key = 'HKLM:\SOFTWARE\WOW6432Node\Embarcadero\BDS'

function Fail([string]$Message) {
  Write-Host "[RADAgent] $Message"
  exit 1
}

function RootOf([string]$Ver) {
  $item = Get-ItemProperty -Path (Join-Path $key $Ver) -Name RootDir -ErrorAction SilentlyContinue
  if ($item) { return $item.RootDir.TrimEnd('\') }
  return ''
}

# Supported releases installed on this PC, oldest first.
function InstalledBdsVersions {
  return @(Get-ChildItem -Path $key -ErrorAction SilentlyContinue |
    Where-Object { $suffixes.ContainsKey($_.PSChildName) -and (RootOf $_.PSChildName) } |
    Sort-Object { [double]$_.PSChildName } | ForEach-Object { $_.PSChildName })
}

if (Get-Variable -Name BdsFunctionsOnly -ValueOnly -ErrorAction SilentlyContinue) { return }

$bds = ''
if ($Version) {
  $bds = RootOf $Version
  if (-not $bds) { Fail "RAD Studio $Version is not installed (no $key\$Version\RootDir)." }
} elseif ($env:BDS -and (Test-Path (Join-Path $env:BDS 'bin\rsvars.bat'))) {
  $bds = $env:BDS.TrimEnd('\')
  $matchedVer = $null
  foreach ($ver in InstalledBdsVersions) {
    $root = RootOf $ver
    if ($root -and ($root.TrimEnd('\') -ieq $bds)) {
      $matchedVer = $ver
      break
    }
  }
  if (-not $matchedVer) {
    Fail "BDS path '$bds' does not match any registered RAD Studio installation in $key."
  }
  $Version = $matchedVer
} else {
  $installed = @(InstalledBdsVersions)
  if ($installed.Count -eq 0) { Fail 'No supported RAD Studio found (10.4 Sydney or later).' }
  $Version = $installed[-1]
  $bds = RootOf $Version
}
if (-not $suffixes.ContainsKey($Version)) {
  Fail "BDS $Version is not supported. Supported: 21.0 (10.4), 22.0 (11), 23.0 (12), 37.0 (13)."
}
$suffix = $suffixes[$Version]
$rsvars = Join-Path $bds 'bin\rsvars.bat'
if (-not (Test-Path $rsvars)) { Fail "rsvars.bat not found: $rsvars" }
