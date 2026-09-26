unit RADAgent.SettingsDialog;

{ The chat's settings window. Tabs: chat display and RADAgent options (saved to the registry,
  applied at once), model/login (RPC, at once), and this project's omp overlay (roles,
  extensions, defaults; applied by restarting omp on the same session). Main thread only. }

interface

{ Page: tab to show first (0 Chat Display, 1 Account & Model, 2 Model Roles, 3 Extensions, 4 Advanced). }
procedure ShowSettings(Page: Integer = 0);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, System.UITypes, RADAgent.AskDialog, RADAgent.SettingsUi, RADAgent.SettingsAccount,
  RADAgent.SettingsProject, RADAgent.OmpSettings, RADAgent.AgentSettings,
  RADAgent.ChatSession, RADAgent.ChatTheme, RADAgent.IdeContext, RADAgent.Options,
  RADAgent.OmpCheck, RADAgent.Lang, RADAgent.ClangdInstall;

type
  TSettingsForm = class(TAgentForm)
  private
    FPages: TPageControl;
    FShows: TListView;
    FFontSize, FLanguage: TComboBox;
    FHighContrast, FEnglish, FTurnNotify: TCheckBox;
    FOmpPath, FOmpArgs, FClangd: TEdit;
    FClangdButton: TButton;
    FClangdStatus: TLabel;
    FProject: TOmpProjectSettings;
    FProjectPages: TProjectPages;
    function AddSheet(const Caption: string): TScrollBox;
    procedure BuildDisplay(Page: TWinControl);
    procedure BuildAdvanced(Page: TWinControl);
    procedure OkClick(Sender: TObject);
    procedure CheckOmpClick(Sender: TObject);
    procedure InstallClangdClick(Sender: TObject);
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
  Caption := Tr('settingsdialog.title');
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
  Button.Caption := Tr('settingsdialog.cancel');
  Button.ModalResult := mrCancel;
  Button.Cancel := True;
  Button.Width := 96;
  Button.Align := alRight;
  Button.Parent := Bottom;
  Button := TButton.Create(Self);
  Button.Caption := Tr('settingsdialog.ok');
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
  BuildDisplay(AddSheet(Tr('settingsdialog.tabDisplay')));
  TAccountPage.Create(Self, AddSheet(Tr('settingsdialog.tabAccount')));
  RolePage := AddSheet(Tr('settingsdialog.tabRoles'));
  ExtensionPage := AddSheet(Tr('settingsdialog.tabExtensions'));
  DefaultsPage := AddSheet(Tr('settingsdialog.tabAdvanced'));
  BuildAdvanced(DefaultsPage);
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
  begin
    AddNote(RolePage, Tr('settingsdialog.noActiveProjectRole'));
    AddNote(ExtensionPage, Tr('settingsdialog.noActiveProjectExtension'));
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
  AddNote(DefaultsPage, TrF('settingsdialog.overlayPath', [OverlayPath(Dir)]));
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
  Lang: TLanguage;
begin
  AddHeading(Page, Tr('settingsdialog.headingProgress'));
  FShows := AddCheckList(Page, 190);
  Shows := ChatShows;
  for Show := Low(TChatShow) to High(TChatShow) do
  begin
    Item := FShows.Items.Add;
    Item.Caption := ChatShowCaption(Show);
    Item.Checked := Show in Shows;
  end;
  AddNote(Page, Tr('settingsdialog.noteProgress'));
  AddHeading(Page, Tr('settingsdialog.headingAppearance'));
  FLanguage := TComboBox.Create(Page);
  FLanguage.Style := csDropDownList;
  AddRow(Page, Tr('settingsdialog.language'), FLanguage);
  FLanguage.Items.Add(TrF('settingsdialog.languageAuto', [LanguageNames[SystemLanguage]]));
  for Lang := lgEnglish to High(TLanguage) do
    FLanguage.Items.Add(LanguageNames[Lang]);
  if LanguageCode = '' then
    FLanguage.ItemIndex := 0
  else
    FLanguage.ItemIndex := Ord(LanguageFromCode(LanguageCode));
  FFontSize := TComboBox.Create(Page);
  FFontSize.Style := csDropDownList;
  AddRow(Page, Tr('settingsdialog.fontSize'), FFontSize);
  for Size := 11 to 18 do
    FFontSize.Items.Add(IntToStr(Size));
  FFontSize.ItemIndex := FFontSize.Items.IndexOf(IntToStr(ChatFontSize));
  FHighContrast := AddCheck(Page, Tr('settingsdialog.highContrast'));
  FHighContrast.Checked := HighContrastEnabled;
  FTurnNotify := AddCheck(Page, Tr('settingsdialog.turnNotify'));
  FTurnNotify.Checked := TurnNotifications;
end;

