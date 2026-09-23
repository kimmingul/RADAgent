unit DelphiAgent.DockForm;
{ Chat frame embedded by the IDE's dockable form. A view over DelphiAgent.ChatSession: toolbar,
  WebView2 transcript, editor context bar, multi-line input and two-line status. }
interface
uses
  System.Classes, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls,
  DelphiAgent.ChatSession, DelphiAgent.ChatInput, DelphiAgent.WebView2Host;
type
  TDelphiAgentChatFrame = class(TFrame, IChatView)
  private
    FTop, FFooter, FContext, FBottom, FButtons, FStatus: TPanel;
    FNewSession, FSessions, FExport, FSettings, FSend, FStop, FCompile, FFile: TButton;
    FIncludeSelection: TCheckBox;
    FContextLabel, FStatusLine, FDetailLine: TLabel;
    FWeb: TWebView2Host;
    FFallback: TMemo;
    FInput: TChatInput;
    FTimer: TTimer;
    FAttached: Boolean;
    function MakeButton(Parent: TWinControl; const Caption: string; Handler: TNotifyEvent): TButton;
    function MakeLabel(Parent: TWinControl; Align: TAlign): TLabel;
    procedure BuildUi;
    procedure ApplyTheme;
    procedure ThemeChanged;
    procedure RefreshContext;
    procedure LayoutInput(Sender: TObject);
    procedure WebFailed(Sender: TObject);
    procedure WebMessage(const Json: string);
    procedure Submit(const Text: string);
    procedure TimerTick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure CompileClick(Sender: TObject);
    procedure FileClick(Sender: TObject);
    procedure NewSessionClick(Sender: TObject);
    procedure SessionsClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    { IChatView }
    procedure PageMessage(const Json: string);
    procedure SessionChanged;
  public
    destructor Destroy; override;
    procedure HostFrameCreated;
    procedure FocusInput;
  end;
{ Shows the chat, puts Text in the input and sends it when the session can take it. }
procedure SendFromIde(const Text: string);
implementation
{$R *.dfm}
uses
  System.SysUtils, System.JSON, System.Math, Winapi.Windows, Winapi.ShellAPI, Vcl.Graphics,
  Vcl.Dialogs, Vcl.Clipbrd, DelphiAgent.ChatActions, DelphiAgent.ChatTheme, DelphiAgent.AskDialog,
  DelphiAgent.EditorContext, DelphiAgent.ChatFallback, DelphiAgent.SettingsDialog;
var
  GActiveFrame: TDelphiAgentChatFrame;
function TDelphiAgentChatFrame.MakeButton(Parent: TWinControl; const Caption: string;
  Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Parent;
  Result.Caption := Caption;
  Result.OnClick := Handler;
  Result.Height := ScaleValue(26);
  Result.Width := ScaleValue(Max(64, Length(Caption) * 14 + 20));
end;
function TDelphiAgentChatFrame.MakeLabel(Parent: TWinControl; Align: TAlign): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Parent;
  Result.Align := Align;
  Result.AutoSize := False;
  Result.Layout := tlCenter;
  Result.ShowHint := True;
  Result.Height := ScaleValue(20);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(6), 0, ScaleValue(6), 0);
end;
procedure TDelphiAgentChatFrame.BuildUi;
  function Panel(Owner: TWinControl; Align: TAlign; Height: Integer): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := Owner;
    Result.Align := Align;
    Result.BevelOuter := bvNone;
    Result.Height := ScaleValue(Height);
    Result.ParentBackground := False;
  end;
