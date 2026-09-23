unit DelphiAgent.Options;

{ omp.exe path, model, and provider. Defaults stay on the local omp the user already configured. }

interface

function OmpExecutable: string;
function OmpModel: string;
function OmpProvider: string;
function AgentTempRoot: string;
function OmpStderrLog: string;
procedure AppendRpcLog(const Line: string);
function BuildOmpCommandLine(const Executable, WorkDir, Model, Provider: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows;

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

function OmpModel: string;
begin
  Result := '';
end;

function OmpProvider: string;
begin
  Result := '';
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
  try
    ForceDirectories(AgentTempRoot);
    TFile.AppendAllText(AgentTempRoot + 'rpc.log', Line + sLineBreak, TEncoding.UTF8);
  except
  end;
end;

function QuoteArg(const Value: string): string;
begin
  Result := '"' + StringReplace(Value, '"', '\"', [rfReplaceAll]) + '"';
end;

function BuildOmpCommandLine(const Executable, WorkDir, Model, Provider: string): string;
begin
  Result := QuoteArg(Executable) + ' --mode rpc --cwd ' + QuoteArg(WorkDir);
  if Model <> '' then
    Result := Result + ' --model ' + QuoteArg(Model);
  if Provider <> '' then
    Result := Result + ' --provider ' + QuoteArg(Provider);
end;

end.