procedure TSettingsForm.BuildAdvanced(Page: TWinControl);
begin
  AddHeading(Page, Tr('settingsdialog.headingAgentAdvanced'));
  FOmpPath := TEdit.Create(Page);
  FOmpPath.TextHint := TrF('settingsdialog.ompPathHint', [OmpExecutable]);
  FOmpPath.Text := OmpPathOverride;
  AddRow(Page, Tr('settingsdialog.ompPath'), FOmpPath);
  FOmpArgs := TEdit.Create(Page);
  FOmpArgs.TextHint := Tr('settingsdialog.ompArgsHint');
  FOmpArgs.Text := OmpExtraArgs;
  AddRow(Page, Tr('settingsdialog.ompArgs'), FOmpArgs);
  FClangd := TEdit.Create(Page);
  FClangd.TextHint := Tr('settingsdialog.clangdHint');
  FClangd.Text := ClangdPath;
  AddRow(Page, Tr('settingsdialog.clangdPath'), FClangd);
  FClangdButton := AddButton(AddButtons(Page), Tr('settingsdialog.btnInstallClangd'), InstallClangdClick);
  FClangdStatus := AddNote(Page, Tr('settingsdialog.noteInstallClangd'));
  if IsClangdInstalling then
  begin
    FClangdButton.Enabled := False;
    FClangdStatus.Caption := Tr('settingsdialog.installingClangd');
  end;
  FEnglish := AddCheck(Page, Tr('settingsdialog.englishWork'));
  FEnglish.Checked := EnglishWork;
  AddHeading(Page, Tr('settingsdialog.headingCompatibility'));
  AddButton(AddButtons(Page), Tr('settingsdialog.btnCheckOmp'), CheckOmpClick);
  AddNote(Page, Tr('settingsdialog.noteCompatibility'));
end;

var
  { The open settings dialog, for a clangd download that finishes while it is shown. }
  GOpenForm: TSettingsForm;

procedure TSettingsForm.InstallClangdClick(Sender: TObject);
begin
  if IsClangdInstalling then
    Exit;
  if not AskYes(Tr('settingsdialog.btnInstallClangd'), Tr('settingsdialog.askInstallClangd')) then
    Exit;
  FClangdButton.Enabled := False;
  FClangdStatus.Caption := Tr('settingsdialog.installingClangd');
  InstallClangd(
    procedure(const Path, Version, Problem: string)
    begin
      if Path <> '' then
        ChatSession.Notice('info', TrF('settingsdialog.clangdInstalled', [Version, Path]))
      else
        ChatSession.Notice('warn', TrF('settingsdialog.clangdInstallFailed', [Problem]));
      { Closed meanwhile: keep the path and restart omp with it. Open: OK saves it. }
      if GOpenForm = nil then
      begin
        if Path <> '' then
        begin
          SetClangdPath(Path);
          ChatSession.RestartWhenIdle;
        end;
        Exit;
      end;
      GOpenForm.FClangdButton.Enabled := True;
      if Path <> '' then
      begin
        GOpenForm.FClangd.Text := Path;
        GOpenForm.FClangdStatus.Caption := TrF('settingsdialog.clangdInstalled', [Version, Path]);
      end
      else
        GOpenForm.FClangdStatus.Caption := TrF('settingsdialog.clangdInstallFailed', [Problem]);
    end);
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
  ShowReport(Tr('settingsdialog.checkOmpTitle'), Report);
end;

procedure TSettingsForm.OkClick(Sender: TObject);
var
  Show: TChatShow;
  Shows: TChatShows;
  Restart: Boolean;
  Before, After, ChosenLang: string;
begin
  Shows := [];
  for Show := Low(TChatShow) to High(TChatShow) do
    if FShows.Items[Ord(Show)].Checked then
      Include(Shows, Show);
  SetChatShows(Shows);
  if (FLanguage.ItemIndex > 0) and (FLanguage.ItemIndex <= Ord(High(TLanguage))) then
    ChosenLang := LanguageCodes[TLanguage(FLanguage.ItemIndex)]
  else
    ChosenLang := '';
  if ChosenLang <> LanguageCode then
    SetLanguageCode(ChosenLang);
  if FFontSize.ItemIndex >= 0 then
    SetChatFontSize(StrToInt(FFontSize.Items[FFontSize.ItemIndex]));
  SetHighContrast(FHighContrast.Checked);
  SetTurnNotifications(FTurnNotify.Checked);
  Restart := (Trim(FOmpPath.Text) <> OmpPathOverride) or (Trim(FOmpArgs.Text) <> OmpExtraArgs) or
    (FEnglish.Checked <> EnglishWork) or (Trim(FClangd.Text) <> ClangdPath);
  SetClangdPath(FClangd.Text);
  SetEnglishWork(FEnglish.Checked);
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
    Restart := Restart or (Before <> After) or FProjectPages.FormEditingChanged;
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
    ChatSession.Notice('info', Tr('settingsdialog.noticeRestartPending'));
  end
  else if AskYes(Tr('settingsdialog.askRestartTitle'), Tr('settingsdialog.askRestartPrompt')) then
    ChatSession.Restart
  else
    ChatSession.Notice('info', Tr('settingsdialog.noticeSaved'));
end;

procedure ShowSettings(Page: Integer);
var
  Form: TSettingsForm;
begin
  Form := TSettingsForm.CreateDialog;
  try
    ThemeForm(Form);
    GOpenForm := Form;
    if (Page >= 0) and (Page < Form.FPages.PageCount) then
      Form.FPages.ActivePageIndex := Page;
    Form.ShowModal;
  finally
    GOpenForm := nil;
    Form.Free;
  end;
end;

end.
