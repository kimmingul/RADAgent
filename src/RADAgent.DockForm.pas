unit RADAgent.DockForm;
{ Chat frame embedded by the IDE's dockable form. A view over RADAgent.ChatSession: the whole
  chat (top bar, transcript, composer) is the WebView2 page; this frame only hosts it, feeds it
  state and carries out its requests. A plain text chat replaces it when WebView2 cannot start. }
interface
uses
  System.Classes, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls,
  RADAgent.ChatSession, RADAgent.ChatInput, RADAgent.WebView2Host;
type
  TStateKind = (skStatus, skCatalog, skCommands, skContext);
  TRADAgentChatFrame = class(TFrame, IChatView)
  private
    FWeb: TWebView2Host;
    FFallback: TMemo;
    FFallbackInput: TChatInput;
    FFallbackStop: TButton;
    FTimer: TTimer;
    FAttached: Boolean;
    FLangGen: Integer;
    FLastSent: array[TStateKind] of string;
    procedure ApplyTheme;
    procedure ThemeChanged;
    procedure WebFailed(Sender: TObject);
    procedure WebMessage(const Json: string);
    procedure WebReady(Sender: TObject);
    procedure Push(Kind: TStateKind; const Json: string);
    procedure PushState;
    procedure TimerTick(Sender: TObject);
    procedure BuildFallbackInput;
    procedure FallbackSubmit(const Text: string);
    procedure FallbackSend(Sender: TObject);
    procedure FallbackStop(Sender: TObject);
    { IChatView }
    procedure PageMessage(const Json: string);
    procedure SessionChanged;
  public
    destructor Destroy; override;
    procedure HostFrameCreated;
    procedure FocusInput;
  end;
{ Shows the chat and sends Text when the session can take it; otherwise leaves it in the input. }
procedure SendFromIde(const Text: string);
implementation
{$R *.dfm}
uses
  System.SysUtils, System.JSON, RADAgent.ChatTheme, RADAgent.ChatFallback,
  RADAgent.ChatStatus, RADAgent.ChatPageCommands, RADAgent.ChatApprovalCard,
  RADAgent.Lang, RADAgent.ChatPageMessages, RADAgent.ChatStop;
var
  GActiveFrame: TRADAgentChatFrame;
procedure TRADAgentChatFrame.ApplyTheme;
var
  Palette: TChatPalette;
begin
  Palette := CurrentPalette;
  Color := Palette.Bg;
  ParentBackground := False;
  ApplyVclTheme(Self);
  FWeb.SetBackColor(Palette.Bg);
end;
procedure TRADAgentChatFrame.ThemeChanged;
var
  Kind: TStateKind;
begin
  ApplyTheme;
  ChatSession.ThemeChanged;
  if LanguageGeneration <> FLangGen then
  begin
    FLangGen := LanguageGeneration;
    if FFallback = nil then
    begin
      FWeb.PostJson(PageClear);
      FWeb.PostJson(PageStrings);
      ChatSession.Attach(Self);
      for Kind := Low(TStateKind) to High(TStateKind) do
        FLastSent[Kind] := '';
    end;
  end;
end;
procedure TRADAgentChatFrame.HostFrameCreated;
begin
  if FAttached then
    Exit;
  Font.Name := 'Malgun Gothic';
  Font.Size := 9;
  FWeb := TWebView2Host.Create(Self);
  { Handlers first: setting Parent creates the handle and may fail synchronously. }
  FWeb.OnMessage := WebMessage;
  FWeb.OnFailed := WebFailed;
  FWeb.OnPageReady := WebReady;
  FWeb.Align := alClient;
  FWeb.Parent := Self;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 700;
  FTimer.OnTimer := TimerTick;
  ApplyTheme;
  InstallThemeWatch(ThemeChanged);
  GActiveFrame := Self;
  FAttached := True;
  FWeb.PostJson(PageStrings);
  FLangGen := LanguageGeneration;
  ChatSession.Attach(Self);
  FTimer.Enabled := True;
end;
destructor TRADAgentChatFrame.Destroy;
begin
  if FAttached then
  begin
    SetInChatApprovals(False);
    ChatSession.Detach(Self);
    RemoveThemeWatch;
  end;
  if GActiveFrame = Self then
    GActiveFrame := nil;
  inherited Destroy;
