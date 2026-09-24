unit DelphiAgent.SettingsDialog;

{ The chat's settings window. Tabs: chat display and DelphiAgent options (saved to the registry,
  applied at once), model/login (RPC, at once), and this project's omp overlay (roles,
  extensions, defaults; applied by restarting omp on the same session). Main thread only. }

interface

{ Page: tab to show first (0 채팅 표시, 1 계정·모델, 2 역할별 모델, 3 확장, 4 고급). }
procedure ShowSettings(Page: Integer = 0);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, System.UITypes, DelphiAgent.AskDialog, DelphiAgent.SettingsUi, DelphiAgent.SettingsAccount,
  DelphiAgent.SettingsProject, DelphiAgent.OmpSettings, DelphiAgent.AgentSettings,
  DelphiAgent.ChatSession, DelphiAgent.ChatTheme, DelphiAgent.IdeContext, DelphiAgent.Options,
  DelphiAgent.OmpCheck, Vcl.Dialogs;

type
  TSettingsForm = class(TForm)
  private
    FPages: TPageControl;
    FShows: TListView;
    FFontSize: TComboBox;
    FHighContrast: TCheckBox;
    FOmpPath, FOmpArgs: TEdit;
    FProject: TOmpProjectSettings;
    FProjectPages: TProjectPages;
    function AddSheet(const Caption: string): TScrollBox;
    procedure BuildDisplay(Page: TWinControl);
    procedure BuildAdvanced(Page: TWinControl);
    procedure OkClick(Sender: TObject);
    procedure CheckOmpClick(Sender: TObject);
  public
    constructor CreateDialog;
    destructor Destroy; override;
  end;

function TSettingsForm.AddSheet(const Caption: string): TScrollBox;
var
  Sheet: TTabSheet;
begin
  Sheet := TTabSheet.Create(Self);
  Sheet.PageControl := FPages;
  Sheet.Caption := Caption;
  Result := TScrollBox.Create(Self);
  Result.Parent := Sheet;
  Result.Align := alClient;
  Result.BorderStyle := bsNone;
  Result.VertScrollBar.Tracking := True;
end;

constructor TSettingsForm.CreateDialog;
var
  Bottom: TPanel;
  Button: TButton;
  Dir: string;
  RolePage, ExtensionPage, DefaultsPage: TWinControl;
begin
  CreateNew(nil);
  Caption := 'DelphiAgent 설정';
  Position := poMainFormCenter;
  BorderStyle := bsSizeable;
  Width := 640;
  Height := 620;
  Font.Name := 'Malgun Gothic';
  Font.Size := 9;
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 40;
  Bottom.BevelOuter := bvNone;
  Bottom.Padding.SetBounds(0, 6, 10, 8);
  { alRight: the first button created sits rightmost. }
  Button := TButton.Create(Self);
  Button.Caption := '취소';
  Button.ModalResult := mrCancel;
  Button.Cancel := True;
  Button.Width := 96;
  Button.Align := alRight;
  Button.Parent := Bottom;
  Button := TButton.Create(Self);
  Button.Caption := '확인';
  Button.Default := True;
  Button.OnClick := OkClick;
  Button.Width := 96;
  Button.Align := alRight;
  Button.AlignWithMargins := True;
  Button.Margins.SetBounds(0, 0, 8, 0);
  Button.Left := 0;
  Button.Parent := Bottom;
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  BuildDisplay(AddSheet('채팅 표시'));
  TAccountPage.Create(Self, AddSheet('계정·모델'));
  RolePage := AddSheet('역할별 모델');
  ExtensionPage := AddSheet('확장');
  DefaultsPage := AddSheet('고급');
  BuildAdvanced(DefaultsPage);
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
  begin
    AddNote(RolePage, '활성 프로젝트가 없습니다. 프로젝트를 열면 이 프로젝트용 omp 설정을 바꿀 수 있습니다.');
    AddNote(ExtensionPage, '활성 프로젝트가 없습니다.');
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    FProject := TOmpProjectSettings.Create(OmpCommand, Dir);
    FProjectPages := TProjectPages.Create(Self, FProject, RolePage, ExtensionPage, DefaultsPage,
      ChatSession.Catalog.Models);
  finally
    Screen.Cursor := crDefault;
  end;
  AddNote(DefaultsPage, '이 프로젝트의 omp 설정 파일: ' + OverlayPath(Dir));
end;

destructor TSettingsForm.Destroy;
begin
  inherited Destroy;
  FProject.Free;
end;

procedure TSettingsForm.BuildDisplay(Page: TWinControl);
var
  Show: TChatShow;
  Shows: TChatShows;
  Item: TListItem;
  Size: Integer;