begin
  Font.Name := 'Malgun Gothic';
  Font.Size := 9;
  FTop := Panel(Self, alTop, 32);
  FTop.Padding.SetBounds(ScaleValue(4), ScaleValue(3), ScaleValue(4), ScaleValue(3));
  FNewSession := MakeButton(FTop, '새 세션', NewSessionClick);
  FSessions := MakeButton(FTop, '세션 목록', SessionsClick);
  FExport := MakeButton(FTop, '내보내기', ExportClick);
  FNewSession.Align := alLeft;
  FSessions.Align := alLeft;
  FExport.Align := alLeft;
  FSessions.Left := FNewSession.Left + FNewSession.Width;
  FExport.Left := FSessions.Left + FSessions.Width;
  FSettings := MakeButton(FTop, '설정', SettingsClick);
  FSettings.Align := alRight;
  { Footer children align inside one panel, so resizing the input never reorders them. }
  FFooter := Panel(Self, alBottom, 44 + 84 + 24);
  FStatus := Panel(FFooter, alBottom, 44);
  FDetailLine := MakeLabel(FStatus, alBottom);
  FDetailLine.EllipsisPosition := epPathEllipsis;
  FStatusLine := MakeLabel(FStatus, alClient);
  FStatusLine.EllipsisPosition := epEndEllipsis;
  FContext := Panel(FFooter, alTop, 24);
  FBottom := Panel(FFooter, alClient, 84);
  FBottom.Padding.SetBounds(ScaleValue(4), ScaleValue(2), ScaleValue(4), ScaleValue(2));
  FButtons := TPanel.Create(Self);
  FButtons.Parent := FBottom;
  FButtons.Align := alRight;
  FButtons.BevelOuter := bvNone;
  FButtons.Width := ScaleValue(150);
  FSend := MakeButton(FButtons, '보내기', SendClick);
  FSend.SetBounds(ScaleValue(4), 0, ScaleValue(142), ScaleValue(28));
  FStop := MakeButton(FButtons, '중지', StopClick);
  FStop.SetBounds(ScaleValue(4), ScaleValue(30), ScaleValue(46), ScaleValue(26));
  FCompile := MakeButton(FButtons, '컴파일', CompileClick);
  FCompile.SetBounds(ScaleValue(52), ScaleValue(30), ScaleValue(46), ScaleValue(26));
  FFile := MakeButton(FButtons, '파일', FileClick);
  FFile.SetBounds(ScaleValue(100), ScaleValue(30), ScaleValue(46), ScaleValue(26));
  FInput := TChatInput.Create(Self);
  FInput.Parent := FBottom;
  FInput.Align := alClient;
  FInput.OnSubmit := Submit;
  FInput.OnHeightWanted := LayoutInput;
  FIncludeSelection := TCheckBox.Create(Self);
  FIncludeSelection.Parent := FContext;
  FIncludeSelection.Align := alRight;
  FIncludeSelection.Width := ScaleValue(120);
  FIncludeSelection.Caption := '선택 영역 포함';
  FContextLabel := MakeLabel(FContext, alClient);
  FContextLabel.EllipsisPosition := epEndEllipsis;
  FWeb := TWebView2Host.Create(Self);
  { Handlers first: setting Parent creates the handle and may fail synchronously. }
  FWeb.OnMessage := WebMessage;
  FWeb.OnFailed := WebFailed;
  FWeb.Align := alClient;
  FWeb.Parent := Self;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 700;
  FTimer.OnTimer := TimerTick;
end;
procedure TDelphiAgentChatFrame.ApplyTheme;
var
  Palette: TChatPalette;
begin
  Palette := CurrentPalette;
  Color := Palette.Bg;
  ParentBackground := False;
  ApplyVclTheme(Self);
  FWeb.SetBackColor(Palette.Bg);
  FContextLabel.Font.Color := Palette.Muted;
  FDetailLine.Font.Color := Palette.Muted;
end;
procedure TDelphiAgentChatFrame.ThemeChanged;
begin
  ApplyTheme;
  ChatSession.ThemeChanged;
end;
procedure TDelphiAgentChatFrame.HostFrameCreated;
begin
  if FAttached then
    Exit;
  BuildUi;
  ApplyTheme;
  InstallThemeWatch(ThemeChanged);
  GActiveFrame := Self;
  FAttached := True;
  ChatSession.Attach(Self);
  FTimer.Enabled := True;
end;
destructor TDelphiAgentChatFrame.Destroy;
begin
  if FAttached then
  begin
    ChatSession.Detach(Self);
    RemoveThemeWatch;
  end;
  if GActiveFrame = Self then
    GActiveFrame := nil;
  inherited Destroy;
end;
procedure TDelphiAgentChatFrame.PageMessage(const Json: string);
begin
  if FFallback <> nil then
    AppendFallback(FFallback, Json)
  else
    FWeb.PostJson(Json);
end;
procedure TDelphiAgentChatFrame.WebFailed(Sender: TObject);
begin
  { Keep chatting in plain text when WebView2 cannot start; say why once. }
  FWeb.Visible := False;
  FFallback := CreateFallback(Self, FWeb.Problem);
  { Replay the transcript as text; before HostFrameCreated the attach there does it. }
  if FAttached then
    ChatSession.Attach(Self);
end;
procedure TDelphiAgentChatFrame.WebMessage(const Json: string);
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Kind, Url: string;
begin
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if not (Value is TJSONObject) then
      Exit;
    Obj := TJSONObject(Value);
    Kind := Obj.GetValue<string>('t', '');
    if Kind = 'openFile' then
    begin
      if not OpenFileAtLine(Obj.GetValue<string>('path', ''), Obj.GetValue<Integer>('line', 0)) then
        ChatSession.Notice('warn', '파일을 열지 못했습니다: ' + Obj.GetValue<string>('path', ''));
    end
    else if Kind = 'openUrl' then
    begin
      Url := Obj.GetValue<string>('url', '');
      if Url.StartsWith('http://', True) or Url.StartsWith('https://', True) then
        ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
    end
    else if Kind = 'copy' then
      Clipboard.AsText := Obj.GetValue<string>('text', '');
  finally
    Value.Free;
  end;
