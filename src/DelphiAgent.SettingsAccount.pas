unit DelphiAgent.SettingsAccount;

{ Settings page "계정·모델": model, thinking level and OAuth login of the running omp. Every
  action is an RPC command that applies at once. Main thread only. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TAccountPage = class(TComponent)
  private
    FModel, FLevel: TComboBox;
    FProviders: TListBox;
    FApply, FLogin: TButton;
    FTimer: TTimer;
    FSeenVersion: Integer;
    procedure Refill;
    procedure Poll(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure LoginClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; Page: TWinControl); reintroduce;
  end;

implementation

uses
  System.SysUtils, System.JSON, DelphiAgent.SettingsUi, DelphiAgent.ChatSession,
  DelphiAgent.ChatCommand, DelphiAgent.RpcResponses;

constructor TAccountPage.Create(AOwner: TComponent; Page: TWinControl);
var
  Row: TPanel;
begin
  inherited Create(AOwner);
  AddHeading(Page, '지금 대화의 모델 (바로 적용)');
  FModel := TComboBox.Create(Page);
  FModel.Style := csDropDownList;
  FModel.DropDownCount := 24;
  AddRow(Page, '모델', FModel);
  FLevel := TComboBox.Create(Page);
  FLevel.Style := csDropDownList;
  AddRow(Page, '생각 수준', FLevel);
  Row := AddButtons(Page);
  FApply := AddButton(Row, '지금 적용', ApplyClick);
  AddHeading(Page, '로그인 (OAuth)');
  FProviders := TListBox.Create(Page);
  FProviders.Height := 170;
  AddStacked(Page, FProviders);
  Row := AddButtons(Page);
  FLogin := AddButton(Row, '선택한 공급자로 로그인', LoginClick);
  AddNote(Page, '로그인을 누르면 브라우저가 열리고 코드 입력 창이 뜹니다. 브라우저에서 로그인을 마치거나, ' +
    '그만두려면 입력 창이나 이 버튼에서 취소하세요(omp를 같은 세션으로 다시 시작). 한 번에 하나만 진행됩니다.');
  AddNote(Page, 'API 키를 입력해야 하는 공급자는 omp가 RPC로 받지 않습니다. 터미널에서 omp를 실행한 뒤 ' +
    '/login으로 로그인하세요. DelphiAgent는 키를 저장하지 않습니다.');
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 300;
  FTimer.OnTimer := Poll;
  FSeenVersion := -1;
  ChatSession.RequestCatalog;
  Poll(nil);
end;

procedure SelectText(Combo: TComboBox; const Text: string);
begin
  Combo.ItemIndex := Combo.Items.IndexOf(Text);
end;

procedure TAccountPage.Refill;
var
  Session: TChatSession;
  Provider: TLoginProvider;
  Name: string;
begin
  Session := ChatSession;
  FModel.Items.BeginUpdate;
  try
    FModel.Items.Clear;
    for Name in Session.Catalog.Models do
      FModel.Items.Add(Name);
  finally
    FModel.Items.EndUpdate;
  end;
  SelectText(FModel, Session.State.Provider + '/' + Session.State.ModelId);
  FLevel.Items.Clear;
  for Name in Session.Catalog.ThinkingLevels do
    FLevel.Items.Add(Name);
  SelectText(FLevel, Session.State.ThinkingLevel);
  FProviders.Items.BeginUpdate;
  try
    FProviders.Items.Clear;
    for Provider in Session.Catalog.LoginProviders do
      if Provider.Authenticated then
        FProviders.Items.Add(Provider.Name + ' · 로그인됨')
      else
        FProviders.Items.Add(Provider.Name + ' · 로그인 안 됨');
  finally
    FProviders.Items.EndUpdate;
  end;
end;

procedure TAccountPage.Poll(Sender: TObject);
var
  Ready: Boolean;
begin
  Ready := ChatSession.Connected and not ChatSession.Busy and (ChatSession.Catalog.PendingLogin = '');
  FApply.Enabled := Ready;
  { omp has no command to stop a login; the button then restarts omp instead. }
  if ChatSession.Catalog.PendingLogin <> '' then
  begin
    FLogin.Caption := '로그인 취소: ' + ChatSession.Catalog.PendingLogin;
    FLogin.Enabled := True;
  end
  else
  begin
    FLogin.Caption := '선택한 공급자로 로그인';
    FLogin.Enabled := Ready and (FProviders.ItemIndex >= 0);
  end;
  if ChatSession.Catalog.Version = FSeenVersion then
    Exit;
  FSeenVersion := ChatSession.Catalog.Version;
  Refill;
end;

procedure TAccountPage.ApplyClick(Sender: TObject);
var
  Session: TChatSession;
  Selector: string;
  Slash: Integer;
begin
  Session := ChatSession;
  if FModel.ItemIndex >= 0 then
  begin
    Selector := FModel.Items[FModel.ItemIndex];
    Slash := Pos('/', Selector);
    if (Slash > 1) and (Selector <> Session.State.Provider + '/' + Session.State.ModelId) then
      Session.SendCommand('set_model', BuildSetModelFrame('req', Copy(Selector, 1, Slash - 1),
        Copy(Selector, Slash + 1, MaxInt)));
  end;
  if (FLevel.ItemIndex >= 0) and (FLevel.Items[FLevel.ItemIndex] <> Session.State.ThinkingLevel) then
    Session.SendCommand('set_thinking_level', BuildSetThinkingFrame('req', FLevel.Items[FLevel.ItemIndex]));
  { set_model changes the level list; ask again. }
  Session.RequestCatalog;
end;

procedure TAccountPage.LoginClick(Sender: TObject);
var
  Obj: TJSONObject;
  Providers: TArray<TLoginProvider>;
begin
  if ChatSession.Catalog.PendingLogin <> '' then
  begin
    ChatSession.Notice('info', ChatSession.Catalog.PendingLogin + ' 로그인을 취소했습니다.');
    ChatSession.Catalog.SetPendingLogin('');
    ChatSession.Restart;
    Exit;
  end;
  Providers := ChatSession.Catalog.LoginProviders;
  if (FProviders.ItemIndex < 0) or (FProviders.ItemIndex > High(Providers)) then
    Exit;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'login');
    Obj.AddPair('providerId', Providers[FProviders.ItemIndex].Id);
    ChatSession.SendCommand('login', Obj.ToJSON);
  finally
    Obj.Free;
  end;
  ChatSession.Catalog.SetPendingLogin(Providers[FProviders.ItemIndex].Name);
  ChatSession.Notice('info', Providers[FProviders.ItemIndex].Name + ' 로그인을 시작합니다.');
end;

end.
