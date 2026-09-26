unit RADAgent.AgentVersion;

{ RAD Agent's own version, read from the BPL's version info (set once in RADAgent.dproj), the
  IDE it runs in, and where its release notes are. No ToolsAPI, no VCL. }

interface

{ "1.2.5"; a fourth part only when it is not 0. '' when the BPL has no version info. }
function AgentVersion: string;
{ "64-bit" or "32-bit": the IDE this BPL was built for. }
function AgentBitness: string;
{ The running bds.exe, "37.0.57242.3601"; '' when it cannot be read. }
function IdeVersion: string;
function ReleaseNotesUrl: string;
{ "RAD Agent 1.2.5 (64-bit) · omp 18.2.11"; OmpVersion '' shows "?". }
function ShortVersionLine(const OmpVersion: string): string;
{ One line for bug reports and the log, the same in every language: the short line and
  " · BDS 37.0.57242.3601". }
function VersionLine(const OmpVersion: string): string;

implementation

uses
  System.SysUtils, Winapi.Windows;

const
  ReleasesUrl = 'https://github.com/kimmingul/RADAgent/releases';

var
  GAgentVersion: string;
  GAgentRead: Boolean;

{ The four numbers of FileName's fixed version info; False without one. }
function FileVersionParts(const FileName: string; out Parts: array of Word): Boolean;
var
  Size, Handle, InfoSize: DWORD;
  Buffer: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := False;
  Size := GetFileVersionInfoSize(PChar(FileName), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buffer, Size);
  if not GetFileVersionInfo(PChar(FileName), 0, Size, Pointer(Buffer)) or
    not VerQueryValue(Pointer(Buffer), '\', Pointer(Info), InfoSize) or (InfoSize < SizeOf(Info^)) then
    Exit;
  Parts[0] := HiWord(Info.dwFileVersionMS);
  Parts[1] := LoWord(Info.dwFileVersionMS);
  Parts[2] := HiWord(Info.dwFileVersionLS);
  Parts[3] := LoWord(Info.dwFileVersionLS);
  Result := True;
end;

function AgentVersion: string;
var
  Parts: array[0..3] of Word;
begin
  if not GAgentRead then
  begin
    GAgentRead := True;
    GAgentVersion := '';
    if FileVersionParts(GetModuleName(HInstance), Parts) then
    begin
      GAgentVersion := Format('%d.%d.%d', [Parts[0], Parts[1], Parts[2]]);
      if Parts[3] <> 0 then
        GAgentVersion := GAgentVersion + '.' + IntToStr(Parts[3]);
    end;
  end;
  Result := GAgentVersion;
end;

function AgentBitness: string;
begin
{$IFDEF WIN64}
  Result := '64-bit';
{$ELSE}
  Result := '32-bit';
{$ENDIF}
end;

function IdeVersion: string;
var
  Parts: array[0..3] of Word;
begin
  Result := '';
  if FileVersionParts(GetModuleName(0), Parts) then
    Result := Format('%d.%d.%d.%d', [Parts[0], Parts[1], Parts[2], Parts[3]]);
end;

function ReleaseNotesUrl: string;
begin
  if AgentVersion = '' then
    Result := ReleasesUrl
  else
    Result := ReleasesUrl + '/tag/v' + AgentVersion;
end;

function OrUnknown(const Value: string): string;
begin
  Result := Value;
  if Result = '' then
    Result := '?';
end;

function ShortVersionLine(const OmpVersion: string): string;
begin
  Result := 'RAD Agent ' + OrUnknown(AgentVersion) + ' (' + AgentBitness + ') · omp ' + OrUnknown(OmpVersion);
end;

function VersionLine(const OmpVersion: string): string;
begin
  Result := ShortVersionLine(OmpVersion) + ' · BDS ' + OrUnknown(IdeVersion);
end;

end.
