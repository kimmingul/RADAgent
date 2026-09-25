unit RADAgent.OmpSettings;

{ omp settings RADAgent may change, scoped to one project. Values are written to
  <project>\.omp\radagent.yml (JSON is valid YAML) and passed to omp with --config, so the
  user's global config.yml and the project's own .omp\config.yml are never rewritten.
  Base values come from "omp config list --json" run in the project folder. No ToolsAPI. }

interface

uses
  System.JSON, RADAgent.OmpCatalog;

type
  TOmpProjectSettings = class
  private
    FExecutable, FProjectDir: string;
    FBase, FOverlay: TJSONObject;
    function BaseValue(const Key: string): TJSONValue;
    function OverlayValue(const Key: string): TJSONValue;
    function EffectiveList(const Key: string): TArray<string>;
    procedure SetList(const Key: string; const Items: TArray<string>);
  public
    constructor Create(const Executable, ProjectDir: string);
    destructor Destroy; override;
    { Value this project overrides ('' = none) and the value omp uses without it. }
    function OverlayText(const Key: string): string;
    function BaseText(const Key: string): string;
    procedure SetOverlayText(const Key, Value: string);
    { Booleans: 'true', 'false', or '' for none. }
    function OverlayBool(const Key: string): string;
    procedure SetOverlayBool(const Key, Value: string);
    function Toggles: TArray<TToggleItem>;
    procedure ApplyToggles(const Items: TArray<TToggleItem>);
    { One disabledExtensions id (e.g. extension-module:foo) on or off for this project. }
    function IsDisabled(const Id: string): Boolean;
    procedure SetDisabled(const Id: string; Disabled: Boolean);
    procedure Save;
    property ProjectDir: string read FProjectDir;
  end;

function OverlayPath(const ProjectDir: string): string;
{ The overlay to pass with --config, or '' when this project has none. }
function ExistingOverlay(const ProjectDir: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, RADAgent.OmpCli;

function OverlayPath(const ProjectDir: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ProjectDir, '.omp'), 'radagent.yml');
end;

function ExistingOverlay(const ProjectDir: string): string;
begin
  Result := '';
  if (ProjectDir <> '') and FileExists(OverlayPath(ProjectDir)) then
    Result := OverlayPath(ProjectDir);
end;

constructor TOmpProjectSettings.Create(const Executable, ProjectDir: string);
begin
  inherited Create;
  FExecutable := Executable;
  FProjectDir := ProjectDir;
  FBase := ParseObject(RunOmp(Executable, 'config list --json', ProjectDir));
  FOverlay := ReadJsonFile(OverlayPath(ProjectDir));
end;

destructor TOmpProjectSettings.Destroy;
begin
  FBase.Free;
  FOverlay.Free;
  inherited Destroy;
end;

{ "config list" keys records by their own name ("modelRoles"); entries below are walked. }
function TOmpProjectSettings.BaseValue(const Key: string): TJSONValue;
var
  Parts: TArray<string>;
  Head, Step: Integer;
begin
  Result := nil;
  Parts := Key.Split(['.']);
  for Head := High(Parts) downto 0 do
    if FBase.GetValue(string.Join('.', Parts, 0, Head + 1)) is TJSONObject then
    begin
      Result := TJSONObject(FBase.GetValue(string.Join('.', Parts, 0, Head + 1))).GetValue('value');
      for Step := Head + 1 to High(Parts) do
        if Result is TJSONObject then
          Result := TJSONObject(Result).GetValue(Parts[Step])
        else
          Exit(nil);
      Exit;
    end;
end;

{ Walks dotted keys ("tools.approvalMode") through nested overlay objects. }
function TOmpProjectSettings.OverlayValue(const Key: string): TJSONValue;
var
  Parts: TArray<string>;
  Index: Integer;
begin
  Result := FOverlay;
  Parts := Key.Split(['.']);
  for Index := 0 to High(Parts) do
    if Result is TJSONObject then
      Result := TJSONObject(Result).GetValue(Parts[Index])
    else
      Exit(nil);
end;

function TOmpProjectSettings.OverlayText(const Key: string): string;
begin
  Result := '';
  if OverlayValue(Key) is TJSONString then
    Result := TJSONString(OverlayValue(Key)).Value;
end;

function TOmpProjectSettings.BaseText(const Key: string): string;
begin
  Result := '';
  if BaseValue(Key) <> nil then
    Result := BaseValue(Key).Value;
end;

procedure SetPath(Root: TJSONObject; const Key: string; Value: TJSONValue);
var
  Parts: TArray<string>;
  Node, Child: TJSONObject;
  Index, Depth: Integer;
begin
  Parts := Key.Split(['.']);
  Node := Root;
  for Index := 0 to High(Parts) - 1 do
  begin
    if not (Node.GetValue(Parts[Index]) is TJSONObject) then
    begin
      Node.RemovePair(Parts[Index]).Free;
      Child := TJSONObject.Create;
      Node.AddPair(Parts[Index], Child);
    end;
    Node := TJSONObject(Node.GetValue(Parts[Index]));
  end;
  Node.RemovePair(Parts[High(Parts)]).Free;
  if Value <> nil then
    Node.AddPair(Parts[High(Parts)], Value);
  { Drop objects left empty so the overlay only holds real overrides. }
  for Index := High(Parts) - 1 downto 0 do
  begin
    Node := Root;
    for Depth := 0 to Index - 1 do
      Node := TJSONObject(Node.GetValue(Parts[Depth]));
    if (Node.GetValue(Parts[Index]) is TJSONObject) and (TJSONObject(Node.GetValue(Parts[Index])).Count = 0) then
      Node.RemovePair(Parts[Index]).Free;
  end;
