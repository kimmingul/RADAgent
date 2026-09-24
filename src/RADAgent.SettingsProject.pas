unit RADAgent.SettingsProject;

{ Settings pages whose values go to this project's omp overlay (RADAgent.OmpSettings):
  model roles, skills/extensions/agents, and omp defaults. They apply after omp restarts. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, RADAgent.OmpSettings,
  RADAgent.OmpCatalog;

type
  TProjectPages = class(TComponent)
  private
    FSettings: TOmpProjectSettings;
    FRoles: array of TComboBox;
    FToggles: TArray<TToggleItem>;
    FToggleList: TListView;
    FApproval, FThinking: TComboBox;
    procedure ToggleChanging(Sender: TObject; Item: TListItem; Change: TItemChange;
      var AllowChange: Boolean);
    procedure BuildRoles(Page: TWinControl; const Models: TArray<string>);
    procedure BuildToggles(Page: TWinControl);
    procedure BuildDefaults(Page: TWinControl);
  public
    constructor Create(AOwner: TComponent; Settings: TOmpProjectSettings;
      RolePage, ExtensionPage, DefaultsPage: TWinControl; const Models: TArray<string>); reintroduce;
    { Copies the controls into the overlay (not yet saved). }
    procedure Store;
  end;

implementation

uses
  System.SysUtils, RADAgent.SettingsUi, RADAgent.Lang;

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
    Combo := TComboBox.Create(Page);
    Combo.Style := csDropDown;
    Combo.DropDownCount := 24;
    AddRow(Page, RoleCaption(Index), Combo);
    Combo.Items.Add('');
    for Model in Models do
      Combo.Items.Add(Model);
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
begin
  for Index := 0 to High(Roles) do
    FSettings.SetOverlayText('modelRoles.' + Roles[Index], FRoles[Index].Text);
  for Index := 0 to High(FToggles) do
    if not FToggles[Index].GloballyOff then
      FToggles[Index].Enabled := FToggleList.Items[Index].Checked;
  FSettings.ApplyToggles(FToggles);
  FSettings.SetOverlayText('tools.approvalMode', ChoiceValue(FApproval));
  FSettings.SetOverlayText('defaultThinkingLevel', ChoiceValue(FThinking));
end;

end.
