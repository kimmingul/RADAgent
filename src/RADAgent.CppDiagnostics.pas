unit RADAgent.CppDiagnostics;

{ Compiler errors for a failed C++Builder build. The IDE reports C++ build errors only in the
  Messages view, which has no public reading API, and Error Insight has none for C++. So after a
  failed build this unit compiles the project's changed .cpp files once more with the platform's
  compiler (bcc64x, bcc64 or bcc32c) and reads the errors it prints. Main thread only. }

interface

uses
  ToolsAPI, RADAgent.RpcProtocol;

{ Errors from the .cpp files changed since the last good build (all of them when unknown). }
function CppBuildErrors(const Project: IOTAProject; const PlatformName: string): TArray<TAgentCompileError>;
{ Call after a successful build: later checks start from here. }
procedure NoteCppBuildOk;
{ Parses compiler output ("Error E1525 MainForm.cpp 33(10): expected expression"). Dir resolves
  relative file names. }
function ParseCppErrors(const Output, Dir: string): TArray<TAgentCompileError>;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  RADAgent.ProcessRun, RADAgent.Options;

const
  MaxFiles = 12;
  MaxErrors = 30;

var
  GLastOk: TDateTime;

procedure NoteCppBuildOk;
begin
  GLastOk := Now;
end;

function ParseCppErrors(const Output, Dir: string): TArray<TAgentCompileError>;
var
  Line, FileName: string;
  Match: TMatch;
  Item: TAgentCompileError;
begin
  Result := nil;
  for Line in Output.Split([#10]) do
  begin
    Match := TRegEx.Match(Line.TrimRight, '^(?:Error|Fatal)\s+[EF]?\d*\s+(.+?)\s+(\d+)(?:\((\d+)\))?:\s*(.+)$');
    if not Match.Success then
      Match := TRegEx.Match(Line.TrimRight, '^(.+?):(\d+):(\d+):\s*(?:fatal )?error:\s*(.+)$');
    if not Match.Success then
      Continue;
    FileName := Match.Groups[1].Value;
    if not TPath.IsPathRooted(FileName) then
      FileName := TPath.Combine(Dir, FileName);
    Item.FileName := FileName;
    Item.Line := StrToIntDef(Match.Groups[2].Value, 0);
    Item.Col := StrToIntDef(Match.Groups[3].Value, 0);
    Item.Msg := Match.Groups[4].Value;
    Result := Result + [Item];
  end;
end;

function Compiler(const PlatformName: string): string;
var
  Bds: string;
begin
  Bds := ExcludeTrailingPathDelimiter(GetEnvironmentVariable('BDS'));
  if SameText(PlatformName, 'Win64x') then
    Result := Bds + '\bin64\bcc64x.exe'
  else if SameText(PlatformName, 'Win64') then
    Result := Bds + '\bin\bcc64.exe'
  else if SameText(PlatformName, 'Win32') then
    Result := Bds + '\bin\bcc32c.exe'
  else
    Result := '';
  if (Result <> '') and not FileExists(Result) then
    Result := '';
end;

{ $(BDS), $(BDSINCLUDE), $(BDSCOMMONDIR), $(Platform), $(Config) and environment variables;
  '' when something stays unknown. }
function Expand(const Value, PlatformName, ConfigName: string): string;
var
  Match: TMatch;
  Name, Replacement: string;
begin
  Result := Value;
  for Match in TRegEx.Matches(Value, '\$\(([^)]+)\)') do
  begin
    Name := Match.Groups[1].Value;
    if SameText(Name, 'BDSINCLUDE') then
      Replacement := ExcludeTrailingPathDelimiter(GetEnvironmentVariable('BDS')) + '\include'
    else if SameText(Name, 'Platform') then
      Replacement := PlatformName
    else if SameText(Name, 'Config') then
      Replacement := ConfigName
    else
      Replacement := GetEnvironmentVariable(Name);
    if Replacement = '' then
      Exit('');
    Result := StringReplace(Result, Match.Value, Replacement, [rfIgnoreCase]);
  end;
end;

function ProjectArgs(const Project: IOTAProject; const PlatformName, Dir: string): string;
var
  Configs: IOTAProjectOptionsConfigurations;
  Config: IOTABuildConfiguration;
  Item, Value: string;
begin
  Result := ' -tW -tU -I"' + Dir + '"';
  if not Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    Exit;
  Config := Configs.ActiveConfiguration;
  if Config = nil then
    Exit;
  if Config.PlatformConfiguration[PlatformName] <> nil then
    Config := Config.PlatformConfiguration[PlatformName];
  for Item in Config.GetValue('IncludePath', True).Split([';']) do
  begin
    Value := Expand(Trim(Item), PlatformName, Configs.ActiveConfigurationName);
    if (Value <> '') and not Value.Contains('$(') then
      Result := Result + ' -I"' + TPath.Combine(Dir, Value) + '"';
  end;
  for Item in Config.GetValue('Defines', True).Split([';']) do
    if (Trim(Item) <> '') and not Item.Contains('$(') then
      Result := Result + ' -D' + Trim(Item);
end;

{ The project's .cpp files changed since the last good build, plus the ones including a changed
  header; all of them when there was no good build yet. At most MaxFiles. }
function ChangedSources(const Project: IOTAProject): TArray<string>;
var
  Index: Integer;
  FileName, Header: string;
  All, Headers: TArray<string>;
begin
  Result := nil;
  All := nil;
  Headers := nil;
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    FileName := Project.GetModule(Index).FileName;
    if SameText(ExtractFileExt(FileName), '.cpp') and FileExists(FileName) then
    begin
      All := All + [FileName];
      Header := ChangeFileExt(FileName, '.h');
      if (GLastOk > 0) and FileExists(Header) and (TFile.GetLastWriteTime(Header) > GLastOk) then
        Headers := Headers + [ExtractFileName(Header)];
    end;
  end;
  if FileExists(ChangeFileExt(Project.FileName, '.cpp')) and
    (IndexStr(ChangeFileExt(Project.FileName, '.cpp'), All) < 0) then
    All := All + [ChangeFileExt(Project.FileName, '.cpp')];
  for FileName in All do
  begin
    if Length(Result) >= MaxFiles then
      Break;
    if GLastOk = 0 then
      Result := Result + [FileName]
    else if TFile.GetLastWriteTime(FileName) > GLastOk then
      Result := Result + [FileName]
    else
      for Header in Headers do
        if TFile.ReadAllText(FileName).Contains('"' + Header + '"') then
        begin
          Result := Result + [FileName];
          Break;
        end;
  end;
end;

function CppBuildErrors(const Project: IOTAProject; const PlatformName: string): TArray<TAgentCompileError>;
var
  Exe, Dir, Args, Output, FileName, ObjFile: string;
begin
  Result := nil;
  Exe := Compiler(PlatformName);
  if Exe = '' then
    Exit;
  Dir := ExtractFileDir(Project.FileName);
  Args := ProjectArgs(Project, PlatformName, Dir);
  ObjFile := ProcessTempFile('cppcheck.o');
  for FileName in ChangedSources(Project) do
  begin
    RunCaptured('"' + Exe + '"' + Args + ' -c -o "' + ObjFile + '" "' + FileName + '"', Dir, Output, 120000);
    Result := Result + ParseCppErrors(Output, ExtractFileDir(FileName));
    if Length(Result) >= MaxErrors then
      Break;
  end;
  System.SysUtils.DeleteFile(ObjFile);
end;

end.