end;

procedure TOmpProjectSettings.SetOverlayText(const Key, Value: string);
begin
  if Trim(Value) = '' then
    SetPath(FOverlay, Key, nil)
  else
    SetPath(FOverlay, Key, TJSONString.Create(Trim(Value)));
end;

function TOmpProjectSettings.OverlayBool(const Key: string): string;
begin
  Result := '';
  if OverlayValue(Key) is TJSONBool then
    Result := LowerCase(BoolToStr(TJSONBool(OverlayValue(Key)).AsBoolean, True));
end;

procedure TOmpProjectSettings.SetOverlayBool(const Key, Value: string);
begin
  if Value = '' then
    SetPath(FOverlay, Key, nil)
  else
    SetPath(FOverlay, Key, TJSONBool.Create(SameText(Value, 'true')));
end;

function TOmpProjectSettings.EffectiveList(const Key: string): TArray<string>;
begin
  if OverlayValue(Key) is TJSONArray then
    Result := StringsOf(OverlayValue(Key))
  else
    Result := StringsOf(BaseValue(Key));
end;

procedure TOmpProjectSettings.SetList(const Key: string; const Items: TArray<string>);
var
  Base: TArray<string>;
  List: TJSONArray;
  Item: string;
  Same: Boolean;
begin
  Base := StringsOf(BaseValue(Key));
  Same := Length(Base) = Length(Items);
  for Item in Items do
    Same := Same and ContainsText(Base, Item);
  if Same then
  begin
    SetPath(FOverlay, Key, nil);
    Exit;
  end;
  List := TJSONArray.Create;
  for Item in Items do
    List.Add(Item);
  SetPath(FOverlay, Key, List);
end;

function TOmpProjectSettings.Toggles: TArray<TToggleItem>;
var
  Disabled, Agents, Ignored: TArray<string>;
  Index: Integer;
begin
  Result := DiscoverToggles(FExecutable, FProjectDir, SameText(BaseText('skills.enableClaudeProject'), 'true'));
  Disabled := EffectiveList('disabledExtensions');
  Agents := EffectiveList('task.disabledAgents');
  Ignored := StringsOf(BaseValue('skills.ignoredSkills'));
  for Index := 0 to High(Result) do
  begin
    if Result[Index].Kind = tkAgent then
      Result[Index].Enabled := not ContainsText(Agents, Result[Index].Name)
    else
      Result[Index].Enabled := not ContainsText(Disabled, ToggleIdPrefix[Result[Index].Kind] + Result[Index].Name);
    Result[Index].GloballyOff := (Result[Index].Kind = tkSkill) and ContainsText(Ignored, Result[Index].Name);
  end;
end;

function TOmpProjectSettings.IsDisabled(const Id: string): Boolean;
begin
  Result := ContainsText(EffectiveList('disabledExtensions'), Id);
end;

procedure TOmpProjectSettings.SetDisabled(const Id: string; Disabled: Boolean);
var
  Items, Kept: TArray<string>;
  Item: string;
begin
  Items := EffectiveList('disabledExtensions');
  Kept := nil;
  for Item in Items do
    if not SameText(Item, Id) then
      Kept := Kept + [Item];
  if Disabled then
    Kept := Kept + [Id];
  SetList('disabledExtensions', Kept);
end;

procedure TOmpProjectSettings.ApplyToggles(const Items: TArray<TToggleItem>);
var
  Disabled, Agents, Kept: TArray<string>;
  Item: TToggleItem;
  Id: string;
  Listed: Boolean;
begin
  Disabled := EffectiveList('disabledExtensions');
  Agents := EffectiveList('task.disabledAgents');
  { Keep ids this dialog does not list (e.g. context files), then add the unchecked ones. }
  Kept := nil;
  for Id in Disabled do
  begin
    Listed := False;
    for Item in Items do
      Listed := Listed or ((Item.Kind <> tkAgent) and SameText(Id, ToggleIdPrefix[Item.Kind] + Item.Name));
    if not Listed then
      Kept := Kept + [Id];
  end;
  for Item in Items do
    if (Item.Kind <> tkAgent) and not Item.Enabled then
      Kept := Kept + [ToggleIdPrefix[Item.Kind] + Item.Name];
  SetList('disabledExtensions', Kept);
  Kept := nil;
  for Id in Agents do
  begin
    Listed := False;
    for Item in Items do
      Listed := Listed or ((Item.Kind = tkAgent) and SameText(Id, Item.Name));
    if not Listed then
      Kept := Kept + [Id];
  end;
  for Item in Items do
    if (Item.Kind = tkAgent) and not Item.Enabled then
      Kept := Kept + [Item.Name];
  SetList('task.disabledAgents', Kept);
end;

procedure TOmpProjectSettings.Save;
var
  Path: string;
begin
  Path := OverlayPath(FProjectDir);
  if FOverlay.Count = 0 then
  begin
    if FileExists(Path) then
      System.SysUtils.DeleteFile(Path);
    Exit;
  end;
  ForceDirectories(ExtractFileDir(Path));
  { No BOM: the file is read as YAML. }
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(FOverlay.Format(2)));
end;

end.