end;
procedure TDelphiAgentChatFrame.SessionChanged;
var
  Session: TChatSession;
begin
  Session := ChatSession;
  FStatusLine.Caption := SessionStatusLine;
  FStatusLine.Hint := FStatusLine.Caption;
  FDetailLine.Caption := SessionDetailLine;
  FDetailLine.Hint := FDetailLine.Caption;
  FSend.Enabled := Session.Connected and not Session.Busy;
  FStop.Enabled := Session.Busy;
  FNewSession.Enabled := Session.Connected and not Session.Busy;
  FSessions.Enabled := FNewSession.Enabled and (Session.State.SessionFile <> '');
  FExport.Enabled := Session.Connected;
  FInput.SetCommands(Session.Commands);
end;
procedure TDelphiAgentChatFrame.RefreshContext;
var
  Info: TEditorInfo;
  Text: string;
  Unsaved: Integer;
begin
  Info := ActiveEditorInfo;
  if Info.FileName = '' then
    Text := '열린 파일 없음'
  else
    Text := ExtractFileName(Info.FileName);
  if Info.HasSelection then
    Text := Text + Format(' · 선택 %d–%d줄', [Info.StartLine, Info.EndLine]);
  Unsaved := UnsavedModuleCount;
  if Unsaved > 0 then
    Text := Text + Format(' · 저장 안 한 파일 %d개', [Unsaved]);
  FContextLabel.Caption := Text;
  FContextLabel.Hint := Info.FileName;
  FIncludeSelection.Enabled := Info.HasSelection;
end;
procedure TDelphiAgentChatFrame.TimerTick(Sender: TObject);
begin
  RefreshContext;
end;
procedure TDelphiAgentChatFrame.LayoutInput(Sender: TObject);
begin
  FFooter.Height := FContext.Height + FStatus.Height + Max(ScaleValue(62),
    FInput.WantedLines * Abs(FInput.Font.Height) * 3 div 2 + ScaleValue(14));
end;
procedure TDelphiAgentChatFrame.Submit(const Text: string);
var
  Info: TEditorInfo;
  Attachment, AttachmentLabel: string;
begin
  Attachment := '';
  AttachmentLabel := '';
  if FIncludeSelection.Checked and FIncludeSelection.Enabled then
  begin
    Info := ActiveEditorInfo;
    Attachment := SelectionAttachment(Info);
    if Attachment <> '' then
      AttachmentLabel := Format('%s %d–%d줄 선택 영역 포함', [ExtractFileName(Info.FileName),
        Info.StartLine, Info.EndLine]);
  end;
  if SubmitChat(Text, Attachment, AttachmentLabel) then
  begin
    FInput.Clear;
    FIncludeSelection.Checked := False;
  end;
end;
procedure TDelphiAgentChatFrame.SendClick(Sender: TObject);
begin
  Submit(Trim(FInput.Text));
  FocusInput;
end;
procedure TDelphiAgentChatFrame.StopClick(Sender: TObject);
begin
  if ChatSession.Client <> nil then
    ChatSession.Client.SendAbort;
end;
procedure TDelphiAgentChatFrame.CompileClick(Sender: TObject);
begin
  CompileActiveProject;
end;
procedure TDelphiAgentChatFrame.FileClick(Sender: TObject);
var
  Path: string;
begin
  if not AskOpenFile(Path) then
    Exit;
  if FInput.Text = '' then
    FInput.Text := Path
  else
    FInput.Text := FInput.Text + ' ' + Path;
end;
procedure TDelphiAgentChatFrame.NewSessionClick(Sender: TObject);
begin
  StartNewSession;
end;
procedure TDelphiAgentChatFrame.SessionsClick(Sender: TObject);
begin
  PickSession;
end;
procedure TDelphiAgentChatFrame.ExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Filter := 'HTML (*.html)|*.html';
    Dialog.DefaultExt := 'html';
    Dialog.FileName := 'DelphiAgent-' + FormatDateTime('yyyymmdd-hhnn', Now) + '.html';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      ExportConversation(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;
procedure TDelphiAgentChatFrame.SettingsClick(Sender: TObject);
begin
  ShowSettings;
  { Font size and high contrast change the frame too. }
  ThemeChanged;
end;
procedure TDelphiAgentChatFrame.FocusInput;
begin
  if FInput.CanFocus then
    FInput.SetFocus;
end;
procedure SendFromIde(const Text: string);
begin
  if GActiveFrame = nil then
    Exit;
  GActiveFrame.FInput.Text := Text;
  GActiveFrame.FocusInput;
  if ChatSession.Connected and not ChatSession.Busy then
    GActiveFrame.Submit(Text);
end;
end.
