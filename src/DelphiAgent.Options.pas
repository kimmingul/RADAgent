unit DelphiAgent.Options;

{ omp.exe location, temp/log paths and the omp command line. No ToolsAPI. }

interface

function OmpExecutable: string;
function AgentTempRoot: string;
function OmpStderrLog: string;
procedure AppendRpcLog(const Line: string);
{ ConfigOverlay: optional --config file; ExtraArgs: appended verbatim. }
function BuildOmpCommandLine(const Executable, WorkDir, ConfigOverlay, ExtraArgs: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.SyncObjs, Winapi.Windows;

var
  { The RPC reader thread and the main thread both log; unsynchronised appends drop lines. }
  GLogGate: TCriticalSection;

function OmpExecutable: string;
var
  Buf: array[0..MAX_PATH] of Char;
  Part: PChar;
  Local: string;
begin
  Result := 'omp';
  Part := nil;
  if SearchPath(nil, 'omp.exe', nil, MAX_PATH, Buf, Part) > 0 then
    Exit(PChar(@Buf[0]));
  Local := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) +
    'omp\omp.exe';
  if FileExists(Local) then
    Result := Local;
end;

function AgentTempRoot: string;
var
  Buf: array[0..MAX_PATH] of Char;
  Count: DWORD;
begin
  Count := GetTempPath(MAX_PATH, Buf);
  if Count = 0 then
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
  else
    Result := IncludeTrailingPathDelimiter(string(Buf));
  Result := Result + 'DelphiAgent\';
end;

function OmpStderrLog: string;
begin
  Result := AgentTempRoot + 'omp.stderr.log';
end;

procedure AppendRpcLog(const Line: string);
begin
  GLogGate.Acquire;
  try
    try
      ForceDirectories(AgentTempRoot);
      TFile.AppendAllText(AgentTempRoot + 'rpc.log', Line + sLineBreak, TEncoding.UTF8);
    except
    end;
  finally
    GLogGate.Release;
  end;
end;

function QuoteArg(const Value: string): string;
begin
  Result := '"' + StringReplace(Value, '"', '\"', [rfReplaceAll]) + '"';
end;

function BuildOmpCommandLine(const Executable, WorkDir, ConfigOverlay, ExtraArgs: string): string;
begin
  Result := QuoteArg(Executable) + ' --mode rpc --cwd ' + QuoteArg(WorkDir);
  if ConfigOverlay <> '' then
    Result := Result + ' --config ' + QuoteArg(ConfigOverlay);
  if Trim(ExtraArgs) <> '' then
    Result := Result + ' ' + Trim(ExtraArgs);
end;

initialization
  GLogGate := TCriticalSection.Create;

finalization
  FreeAndNil(GLogGate);

end.
