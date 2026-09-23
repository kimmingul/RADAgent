unit DelphiAgent.OmpCatalog;

{ Finds the skills, extension modules, task agents and MCP servers omp would load for a project,
  by the same folders omp scans. Read-only. No ToolsAPI. }

interface

uses
  System.JSON;

type
  TToggleKind = (tkSkill, tkExtension, tkAgent);

  TToggleItem = record
    Kind: TToggleKind;
    Name, Source: string;
    Enabled: Boolean;
    { Excluded by the global skills.ignoredSkills; this dialog cannot turn it on. }
    GloballyOff: Boolean;
  end;

const
  { disabledExtensions id prefix; agents use task.disabledAgents names instead. }
  ToggleIdPrefix: array[TToggleKind] of string = ('skill:', 'extension-module:', '');

{ Discovered items, first of a name wins. Enabled/GloballyOff are left for the caller. }
function DiscoverToggles(const Executable, ProjectDir: string; ClaudeProjectSkills: Boolean): TArray<TToggleItem>;
{ "name — source" lines of configured MCP servers. }
function DiscoverMcpServers(const ProjectDir: string): TArray<string>;
{ Active omp agent directory (~\.omp\agent unless PI_CODING_AGENT_DIR). }
function AgentDir: string;
{ Parsed object, or an empty object for missing/invalid input. The caller frees it. }
function ParseObject(const Text: string): TJSONObject;
function ReadJsonFile(const Path: string): TJSONObject;
function StringsOf(Value: TJSONValue): TArray<string>;
function ContainsText(const Items: TArray<string>; const Item: string): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils, DelphiAgent.OmpCli, DelphiAgent.Options;

function AgentDir: string;
begin
  Result := GetEnvironmentVariable('PI_CODING_AGENT_DIR');
  if Result = '' then
    Result := TPath.Combine(GetEnvironmentVariable('USERPROFILE'), '.omp\agent');
end;

function ParseObject(const Text: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(Text);
  except
  end;
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
  begin
    Value.Free;
    Result := TJSONObject.Create;
  end;
end;

function ReadJsonFile(const Path: string): TJSONObject;
begin
  if FileExists(Path) then
    Result := ParseObject(TFile.ReadAllText(Path, TEncoding.UTF8))
  else
    Result := TJSONObject.Create;
end;

function StringsOf(Value: TJSONValue): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if Value is TJSONArray then
    for Index := 0 to TJSONArray(Value).Count - 1 do
      if TJSONArray(Value).Items[Index] is TJSONString then
        Result := Result + [TJSONString(TJSONArray(Value).Items[Index]).Value];
end;

function ContainsText(const Items: TArray<string>; const Item: string): Boolean;
var
  S: string;
begin
  for S in Items do
    if SameText(S, Item) then
      Exit(True);
  Result := False;
end;

procedure AddItem(var Items: TArray<TToggleItem>; Kind: TToggleKind; const Name, Source: string);
var
  Item: TToggleItem;
begin
  Item := Default(TToggleItem);
  Item.Kind := Kind;
  Item.Name := Name;
  Item.Source := Source;
  Items := Items + [Item];
end;

procedure AddEntries(var Items: TArray<TToggleItem>; Kind: TToggleKind; const Dir, Source: string);
var
  Path, Name, Ext: string;
begin
  if not DirectoryExists(Dir) then
    Exit;
  for Path in TDirectory.GetFileSystemEntries(Dir) do
  begin
    Name := ExtractFileName(Path);
    Ext := ExtractFileExt(Name);
    if DirectoryExists(Path) then
    begin
      if ((Kind = tkSkill) and FileExists(TPath.Combine(Path, 'SKILL.md'))) or
        ((Kind = tkExtension) and (FileExists(TPath.Combine(Path, 'index.ts')) or
        FileExists(TPath.Combine(Path, 'index.js')))) then
        AddItem(Items, Kind, Name, Source);
    end
    else if ((Kind = tkExtension) and (SameText(Ext, '.ts') or SameText(Ext, '.js'))) or
      ((Kind = tkAgent) and SameText(Ext, '.md')) then
      AddItem(Items, Kind, ChangeFileExt(Name, ''), Source);
  end;
end;

function DiscoverToggles(const Executable, ProjectDir: string; ClaudeProjectSkills: Boolean): TArray<TToggleItem>;
var
  Home, Bundled: string;
  Index, Other: Integer;
begin
  Result := nil;
  Home := GetEnvironmentVariable('USERPROFILE');
  AddEntries(Result, tkSkill, TPath.Combine(ProjectDir, '.omp\skills'), '프로젝트');
  AddEntries(Result, tkSkill, TPath.Combine(ProjectDir, '.agents\skills'), '프로젝트');
  AddEntries(Result, tkSkill, TPath.Combine(AgentDir, 'skills'), '사용자');
  AddEntries(Result, tkSkill, TPath.Combine(Home, '.agents\skills'), '사용자');
  if ClaudeProjectSkills then
    AddEntries(Result, tkSkill, TPath.Combine(ProjectDir, '.claude\skills'), '프로젝트 Claude');
  AddEntries(Result, tkExtension, TPath.Combine(ProjectDir, '.omp\extensions'), '프로젝트');
  AddEntries(Result, tkExtension, TPath.Combine(AgentDir, 'extensions'), '사용자');
  { Bundled agents are not files; omp writes them out on request. }
  Bundled := AgentTempRoot + 'bundled-agents';
  if RunOmp(Executable, 'agents unpack --force --dir "' + Bundled + '"', ProjectDir) <> '' then
    AddEntries(Result, tkAgent, Bundled, '기본 제공');
  AddEntries(Result, tkAgent, TPath.Combine(ProjectDir, '.omp\agents'), '프로젝트');
  AddEntries(Result, tkAgent, TPath.Combine(AgentDir, 'agents'), '사용자');
  for Index := High(Result) downto 1 do
    for Other := 0 to Index - 1 do
      if (Result[Other].Kind = Result[Index].Kind) and SameText(Result[Other].Name, Result[Index].Name) then
      begin
        Delete(Result, Index, 1);
        Break;
      end;
end;

function DiscoverMcpServers(const ProjectDir: string): TArray<string>;
var
  Off: TArray<string>;
  Found: TArray<string>;

  procedure AddFrom(const Path, Source: string);
  var
    Config: TJSONObject;
    Servers: TJSONValue;
    Index: Integer;
    Name: string;
  begin
    Config := ReadJsonFile(Path);
    try
      Servers := Config.GetValue('mcpServers');
      if Servers is TJSONObject then
        for Index := 0 to TJSONObject(Servers).Count - 1 do
        begin
          Name := TJSONObject(Servers).Pairs[Index].JsonString.Value;
          if ContainsText(Off, Name) then
            Found := Found + [Name + ' — ' + Source + ' · 꺼짐']
          else
            Found := Found + [Name + ' — ' + Source];
        end;
    finally
      Config.Free;
    end;
  end;

var
  User: TJSONObject;
begin
  Found := nil;
  User := ReadJsonFile(TPath.Combine(AgentDir, 'mcp.json'));
  try
    Off := StringsOf(User.GetValue('disabledServers'));
  finally
    User.Free;
  end;
  AddFrom(TPath.Combine(ProjectDir, '.omp\mcp.json'), '프로젝트');
  AddFrom(TPath.Combine(ProjectDir, 'mcp.json'), '프로젝트');
  AddFrom(TPath.Combine(ProjectDir, '.mcp.json'), '프로젝트');
  AddFrom(TPath.Combine(AgentDir, 'mcp.json'), '사용자');
  Result := Found;
end;

end.
