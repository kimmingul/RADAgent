unit DelphiAgent.SettingsProject;

{ Settings pages whose values go to this project's omp overlay (DelphiAgent.OmpSettings):
  model roles, skills/extensions/agents, and omp defaults. They apply after omp restarts. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, DelphiAgent.OmpSettings,
  DelphiAgent.OmpCatalog;

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
  System.SysUtils, DelphiAgent.SettingsUi;

const
  Roles: array[0..8] of string = ('default', 'smol', 'slow', 'plan', 'task', 'advisor', 'commit',
    'vision', 'tiny');
  RoleCaptions: array[0..8] of string = ('기본 (default)', '빠른 작업 (smol)', '깊은 분석 (slow)',
    '계획 (plan)', '하위 에이전트 (task)', '조언자 (advisor)', '커밋 메시지 (commit)',
    '이미지 이해 (vision)', '제목·요약 (tiny)');
  KindCaptions: array[TToggleKind] of string = ('스킬', '확장', '하위 에이전트');
  ApprovalModes: array[0..3] of string = ('', 'always-ask', 'write', 'yolo');
  ThinkingLevels: array[0..8] of string = ('', 'auto', 'off', 'minimal', 'low', 'medium', 'high',
    'xhigh', 'max');

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
  AddNote(Page, '역할마다 쓸 모델입니다. 비워 두면 전역 설정을 그대로 씁니다. 모델 뒤에 :high 같은 ' +
    '생각 수준을 붙일 수 있습니다. 이 프로젝트에만 적용되고 omp를 다시 시작하면 반영됩니다.');
  SetLength(FRoles, Length(Roles));
  for Index := 0 to High(Roles) do
  begin
    Combo := TComboBox.Create(Page);
    Combo.Style := csDropDown;
    Combo.DropDownCount := 24;
    AddRow(Page, RoleCaptions[Index], Combo);
    Combo.Items.Add('');
    for Model in Models do
      Combo.Items.Add(Model);
    Combo.Text := FSettings.OverlayText('modelRoles.' + Roles[Index]);
    Combo.TextHint := '전역: ' + FSettings.BaseText('modelRoles.' + Roles[Index]);
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
  AddNote(Page, '체크를 끄면 이 프로젝트에서 omp가 불러오지 않습니다. 전역 설정에서 제외한 스킬은 ' +
    '여기서 켤 수 없습니다. omp를 다시 시작하면 반영됩니다.');
  FToggleList := AddCheckList(Page, 260);
  FToggles := FSettings.Toggles;
  for Item in FToggles do
  begin
    Row := FToggleList.Items.Add;
    Row.Caption := Format('[%s] %s — %s', [KindCaptions[Item.Kind], Item.Name, Item.Source]);
    if Item.GloballyOff then
      Row.Caption := Row.Caption + ' · 전역에서 제외됨';
    Row.Checked := Item.Enabled and not Item.GloballyOff;
  end;
  FToggleList.OnChanging := ToggleChanging;
  AddHeading(Page, 'MCP 서버');
  List := TListBox.Create(Page);
  List.Height := 90;
  AddStacked(Page, List);
  Servers := DiscoverMcpServers(FSettings.ProjectDir);
  for Server in Servers do
    if Server.Enabled then
      List.Items.Add(Server.Name + ' — ' + Server.Source)
    else
      List.Items.Add(Server.Name + ' — ' + Server.Source + ' · 꺼짐');
  if Length(Servers) = 0 then
    List.Items.Add('설정된 MCP 서버가 없습니다.');
  AddNote(Page, 'MCP 서버(커넥터) 켜고 끄기는 입력 상자 왼쪽 아래 + → 커넥터에서 합니다. omp의 /mcp ' +
    '명령으로 바꾸므로 프로젝트 파일에 정의된 서버는 그 파일에, 나머지는 사용자 설정에 저장됩니다.');
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
      Combo.Items.Add('(전역 값: ' + Base + ')')
    else
      Combo.Items.Add(Value);
  Combo.ItemIndex := 0;
  for Value in Values do
    if (Value <> '') and (Value = Current) then
      Combo.ItemIndex := Combo.Items.IndexOf(Value);
end;

procedure TProjectPages.BuildDefaults(Page: TWinControl);
begin
  AddHeading(Page, 'omp 기본값 (이 프로젝트, omp 다시 시작 후 반영)');
  FApproval := TComboBox.Create(Page);
  FApproval.Style := csDropDownList;
  AddRow(Page, 'omp 도구 승인', FApproval);
  FillChoices(FApproval, ApprovalModes, FSettings.OverlayText('tools.approvalMode'),
    FSettings.BaseText('tools.approvalMode'));
  FThinking := TComboBox.Create(Page);
  FThinking.Style := csDropDownList;
  AddRow(Page, '기본 생각 수준', FThinking);
  FillChoices(FThinking, ThinkingLevels, FSettings.OverlayText('defaultThinkingLevel'),
    FSettings.BaseText('defaultThinkingLevel'));
  AddNote(Page, 'omp 도구 승인은 채팅 입력 아래 승인 방식과 같은 값입니다. omp 자체 도구(bash, write 등)와 ' +
    'IDE 버퍼·폼을 바꾸는 rad.* 도구가 모두 이 값을 따릅니다.');
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
