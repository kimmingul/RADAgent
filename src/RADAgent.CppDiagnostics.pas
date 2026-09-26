unit RADAgent.CppDiagnostics;

{ Compiler errors for a failed C++Builder build. The IDE reports C++ build errors only in the
  Messages view, which has no public reading API, and Error Insight has none for C++. So after a
  failed build this unit compiles the project's changed .cpp files once more with the platform's
  compiler (bcc64x, bcc64 or bcc32c) and reads the errors it prints. Main thread only. }

interface

uses
  ToolsAPI, RADAgent.RpcProtocol;

{ Errors from the .cpp files changed since the last good build (all of them when unknown). }
function CppBuildErrors(const Project: IOTAProject; const PlatformName: string;
  const ConfigName: string = ''): TArray<TAgentCompileError>;
{ The platform's C++ compiler (bcc64x for Win64x, bcc64, bcc32c), '' when there is none. }
function Compiler(const PlatformName: string): string;
{ Include folders (absolute) and defines of the active configuration for PlatformName. }
procedure ProjectOptions(const Project: IOTAProject; const PlatformName: string;
  out Includes, Defines: TArray<string>);
{ Call after a successful build: later checks start from here. }
procedure NoteCppBuildOk(const ProjectFile, ConfigName, PlatformName: string);
{ Parses compiler output ("Error E1525 MainForm.cpp 33(10): expected expression"). Dir resolves
  relative file names. }
function ParseCppErrors(const Output, Dir: string): TArray<TAgentCompileError>;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections, RADAgent.ProcessRun, RADAgent.Options;

const
  MaxFiles = 12;
  MaxErrors = 30;

var
  GLastOk: TDictionary<string, TDateTime>;

function TargetKey(const ProjectFile, Config, Platform: string): string;
begin
  Result := LowerCase(ProjectFile + '|' + Config + '|' + Platform);
end;

procedure NoteCppBuildOk(const ProjectFile, ConfigName, PlatformName: string);
begin
  if GLastOk <> nil then
    GLastOk.AddOrSetValue(TargetKey(ProjectFile, ConfigName, PlatformName), Now);
end;

function LastOkTime(const ProjectFile, ConfigName, PlatformName: string): TDateTime;
begin
  Result := 0;
  if GLastOk <> nil then
    GLastOk.TryGetValue(TargetKey(ProjectFile, ConfigName, PlatformName), Result);
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

procedure ProjectOptions(const Project: IOTAProject; const PlatformName: string;
  out Includes, Defines: TArray<string>);
var
  Configs: IOTAProjectOptionsConfigurations;
  Config: IOTABuildConfiguration;
  Item, Value, Dir: string;
begin
  Dir := ExtractFileDir(Project.FileName);
  Includes := [Dir];
  Defines := nil;
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
      Includes := Includes + [TPath.Combine(Dir, Value)];
  end;
  for Item in Config.GetValue('Defines', True).Split([';']) do
    if (Trim(Item) <> '') and not Item.Contains('$(') then
      Defines := Defines + [Trim(Item)];
end;

function ProjectArgs(const Project: IOTAProject; const PlatformName: string): string;
var
  Includes, Defines: TArray<string>;
  Item: string;
begin
  ProjectOptions(Project, PlatformName, Includes, Defines);
  Result := ' -tW -tU';
  for Item in Includes do
    Result := Result + ' -I"' + Item + '"';
  for Item in Defines do
    Result := Result + ' -D' + Item;
end;

{ The project's .cpp files changed since the last good build, plus the ones including a changed
  header; all of them when there was no good build yet. At most MaxFiles. }
function ChangedSources(const Project: IOTAProject; const PlatformName, ConfigName: string): TArray<string>;
var
  Index: Integer;
  FileName, Header, ActiveConfig: string;
  All, Headers: TArray<string>;
  LastOk: TDateTime;
  Configs: IOTAProjectOptionsConfigurations;
begin
  Result := nil;
  All := nil;
  Headers := nil;
  ActiveConfig := ConfigName;
  if (ActiveConfig = '') and (Project <> nil) and
    Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    ActiveConfig := Configs.ActiveConfigurationName;
  LastOk := 0;
  if Project <> nil then
    LastOk := LastOkTime(Project.FileName, ActiveConfig, PlatformName);
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    FileName := Project.GetModule(Index).FileName;
    if SameText(ExtractFileExt(FileName), '.cpp') and FileExists(FileName) then
    begin
      All := All + [FileName];
      Header := ChangeFileExt(FileName, '.h');
      if (LastOk > 0) and FileExists(Header) and (TFile.GetLastWriteTime(Header) > LastOk) then
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
    if LastOk = 0 then
      Result := Result + [FileName]
    else if TFile.GetLastWriteTime(FileName) > LastOk then
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

function CppBuildErrors(const Project: IOTAProject; const PlatformName: string;
  const ConfigName: string = ''): TArray<TAgentCompileError>;
var
  Exe, Dir, Args, Output, FileName, ObjFile: string;
begin
  Result := nil;
  Exe := Compiler(PlatformName);
  if Exe = '' then
    Exit;
  Dir := ExtractFileDir(Project.FileName);
  Args := ProjectArgs(Project, PlatformName);
  ObjFile := ProcessTempFile('cppcheck.o');
  for FileName in ChangedSources(Project, PlatformName, ConfigName) do
  begin
    RunCaptured('"' + Exe + '"' + Args + ' -c -o "' + ObjFile + '" "' + FileName + '"', Dir, Output, 120000);
    Result := Result + ParseCppErrors(Output, ExtractFileDir(FileName));
    if Length(Result) >= MaxErrors then
      Break;
  end;
  System.SysUtils.DeleteFile(ObjFile);
end;

initialization
  GLastOk := TDictionary<string, TDateTime>.Create;

finalization
  GLastOk.Free;

end.
