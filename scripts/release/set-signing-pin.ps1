<#
.SYNOPSIS
Stores (or removes, -Remove) the SafeNet token PIN for unattended signing.

.DESCRIPTION
Run once, interactively, as the user who signs. The PIN is read without echo, kept only in
Windows Credential Manager ('RADAgent.CodeSign.TokenPin', current user), and checked at once by
unlocking the token. Run again after a PIN change.
#>
[CmdletBinding()]
param([switch] $Remove)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'signing.ps1')
if ($Remove) {
    [NanumSpace.Signing.CredentialStore]::Delete($SigningPinTarget)
    if (Test-Path -LiteralPath $SigningFailureMarker) { Remove-Item -LiteralPath $SigningFailureMarker -Force }
    return [pscustomobject]@{ Stored = $false; Target = $SigningPinTarget }
}
$pin = Read-Host -AsSecureString -Prompt 'SafeNet token PIN (not echoed)'
if ($pin.Length -eq 0) { throw 'Empty PIN.' }
[NanumSpace.Signing.CredentialStore]::Write($SigningPinTarget, $pin)
$pin.Dispose()
try {
    Unlock-SigningToken -Force
} catch {
    [NanumSpace.Signing.CredentialStore]::Delete($SigningPinTarget)
    throw ('The token rejected the PIN; it was not kept. ' + $_.Exception.Message)
}
[pscustomobject]@{ Stored = $true; Target = $SigningPinTarget; Verified = $true }
