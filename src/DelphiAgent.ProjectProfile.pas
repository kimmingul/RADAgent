unit DelphiAgent.ProjectProfile;

{ What the active project is (Delphi or C++Builder, VCL or FMX, which forms) and the project
  tools built on it: rad.project_info, rad.set_build_config, rad.list_components. Main thread
  only. }

interface

uses
  DelphiAgent.HostToolDefs, DelphiAgent.Approval;

type
  TProjectModule = record
    FileName, FormName, DesignClass: string;
  end;

  TProjectProfile = record
    ProjectFile, ProjectDir: string;
    Tools: TToolProfile;
    Modules: TArray<TProjectModule>;
  end;

function ActiveProfile: TProjectProfile;
{ rad.project_info result. }
function ProjectInfoJson: string;
{ rad.set_build_config: approval, then configuration and/or platform. }
function SetBuildConfig(const Config, Platform: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
{ rad.list_components: palette classes whose name or package contains Filter. }
function ComponentsJson(const Filter: string): string;

implementation

uses
  System.SysUtils, System.JSON, ToolsAPI, DelphiAgent.IdeContext;

function ActiveProfile: TProjectProfile;
var
  Project: IOTAProject;
  Info: IOTAModuleInfo;
  Index: Integer;
  Module: TProjectModule;
begin
  Result := Default(TProjectProfile);
  Result.Tools.Language := 'delphi';
  Project := CurrentProject;
  if Project = nil then
    Exit;
  Result.ProjectFile := Project.FileName;
  Result.ProjectDir := ExtractFileDir(Project.FileName);
  if SameText(Project.Personality, sCBuilderPersonality) then
    Result.Tools.Language := 'cpp';
  if SameText(Project.FrameworkType, sFrameworkTypeVCL) or SameText(Project.FrameworkType, sFrameworkTypeFMX) then
    Result.Tools.Framework := UpperCase(Project.FrameworkType);
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    Info := Project.GetModule(Index);
    if (Info = nil) or (Info.FileName = '') then
      Continue;
    Module.FileName := Info.FileName;
    Module.FormName := Info.FormName;
    Module.DesignClass := Info.DesignClass;
    Result.Modules := Result.Modules + [Module];
    if Module.FormName <> '' then
      Result.Tools.HasForms := True;
  end;
end;

function StringArray(const Items: TArray<string>): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in Items do
    Result.Add(Item);
end;

function Configurations(const Project: IOTAProject): TArray<string>;
var
  Options: IOTAProjectOptionsConfigurations;
  Index: Integer;
begin
  Result := nil;
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Options) then
    for Index := 0 to Options.ConfigurationCount - 1 do
      Result := Result + [Options.Configurations[Index].Name];
end;

function ProjectInfoJson: string;
var
  Project: IOTAProject;
  Profile: TProjectProfile;
  Obj, Item: TJSONObject;
  Modules: TJSONArray;
  Module: TProjectModule;
begin
  Project := CurrentProject;
  if Project = nil then
    Exit('{"ok":false,"error":"활성 프로젝트가 없습니다."}');
  Profile := ActiveProfile;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('project', Profile.ProjectFile);
    if Profile.Tools.Language = 'cpp' then
      Obj.AddPair('language', 'C++Builder')
    else
      Obj.AddPair('language', 'Delphi');
    Obj.AddPair('framework', Project.FrameworkType);
    Obj.AddPair('configuration', Project.CurrentConfiguration);
    Obj.AddPair('platform', Project.CurrentPlatform);
    Obj.AddPair('configurations', StringArray(Configurations(Project)));
    Obj.AddPair('platforms', StringArray(Project.SupportedPlatforms));
    Modules := TJSONArray.Create;
    for Module in Profile.Modules do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('file', Module.FileName);
      if Module.FormName <> '' then
      begin
        Item.AddPair('form', Module.FormName);
        Item.AddPair('designClass', Module.DesignClass);
      end;
      Modules.AddElement(Item);
    end;
    Obj.AddPair('modules', Modules);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function Listed(const Items: TArray<string>; const Value: string): string;
var
  Item: string;
begin
  Result := '';
  for Item in Items do
    if SameText(Item, Value) then
      Exit(Item);
end;

function SetBuildConfig(const Config, Platform: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Project: IOTAProject;
  NewConfig, NewPlatform: string;
begin
  Result := False;
  Project := CurrentProject;
  if Project = nil then
  begin
    ResultText := '활성 프로젝트가 없습니다.';
    Exit;
  end;
  NewConfig := Project.CurrentConfiguration;
  NewPlatform := Project.CurrentPlatform;
  if Config <> '' then
    NewConfig := Listed(Configurations(Project), Config);
  if Platform <> '' then
    NewPlatform := Listed(Project.SupportedPlatforms, Platform);
  if (NewConfig = '') or (NewPlatform = '') then
  begin
    ResultText := '없는 구성 또는 플랫폼입니다. rad.project_info의 목록에서 고르세요.';
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveChange(Project.FileName, '', Format(
    '빌드 구성: %s -> %s' + sLineBreak + '대상 플랫폼: %s -> %s', [Project.CurrentConfiguration,
    NewConfig, Project.CurrentPlatform, NewPlatform])) then
  begin
    ResultText := SEditCancelled;
    Exit(True);
  end;
  Project.CurrentConfiguration := NewConfig;
  Project.CurrentPlatform := NewPlatform;
  ResultText := Format('{"ok":true,"configuration":"%s","platform":"%s"}',
    [Project.CurrentConfiguration, Project.CurrentPlatform]);
  Result := True;
end;

function ComponentsJson(const Filter: string): string;
const
  MaxItems = 300;
var
  Packages: IOTAPackageServices;
  Items: TJSONArray;
  Obj, Item: TJSONObject;
  Pkg, Comp, Total: Integer;
  Name, Package, Needle: string;
begin
  Packages := BorlandIDEServices as IOTAPackageServices;
  Needle := LowerCase(Filter);
  Items := TJSONArray.Create;
  Obj := TJSONObject.Create;
  try
    Total := 0;
    for Pkg := 0 to Packages.PackageCount - 1 do
    begin
      Package := Packages.PackageNames[Pkg];
      for Comp := 0 to Packages.ComponentCount[Pkg] - 1 do
      begin
        Name := Packages.ComponentNames[Pkg, Comp];
        if (Needle <> '') and not LowerCase(Name + ' ' + Package).Contains(Needle) then
          Continue;
        Inc(Total);
        if Items.Count >= MaxItems then
          Continue;
        Item := TJSONObject.Create;
        Item.AddPair('class', Name);
        Item.AddPair('package', Package);
        Items.AddElement(Item);
      end;
    end;
    Obj.AddPair('total', TJSONNumber.Create(Total));
    Obj.AddPair('components', Items);
    Items := nil;
    Result := Obj.ToJSON;
  finally
    Items.Free;
    Obj.Free;
  end;
end;

end.
