unit DelphiAgent.Options;

{ omp.exe location, temp/log paths and the omp command line. No ToolsAPI. }

interface

const
  { The --config DelphiAgent passes to every main omp: rad.* host tools as inline xd:// devices. }
  OmpHostConfig = '{"tools":{"xdevInlineDevices":["rad.*"]}}';

function OmpExecutable: string;
function AgentTempRoot: string;
function OmpStderrLog: string;
procedure AppendRpcLog(const Line: string);
{ Why an omp child ended early: the last line it wrote to StderrPath (e.g. "Error: unknown flag"). }
function ChildExitReason(const StderrPath: string): string;
{ One command-line argument in quotes, safe for a trailing backslash (C:\dir\). }
function QuoteArg(const Value: string): string;
{ Configs: --config files in order (empty entries skipped); AppendPrompt: file whose text omp
  appends to its system prompt; ExtraArgs: appended verbatim. }
function BuildOmpCommandLine(const Executable, WorkDir: string; const Configs: array of string;
  const AppendPrompt, ExtraArgs: string): string;

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

function ChildExitReason(const StderrPath: string): string;
var
  Lines: TArray<string>;
  Index: Integer;
begin
  Result := '파이프가 닫혔습니다';
  try
    if not FileExists(StderrPath) then
      Exit;
    Lines := TFile.ReadAllLines(StderrPath, TEncoding.UTF8);
  except
    Exit;
  end;
  for Index := High(Lines) downto 0 do
    if Trim(Lines[Index]) <> '' then
      Exit(Result + ': ' + Trim(Lines[Index]));
end;

function QuoteArg(const Value: string): string;
var
  Body: string;
begin
  Body := StringReplace(Value, '"', '\"', [rfReplaceAll]);
  { A backslash right before the closing quote would escape it. }
  if Body.EndsWith('\') then
    Body := Body + '\';
  Result := '"' + Body + '"';
end;

function BuildOmpCommandLine(const Executable, WorkDir: string; const Configs: array of string;
  const AppendPrompt, ExtraArgs: string): string;
var
  Config: string;
begin
  Result := QuoteArg(Executable) + ' --mode rpc --cwd ' + QuoteArg(WorkDir);
  for Config in Configs do
    if Config <> '' then
      Result := Result + ' --config ' + QuoteArg(Config);
  if AppendPrompt <> '' then
    Result := Result + ' --append-system-prompt ' + QuoteArg(AppendPrompt);
  if Trim(ExtraArgs) <> '' then
    Result := Result + ' ' + Trim(ExtraArgs);
end;

initialization
  GLogGate := TCriticalSection.Create;

finalization
  FreeAndNil(GLogGate);

end.
