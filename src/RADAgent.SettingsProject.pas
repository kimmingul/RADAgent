unit RADAgent.SettingsProject;

{ Settings pages whose values go to this project's omp overlay (RADAgent.OmpSettings):
  model roles, skills/extensions/agents, and omp defaults. They apply after omp restarts. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, RADAgent.OmpSettings,
  RADAgent.OmpCatalog;

type
  { A combo whose rows are translated labels for Values; Values[0] = '' keeps omp's value. }
  TLabeledChoice = record
    Combo: TComboBox;
    Key: string;
    Values: TArray<string>;
    IsBool: Boolean;
  end;

  TProjectPages = class(TComponent)
  private
    FSettings: TOmpProjectSettings;
    FRoles: array of TComboBox;
    FToggles: TArray<TToggleItem>;
    FToggleList: TListView;
    FApproval, FThinking, FUiBuilding, FFormEditing: TComboBox;
    FIdeSettingsChanged: Boolean;
    FChoices: TArray<TLabeledChoice>;
    procedure AddLabeled(Page: TWinControl; const Caption, Key: string; const Values: array of string;
      IsBool: Boolean);
    procedure ToggleChanging(Sender: TObject; Item: TListItem; Change: TItemChange;
      var AllowChange: Boolean);
    procedure BuildRoles(Page: TWinControl; const Models: TArray<string>);
    procedure BuildToggles(Page: TWinControl);
    procedure BuildDefaults(Page: TWinControl);
  public
    constructor Create(AOwner: TComponent; Settings: TOmpProjectSettings;
      RolePage, ExtensionPage, DefaultsPage: TWinControl; const Models: TArray<string>); reintroduce;
    { Copies the controls into the overlay (not yet saved); the UI building and form editing
      choices are saved now. }
    procedure Store;
    { Store changed UI building or form editing: omp must restart for the new guide and tools. }
    property IdeSettingsChanged: Boolean read FIdeSettingsChanged;
  end;

implementation

uses
  System.SysUtils, RADAgent.SettingsUi, RADAgent.Lang, RADAgent.BrandTable, RADAgent.BrandIcons,
  RADAgent.AgentSettings;

const
  Roles: array[0..8] of string = ('default', 'smol', 'slow', 'plan', 'task', 'advisor', 'commit',
    'vision', 'tiny');
  ApprovalModes: array[0..3] of string = ('', 'always-ask', 'write', 'yolo');
  ThinkingLevels: array[0..8] of string = ('', 'auto', 'off', 'minimal', 'low', 'medium', 'high',
    'xhigh', 'max');

function RoleCaption(Index: Integer): string;
begin
  case Index of
    0: Result := Tr('settingsproject.roleDefault');
    1: Result := Tr('settingsproject.roleSmol');
    2: Result := Tr('settingsproject.roleSlow');
    3: Result := Tr('settingsproject.rolePlan');
    4: Result := Tr('settingsproject.roleTask');
    5: Result := Tr('settingsproject.roleAdvisor');
    6: Result := Tr('settingsproject.roleCommit');
    7: Result := Tr('settingsproject.roleVision');
    8: Result := Tr('settingsproject.roleTiny');
  else
    Result := '';
  end;
end;

function KindCaption(Kind: TToggleKind): string;
begin
  case Kind of
    tkSkill: Result := Tr('settingsproject.kindSkill');
    tkExtension: Result := Tr('settingsproject.kindExtension');
    tkAgent: Result := Tr('settingsproject.kindAgent');
  else
    Result := '';
  end;
end;

constructor TProjectPages.Create(AOwner: TComponent; Settings: TOmpProjectSettings;
  RolePage, ExtensionPage, DefaultsPage: TWinControl; const Models: TArray<string>);
begin
  inherited Create(AOwner);
  FSettings := Settings;
  BuildRoles(RolePage, Models);
  BuildToggles(ExtensionPage);
  BuildDefaults(DefaultsPage);
end;

procedure TProjectPages.BuildRoles(Page: TWinControl; const Models: TArray<string>);
var
  Index: Integer;
  Combo: TComboBox;
  Model: string;
begin
  AddNote(Page, Tr('settingsproject.noteRoles'));
  SetLength(FRoles, Length(Roles));
  for Index := 0 to High(Roles) do
  begin
    Combo := TBrandCombo.Create(Page);
    Combo.Style := csDropDown;
    Combo.DropDownCount := 24;
    { Logos in the list; the empty row keeps the global value, shown greyed. }
    MakeBrandCombo(Combo, TrF('settingsproject.globalRoleHint',
      [FSettings.BaseText('modelRoles.' + Roles[Index])]));
    AddRow(Page, RoleCaption(Index), Combo);
    AddBrandItem(Combo.Items, '', -1);
    for Model in Models do
      AddBrandItem(Combo.Items, Model, SelectorBrand(Model));
    Combo.Text := FSettings.OverlayText('modelRoles.' + Roles[Index]);
    Combo.TextHint := TrF('settingsproject.globalRoleHint', [FSettings.BaseText('modelRoles.' + Roles[Index])]);
    Combo.ShowHint := True;
    Combo.Hint := Combo.TextHint;
    FRoles[Index] := Combo;
  end;
end;

procedure TProjectPages.BuildToggles(Page: TWinControl);
var
  Item: TToggleItem;
  Row: TListItem;
  Servers: TArray<TMcpServer>;
  Server: TMcpServer;
  List: TListBox;
begin
  AddNote(Page, Tr('settingsproject.noteToggles'));
  FToggleList := AddCheckList(Page, 260);
  FToggles := FSettings.Toggles;
  for Item in FToggles do
  begin
    Row := FToggleList.Items.Add;
    Row.Caption := Format('[%s] %s — %s', [KindCaption(Item.Kind), Item.Name, Item.Source]);
    if Item.GloballyOff then
      Row.Caption := Row.Caption + Tr('settingsproject.globallyOffSuffix');
    Row.Checked := Item.Enabled and not Item.GloballyOff;
  end;
  FToggleList.OnChanging := ToggleChanging;
  AddHeading(Page, Tr('settingsproject.headingMcp'));
  List := TListBox.Create(Page);
  List.Height := 90;
  AddStacked(Page, List);
  Servers := DiscoverMcpServers(FSettings.ProjectDir);
  for Server in Servers do
    if Server.Enabled then
      List.Items.Add(Server.Name + ' — ' + Server.Source)
    else
      List.Items.Add(Server.Name + ' — ' + Server.Source + Tr('settingsproject.mcpOffSuffix'));
  if Length(Servers) = 0 then
    List.Items.Add(Tr('settingsproject.noMcpServers'));
  AddNote(Page, Tr('settingsproject.noteMcp'));
end;

procedure TProjectPages.ToggleChanging(Sender: TObject; Item: TListItem; Change: TItemChange;
  var AllowChange: Boolean);
begin
  { A globally ignored skill stays off. }
  if (Change = ctState) and (Item.Index <= High(FToggles)) and FToggles[Item.Index].GloballyOff then
    AllowChange := False;
end;

procedure FillChoices(Combo: TComboBox; const Values: array of string; const Current, Base: string);
var
  Value: string;
begin
  for Value in Values do
    if Value = '' then
      Combo.Items.Add(TrF('settingsproject.globalValueFormat', [Base]))
    else
      Combo.Items.Add(Value);
  Combo.ItemIndex := 0;
  for Value in Values do
    if (Value <> '') and (Value = Current) then
      Combo.ItemIndex := Combo.Items.IndexOf(Value);
end;

procedure TProjectPages.BuildDefaults(Page: TWinControl);
begin
  AddHeading(Page, Tr('settingsproject.headingDefaults'));
  FApproval := TComboBox.Create(Page);
  FApproval.Style := csDropDownList;
  AddRow(Page, Tr('settingsproject.toolApproval'), FApproval);
  FillChoices(FApproval, ApprovalModes, FSettings.OverlayText('tools.approvalMode'),
    FSettings.BaseText('tools.approvalMode'));
  FThinking := TComboBox.Create(Page);
  FThinking.Style := csDropDownList;
  AddRow(Page, Tr('settingsproject.defaultThinkingLevel'), FThinking);
  FillChoices(FThinking, ThinkingLevels, FSettings.OverlayText('defaultThinkingLevel'),
    FSettings.BaseText('defaultThinkingLevel'));
  AddNote(Page, Tr('settingsproject.noteApproval'));
  FUiBuilding := TComboBox.Create(Page);
  FUiBuilding.Style := csDropDownList;
  AddRow(Page, Tr('settingsproject.uiBuilding'), FUiBuilding);
  FUiBuilding.Items.Add(Tr('settingsproject.uiBuildingDesigner'));
  FUiBuilding.Items.Add(Tr('settingsproject.uiBuildingFree'));
  FUiBuilding.ItemIndex := Ord(not DesignerUiRequired(FSettings.ProjectDir));
  FFormEditing := TComboBox.Create(Page);
  FFormEditing.Style := csDropDownList;
  AddRow(Page, Tr('settingsproject.formEditing'), FFormEditing);
  FFormEditing.Items.Add(Tr('settingsproject.formEditingAuto'));
  FFormEditing.Items.Add(Tr('settingsproject.formEditingDesigner'));
  FFormEditing.ItemIndex := Ord(not FormTextAllowed(FSettings.ProjectDir));
  AddNote(Page, Tr('settingsproject.noteFormEditing'));
  AddHeading(Page, Tr('settingsproject.headingSession'));
  AddLabeled(Page, Tr('settingsproject.autoCompaction'), 'compaction.enabled', ['', 'true', 'false'], True);
  AddLabeled(Page, Tr('settingsproject.autoRetry'), 'retry.enabled', ['', 'true', 'false'], True);
  AddLabeled(Page, Tr('settingsproject.steeringMode'), 'steeringMode', ['', 'one-at-a-time', 'all'], False);
  AddLabeled(Page, Tr('settingsproject.followUpMode'), 'followUpMode', ['', 'one-at-a-time', 'all'], False);
  AddLabeled(Page, Tr('settingsproject.interruptMode'), 'interruptMode', ['', 'immediate', 'wait'], False);
  AddNote(Page, Tr('settingsproject.noteSession'));
end;

function ValueCaption(const Value: string): string;
begin
  Result := Tr('settingsproject.value.' + Value);
  if Result = 'settingsproject.value.' + Value then
    Result := Value;
end;

procedure TProjectPages.AddLabeled(Page: TWinControl; const Caption, Key: string;
  const Values: array of string; IsBool: Boolean);
var
  Choice: TLabeledChoice;
  Index: Integer;
  Current: string;
begin
  Choice.Combo := TComboBox.Create(Page);
  Choice.Combo.Style := csDropDownList;
  AddRow(Page, Caption, Choice.Combo);
  Choice.Key := Key;
  Choice.IsBool := IsBool;
  Choice.Values := nil;
  if IsBool then
    Current := FSettings.OverlayBool(Key)
  else
    Current := FSettings.OverlayText(Key);
  for Index := 0 to High(Values) do
  begin
    Choice.Values := Choice.Values + [Values[Index]];
    if Values[Index] = '' then
      Choice.Combo.Items.Add(TrF('settingsproject.globalValueFormat', [ValueCaption(FSettings.BaseText(Key))]))
    else
      Choice.Combo.Items.Add(ValueCaption(Values[Index]));
    if Values[Index] = Current then
      Choice.Combo.ItemIndex := Index;
  end;
  if Choice.Combo.ItemIndex < 0 then
    Choice.Combo.ItemIndex := 0;
  FChoices := FChoices + [Choice];
end;

function ChoiceValue(Combo: TComboBox): string;
begin
  if Combo.ItemIndex <= 0 then
    Result := ''
  else
    Result := Combo.Items[Combo.ItemIndex];
end;

procedure TProjectPages.Store;
var
  Index: Integer;
  Choice: TLabeledChoice;
begin
  for Choice in FChoices do
    if Choice.IsBool then
      FSettings.SetOverlayBool(Choice.Key, Choice.Values[Choice.Combo.ItemIndex])
    else
      FSettings.SetOverlayText(Choice.Key, Choice.Values[Choice.Combo.ItemIndex]);
  for Index := 0 to High(Roles) do
    FSettings.SetOverlayText('modelRoles.' + Roles[Index], FRoles[Index].Text);
  for Index := 0 to High(FToggles) do
    if not FToggles[Index].GloballyOff then
      FToggles[Index].Enabled := FToggleList.Items[Index].Checked;
  FSettings.ApplyToggles(FToggles);
  FSettings.SetOverlayText('tools.approvalMode', ChoiceValue(FApproval));
  FSettings.SetOverlayText('defaultThinkingLevel', ChoiceValue(FThinking));
  FIdeSettingsChanged := ((FFormEditing.ItemIndex = 0) <> FormTextAllowed(FSettings.ProjectDir)) or
    ((FUiBuilding.ItemIndex = 0) <> DesignerUiRequired(FSettings.ProjectDir));
  SetFormTextAllowed(FSettings.ProjectDir, FFormEditing.ItemIndex = 0);
  SetDesignerUiRequired(FSettings.ProjectDir, FUiBuilding.ItemIndex = 0);
end;

end.
