unit RADAgent.SettingsAccount;

{ Settings page "Account & Model": model, thinking level and OAuth login of the running omp. Every
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
  System.SysUtils, System.JSON, RADAgent.SettingsUi, RADAgent.ChatSession,
  RADAgent.ChatCommand, RADAgent.RpcResponses, RADAgent.Lang, RADAgent.BrandTable,
  RADAgent.BrandIcons;

constructor TAccountPage.Create(AOwner: TComponent; Page: TWinControl);
var
  Row: TPanel;
begin
  inherited Create(AOwner);
  AddHeading(Page, Tr('settingsaccount.headingModel'));
  FModel := TComboBox.Create(Page);
  FModel.Style := csDropDownList;
  FModel.DropDownCount := 24;
  MakeBrandCombo(FModel);
  AddRow(Page, Tr('settingsaccount.model'), FModel);
  FLevel := TComboBox.Create(Page);
  FLevel.Style := csDropDownList;
  AddRow(Page, Tr('settingsaccount.thinkingLevel'), FLevel);
  Row := AddButtons(Page);
  FApply := AddButton(Row, Tr('settingsaccount.btnApplyNow'), ApplyClick);
  AddHeading(Page, Tr('settingsaccount.headingLogin'));
  FProviders := TListBox.Create(Page);
  FProviders.Height := 170;
  MakeBrandList(FProviders);
  AddStacked(Page, FProviders);
  Row := AddButtons(Page);
  FLogin := AddButton(Row, Tr('settingsaccount.btnLoginSelected'), LoginClick);
  AddNote(Page, Tr('settingsaccount.noteLogin'));
  AddNote(Page, Tr('settingsaccount.noteApiKey'));
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
      AddBrandItem(FModel.Items, Name, SelectorBrand(Name));
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
        AddBrandItem(FProviders.Items, TrF('settingsaccount.providerLoggedIn', [Provider.Name]),
          ProviderBrand(Provider.Id))
      else
        AddBrandItem(FProviders.Items, TrF('settingsaccount.providerNotLoggedIn', [Provider.Name]),
          ProviderBrand(Provider.Id));
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
    FLogin.Caption := TrF('settingsaccount.cancelLoginFormat', [ChatSession.Catalog.PendingLogin]);
    FLogin.Enabled := True;
  end
  else
  begin
    FLogin.Caption := Tr('settingsaccount.btnLoginSelected');
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
    ChatSession.Notice('info', TrF('settingsaccount.noticeLoginCancelled', [ChatSession.Catalog.PendingLogin]));
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
  ChatSession.Notice('info', TrF('settingsaccount.noticeLoginStarting', [Providers[FProviders.ItemIndex].Name]));
end;

end.
