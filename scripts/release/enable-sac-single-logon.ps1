<#
.SYNOPSIS
Turns on SafeNet Authentication Client "Single Logon": the token PIN is asked at most once per
Windows logon session. Writes HKLM (asks for elevation). Applies after logoff/logon or a SAC
service restart. With the stored PIN (set-signing-pin.ps1) signing runs unattended.
#>
[CmdletBinding()]
param([ValidateRange(0, 86400)][int] $TimeoutSeconds = 0)
$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$key = 'HKLM:\SOFTWARE\SafeNet\Authentication\SAC\General'
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-TimeoutSeconds', $TimeoutSeconds)
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Elevated configuration failed with exit code $($process.ExitCode)." }
} else {
    if (-not (Test-Path 'HKLM:\SOFTWARE\SafeNet\Authentication\SAC')) { throw 'SafeNet Authentication Client is not installed.' }
    $null = New-Item -Path $key -Force
    Set-ItemProperty -Path $key -Name SingleLogon -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name SingleLogonTimeout -Value $TimeoutSeconds -Type DWord
}
$value = Get-ItemProperty -Path $key
[pscustomobject]@{ SingleLogon = $value.SingleLogon; SingleLogonTimeout = $value.SingleLogonTimeout }
