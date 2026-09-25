# Dot-sourced helpers for code signing with the Nanum Space EV certificate on the SafeNet USB
# token. Same setup as the other Nanum Space products on this PC:
#   - the certificate is in CurrentUser\My (SafeNet Authentication Client puts it there);
#   - the token PIN is in Windows Credential Manager under 'RADAgent.CodeSign.TokenPin'
#     (set-signing-pin.ps1), never on a command line, in a file or in a log;
#   - SAC "Single Logon" (enable-sac-single-logon.ps1) keeps the token unlocked for the logon
#     session, so signtool.exe and Inno Setup's SignTool run without a PIN prompt.

$SigningThumbprint = '3CE49DE1124F325082FA90BDE4944756D1626251'
# GlobalSign RFC 3161 (the issuing CA). signtool rejects GlobalSign's HTTPS endpoints here as
# "Invalid Timestamp URL"; the timestamp token is itself signed, so HTTP is the usual transport.
$SigningTimestampUrl = 'http://timestamp.globalsign.com/tsa/r6advanced1'
$SigningPinTarget = 'RADAgent.CodeSign.TokenPin'
$SigningFailureMarker = Join-Path $env:LOCALAPPDATA 'RADAgent\signing-unlock-failure.json'

if (-not ('NanumSpace.Signing.CredentialStore' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security;
namespace NanumSpace.Signing {
public static class CredentialStore {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
        public uint Flags; public uint Type; public string TargetName; public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist;
        public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredReadW(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredWriteW(ref CREDENTIAL credential, uint flags);
    [DllImport("advapi32", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredDeleteW(string target, uint type, uint flags);
    [DllImport("advapi32", SetLastError = true)] static extern void CredFree(IntPtr buffer);
    const uint CRED_TYPE_GENERIC = 1, CRED_PERSIST_LOCAL_MACHINE = 2;

    public static bool Exists(string target) {
        IntPtr p; if (!CredReadW(target, CRED_TYPE_GENERIC, 0, out p)) return false; CredFree(p); return true;
    }
    // The secret as a SecureString; the unmanaged copy is zeroed before release.
    public static SecureString Read(string target) {
        IntPtr p;
        if (!CredReadW(target, CRED_TYPE_GENERIC, 0, out p)) throw new InvalidOperationException("Signing PIN credential not found: " + target);
        try {
            var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
            var s = new SecureString();
            int chars = (int)c.CredentialBlobSize / 2;
            for (int i = 0; i < chars; i++) s.AppendChar((char)Marshal.ReadInt16(c.CredentialBlob, i * 2));
            for (int i = 0; i < (int)c.CredentialBlobSize; i++) Marshal.WriteByte(c.CredentialBlob, i, 0);
            s.MakeReadOnly();
            return s;
        } finally { CredFree(p); }
    }
    public static void Write(string target, SecureString secret) {
        IntPtr blob = Marshal.SecureStringToGlobalAllocUnicode(secret);
        try {
            var c = new CREDENTIAL { Type = CRED_TYPE_GENERIC, TargetName = target, Persist = CRED_PERSIST_LOCAL_MACHINE,
                CredentialBlob = blob, CredentialBlobSize = (uint)(secret.Length * 2), UserName = "token", Comment = "Nanum Space code-signing token PIN" };
            if (!CredWriteW(ref c, 0)) throw new InvalidOperationException("CredWrite failed: " + Marshal.GetLastWin32Error());
        } finally { Marshal.ZeroFreeGlobalAllocUnicode(blob); }
    }
    public static void Delete(string target) { CredDeleteW(target, CRED_TYPE_GENERIC, 0); }
}
}
'@
}

function Get-SignTool {
    $tool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
    if (-not $tool) { throw 'signtool.exe from the Windows 10/11 SDK is required.' }
    return $tool
}

function Get-SigningCertificate {
    $store = [Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
    $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    try {
        $found = @($store.Certificates | Where-Object { $_.Thumbprint -ceq $SigningThumbprint })
        if ($found.Count -ne 1) {
            throw 'The Nanum Space signing certificate is not in CurrentUser\My. Plug in the USB token (SafeNet Authentication Client).'
        }
        return $found[0]
    } finally { $store.Close() }
}

# Authenticates the token once for this logon session with the stored PIN. A failure leaves a
# marker so that repeated runs cannot use up the token's PIN retry counter.
function Unlock-SigningToken([switch] $Force) {
    if (-not [NanumSpace.Signing.CredentialStore]::Exists($SigningPinTarget)) { return }
    if ((Test-Path -LiteralPath $SigningFailureMarker) -and -not $Force) {
        $marker = Get-Content -LiteralPath $SigningFailureMarker -Raw | ConvertFrom-Json
        if (([DateTime]::UtcNow - [DateTime]::Parse($marker.FailedUtc).ToUniversalTime()).TotalMinutes -lt 60) {
            throw 'A token unlock failed within the last hour; check the stored PIN (set-signing-pin.ps1) and retry with -Force.'
        }
    }
    $certificate = Get-SigningCertificate
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
    if ($rsa -isnot [Security.Cryptography.RSACng]) { throw 'The signing key is not a CNG key (SafeNet Key Storage Provider expected).' }
    $secure = [NanumSpace.Signing.CredentialStore]::Read($SigningPinTarget)
    $blob = $null
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secure)
        try {
            $blob = [byte[]]::new(($secure.Length + 1) * 2)
            [Runtime.InteropServices.Marshal]::Copy($ptr, $blob, 0, $secure.Length * 2)
        } finally { [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr) }
        # NCRYPT_PIN_PROPERTY: the key storage provider uses it instead of its PIN dialog.
        $rsa.Key.SetProperty([Security.Cryptography.CngProperty]::new('SmartCardPin', $blob, [Security.Cryptography.CngPropertyOptions]::None))
        try {
            $probe = [Text.Encoding]::ASCII.GetBytes('RADAgent signing token unlock probe')
            $signature = $rsa.SignData($probe, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $public = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
            try {
                if (-not $public.VerifyData($probe, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
                    throw 'Probe signature did not verify against the certificate.'
                }
            } finally { $public.Dispose() }
        } catch {
            $null = New-Item -ItemType Directory -Path (Split-Path $SigningFailureMarker) -Force
            [IO.File]::WriteAllText($SigningFailureMarker, (@{ FailedUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json))
            throw ('Token unlock failed (wrong PIN, token absent, or provider refused the PIN): ' + $_.Exception.Message)
        }
        if (Test-Path -LiteralPath $SigningFailureMarker) { Remove-Item -LiteralPath $SigningFailureMarker -Force }
    } finally {
        if ($blob) { [Array]::Clear($blob, 0, $blob.Length) }
        $secure.Dispose()
        $rsa.Dispose()
    }
}

# Runs signtool without a shell; its output (certificate details) is not logged.
function Invoke-SignTool([string[]] $Arguments, [int] $TimeoutSeconds = 180) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Get-SignTool
    $info.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '["\x00-\x1f]' -or $_.EndsWith('\')) { throw 'Invalid signing argument.' }
        '"' + $_ + '"'
    }) -join ' ')
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'signtool did not start.' }
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
        $stderr = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); throw 'signtool timed out.' }
        $null = $stdout.Wait(5000); $null = $stderr.Wait(5000)
        if ($process.ExitCode -ne 0) { throw ('signtool failed: ' + $Arguments[0] + ' ' + $Arguments[-1]) }
    } finally { $process.Dispose() }
}

function Test-NanumSignature([string] $Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    return $signature.Status -eq 'Valid' -and $null -ne $signature.TimeStamperCertificate -and
        $signature.SignerCertificate.Thumbprint -ceq $SigningThumbprint
}

# Signs and timestamps Path (SHA-256), then checks the signature and the timestamp.
function Invoke-CodeSign([string] $Path) {
    Invoke-SignTool @('sign', '/q', '/s', 'My', '/sha1', $SigningThumbprint, '/fd', 'SHA256',
        '/tr', $SigningTimestampUrl, '/td', 'SHA256', $Path)
    Invoke-SignTool @('verify', '/q', '/pa', '/tw', $Path)
    if (-not (Test-NanumSignature $Path)) { throw "Signature or timestamp missing after signing: $Path" }
}

# The command Inno Setup runs for the setup and its uninstaller ($f = the file to sign).
function Get-InnoSignCommand {
    # $q is Inno Setup's quote character inside a SignTool definition.
    return ('$q{0}$q sign /q /s My /sha1 {1} /fd SHA256 /tr {2} /td SHA256 $f' -f (Get-SignTool), $SigningThumbprint, $SigningTimestampUrl)
}