end;
procedure TRADAgentChatFrame.PageMessage(const Json: string);
begin
  if FFallback <> nil then
    AppendFallback(FFallback, Json)
  else
    FWeb.PostJson(Json);
end;
{ The page keeps only the latest of each state message; skip unchanged ones. }
procedure TRADAgentChatFrame.Push(Kind: TStateKind; const Json: string);
begin
  if (FFallback <> nil) or (Json = FLastSent[Kind]) then
    Exit;
  FLastSent[Kind] := Json;
  FWeb.PostJson(Json);
end;
procedure TRADAgentChatFrame.PushState;
begin
  Push(skStatus, PageStatus);
  Push(skCatalog, PageCatalog);
  Push(skCommands, PageCommands);
end;
procedure TRADAgentChatFrame.SessionChanged;
begin
  PushState;
  if FFallbackInput <> nil then
  begin
    FFallbackInput.SetCommands(ChatSession.Commands);
    FFallbackStop.Enabled := ChatSession.Busy;
  end;
end;
procedure TRADAgentChatFrame.TimerTick(Sender: TObject);
begin
  PushState;
  Push(skContext, PageContext);
end;
procedure TRADAgentChatFrame.WebReady(Sender: TObject);
var
  Kind: TStateKind;
begin
  FWeb.PostJson(PageStrings);
  SetInChatApprovals(True);
  { A reloaded page starts empty: send every state again. }
  for Kind := Low(TStateKind) to High(TStateKind) do
    FLastSent[Kind] := '';
  TimerTick(nil);
end;
procedure TRADAgentChatFrame.WebMessage(const Json: string);
begin
  case HandlePageRequest(Json) of
    paThemeChanged:
      ThemeChanged;
    paRefresh:
      PushState;
  end;
end;
procedure TRADAgentChatFrame.WebFailed(Sender: TObject);
begin
  { Keep chatting in plain text when WebView2 cannot start; say why once. }
  SetInChatApprovals(False);
  FWeb.Visible := False;
  BuildFallbackInput;
  FFallback := CreateFallback(Self, FWeb.Problem);
  { Replay the transcript as text; before HostFrameCreated the attach there does it. }
  if FAttached then
    ChatSession.Attach(Self);
end;
procedure TRADAgentChatFrame.BuildFallbackInput;
var
  Bottom: TPanel;
  Send: TButton;
begin
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(72);
  Bottom.BevelOuter := bvNone;
  Send := TButton.Create(Self);
  Send.Parent := Bottom;
  Send.Align := alRight;
  Send.Caption := Tr('dockform.send');
  Send.OnClick := FallbackSend;
  FFallbackStop := TButton.Create(Self);
  FFallbackStop.Parent := Bottom;
  FFallbackStop.Align := alRight;
  FFallbackStop.Caption := Tr('dockform.stop');
  FFallbackStop.OnClick := FallbackStop;
  FFallbackInput := TChatInput.Create(Self);
  FFallbackInput.Parent := Bottom;
  FFallbackInput.Align := alClient;
  FFallbackInput.OnSubmit := FallbackSubmit;
end;
procedure TRADAgentChatFrame.FallbackSubmit(const Text: string);
begin
  if SubmitFromPage(Text, False) then
    FFallbackInput.Clear;
end;
procedure TRADAgentChatFrame.FallbackSend(Sender: TObject);
begin
  FallbackSubmit(Trim(FFallbackInput.Text));
end;
procedure TRADAgentChatFrame.FallbackStop(Sender: TObject);
begin
  StopTurn;
end;
procedure TRADAgentChatFrame.FocusInput;
begin
  if FFallbackInput <> nil then
  begin
    if FFallbackInput.CanFocus then
      FFallbackInput.SetFocus;
    Exit;
  end;
  if FWeb.CanFocus then
    FWeb.SetFocus;
  FWeb.PostJson('{"t":"focusInput"}');
end;
procedure SendFromIde(const Text: string);
var
  Obj: TJSONObject;
begin
  if GActiveFrame = nil then
    Exit;
  GActiveFrame.FocusInput;
  if ChatSession.Connected and not ChatSession.Busy and SubmitFromPage(Text, False) then
    Exit;
  if GActiveFrame.FFallbackInput <> nil then
  begin
    GActiveFrame.FFallbackInput.Text := Text;
    Exit;
  end;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'setInput');
    Obj.AddPair('text', Text);
    GActiveFrame.FWeb.PostJson(Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;
end.