begin
  AddHeading(Page, '채팅에 보여 줄 omp 진행 내용');
  FShows := AddCheckList(Page, 190);
  Shows := ChatShows;
  for Show := Low(TChatShow) to High(TChatShow) do
  begin
    Item := FShows.Items.Add;
    Item.Caption := ChatShowCaptions[Show];
    Item.Checked := Show in Shows;
  end;
  AddNote(Page, '끈 항목은 채팅에서 숨깁니다. 다시 켜면 지난 내용도 보입니다. 오류와 승인 요청은 항상 보입니다.');
  AddHeading(Page, '모양');
  FFontSize := TComboBox.Create(Page);
  FFontSize.Style := csDropDownList;
  AddRow(Page, '글자 크기', FFontSize);
  for Size := 11 to 18 do
    FFontSize.Items.Add(IntToStr(Size));
  FFontSize.ItemIndex := FFontSize.Items.IndexOf(IntToStr(ChatFontSize));
  FHighContrast := AddCheck(Page, '고대비');
  FHighContrast.Checked := HighContrastEnabled;
end;

procedure TSettingsForm.BuildAdvanced(Page: TWinControl);
begin
  AddHeading(Page, 'DelphiAgent (이 PC, omp 다시 시작 후 반영)');
  FOmpPath := TEdit.Create(Page);
  FOmpPath.TextHint := '비우면 PATH에서 찾음: ' + OmpExecutable;
  FOmpPath.Text := OmpPathOverride;
  AddRow(Page, 'omp 실행 파일', FOmpPath);
  FOmpArgs := TEdit.Create(Page);
  FOmpArgs.TextHint := '예: --no-lsp';
  FOmpArgs.Text := OmpExtraArgs;
  AddRow(Page, 'omp 추가 인자', FOmpArgs);
  AddHeading(Page, 'omp 호환성');
  AddButton(AddButtons(Page), 'omp 호환성 검사', CheckOmpClick);
  AddNote(Page, 'omp를 업데이트하면 처음 시작할 때 자동으로 검사합니다. DelphiAgent가 쓰는 명령줄 옵션, ' +
    'RPC 프로토콜, IDE 도구 등록, 응답 필드를 확인하며 모델은 부르지 않습니다.');
end;

procedure TSettingsForm.CheckOmpClick(Sender: TObject);
var
  Dir, Report: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
    Dir := GetCurrentDir;
  Screen.Cursor := crHourGlass;
  try
    Report := OmpCheckReport(Dir);
  finally
    Screen.Cursor := crDefault;
  end;
  MessageDlg('omp 호환성 검사' + sLineBreak + sLineBreak + Report, mtInformation, [mbOK], 0);
end;

procedure TSettingsForm.OkClick(Sender: TObject);
var
  Show: TChatShow;
  Shows: TChatShows;
  Restart: Boolean;
  Before, After: string;
begin
  Shows := [];
  for Show := Low(TChatShow) to High(TChatShow) do
    if FShows.Items[Ord(Show)].Checked then
      Include(Shows, Show);
  SetChatShows(Shows);
  if FFontSize.ItemIndex >= 0 then
    SetChatFontSize(StrToInt(FFontSize.Items[FFontSize.ItemIndex]));
  SetHighContrast(FHighContrast.Checked);
  Restart := (Trim(FOmpPath.Text) <> OmpPathOverride) or (Trim(FOmpArgs.Text) <> OmpExtraArgs);
  SetOmpPathOverride(FOmpPath.Text);
  SetOmpExtraArgs(FOmpArgs.Text);
  if FProjectPages <> nil then
  begin
    Before := '';
    if FileExists(OverlayPath(FProject.ProjectDir)) then
      Before := TFile.ReadAllText(OverlayPath(FProject.ProjectDir));
    FProjectPages.Store;
    FProject.Save;
    After := '';
    if FileExists(OverlayPath(FProject.ProjectDir)) then
      After := TFile.ReadAllText(OverlayPath(FProject.ProjectDir));
    Restart := Restart or (Before <> After);
    { The + menu edits the same file through the catalog's copy; keep it current. }
    if Before <> After then
      ChatSession.Catalog.LoadProject(OmpCommand, FProject.ProjectDir);
  end;
  ChatSession.ThemeChanged;
  ChatSession.DisplayChanged;
  ModalResult := mrOk;
  if not Restart then
    Exit;
  if ChatSession.Busy then
  begin
    ChatSession.RestartWhenIdle;
    ChatSession.Notice('info', 'omp 설정을 저장했습니다. 지금 작업이 끝나면 omp를 다시 시작합니다.');
  end
  else if AskYes('omp 다시 시작', 'omp 설정이 바뀌었습니다. 지금 omp를 다시 시작할까요? 대화는 같은 세션으로 이어집니다.') then
    ChatSession.Restart
  else
    ChatSession.Notice('info', 'omp 설정을 저장했습니다. omp를 다시 시작하면 반영됩니다.');
end;

procedure ShowSettings(Page: Integer);
var
  Form: TSettingsForm;
begin
  Form := TSettingsForm.CreateDialog;
  try
    if (Page >= 0) and (Page < Form.FPages.PageCount) then
      Form.FPages.ActivePageIndex := Page;
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
