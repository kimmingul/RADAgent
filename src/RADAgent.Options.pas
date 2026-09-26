unit RADAgent.Options;

{ omp.exe location, temp/log paths and the omp command line. No ToolsAPI. }

interface

const
  { The --config RADAgent passes to every main omp: rad.* host tools as inline xd:// devices. }
  OmpHostConfig = '{"tools":{"xdevInlineDevices":["rad.*"]}}';

function OmpExecutable: string;
function AgentTempRoot: string;
{ AgentTempRoot + Name with this process's id before the extension ("omp-1234.stderr.log"). Two
  IDEs (32- and 64-bit, or two of one kind) each run their own omp; a shared file would be held open
  by the other one's child. Files of IDEs that are gone are removed on first use. }
function ProcessTempFile(const Name: string): string;
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
  System.SysUtils, System.IOUtils, System.SyncObjs, Winapi.Windows, RADAgent.Lang;

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
  Result := Result + 'RADAgent\';
end;

var
  GPruned: Boolean;

{ Deletes other IDEs' per-process files; a file still held open by a running omp stays. }
procedure PruneProcessFiles;
var
  Path, Own: string;
begin
  GPruned := True;
  if not DirectoryExists(AgentTempRoot) then
    Exit;
  Own := '-p' + IntToStr(GetCurrentProcessId) + '.';
  for Path in TDirectory.GetFiles(AgentTempRoot, '*-p*.*') do
    if not ExtractFileName(Path).Contains(Own) then
      System.SysUtils.DeleteFile(Path);
  { The shared names versions before per-process files used. }
  for Path in ['omp.stderr.log', 'omp-host.yml', 'project-guide.md', 'btw-guide.md',
    'omp-probe.yml', 'omp-probe.stderr.log'] do
    System.SysUtils.DeleteFile(AgentTempRoot + Path);
end;

function ProcessTempFile(const Name: string): string;
var
  Dot: Integer;
begin
  if not GPruned then
    PruneProcessFiles;
  Dot := Pos('.', Name);
  if Dot = 0 then
    Dot := Length(Name) + 1;
  Result := AgentTempRoot + Copy(Name, 1, Dot - 1) + '-p' + IntToStr(GetCurrentProcessId) +
    Copy(Name, Dot, MaxInt);
end;

function OmpStderrLog: string;
begin
  Result := ProcessTempFile('omp.stderr.log');
end;

procedure AppendRpcLog(const Line: string);
const
  MaxLogBytes = 20 * 1024 * 1024;
var
  Root, LogPath, BackupPath: string;
begin
  GLogGate.Acquire;
  try
    try
      Root := AgentTempRoot;
      ForceDirectories(Root);
      LogPath := Root + 'rpc.log';
      BackupPath := Root + 'rpc.1.log';
      if FileExists(LogPath) and (TFile.GetSize(LogPath) >= MaxLogBytes) then
      begin
        if FileExists(BackupPath) then
          System.SysUtils.DeleteFile(BackupPath);
        if not MoveFileEx(PChar(LogPath), PChar(BackupPath), MOVEFILE_REPLACE_EXISTING) then
        begin
          System.SysUtils.DeleteFile(BackupPath);
          System.SysUtils.RenameFile(LogPath, BackupPath);
        end;
      end;
      TFile.AppendAllText(LogPath, Line + sLineBreak, TEncoding.UTF8);
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
  Result := Tr('options.pipeClosed');
  try
    if not FileExists(StderrPath) then
      Exit;
    Lines := TFile.ReadAllLines(StderrPath, TEncoding.UTF8);
  except
    Exit;
  end;
  for Index := High(Lines) downto 0 do
    if Trim(Lines[Index]) <> '' then
      Exit(TrF('options.pipeClosedDetail', [Trim(Lines[Index])]));
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
