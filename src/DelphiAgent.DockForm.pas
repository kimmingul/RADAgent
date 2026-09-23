unit DelphiAgent.DockForm;
{ Chat frame embedded by the IDE's dockable form. A view over DelphiAgent.ChatSession: the whole
  chat (top bar, transcript, composer) is the WebView2 page; this frame only hosts it, feeds it
  state and carries out its requests. A plain text chat replaces it when WebView2 cannot start. }
interface
uses
  System.Classes, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls,
  DelphiAgent.ChatSession, DelphiAgent.ChatInput, DelphiAgent.WebView2Host;
type
  TStateKind = (skStatus, skCatalog, skCommands, skContext);
  TDelphiAgentChatFrame = class(TFrame, IChatView)
  private
    FWeb: TWebView2Host;
    FFallback: TMemo;
    FFallbackInput: TChatInput;
    FFallbackStop: TButton;
    FTimer: TTimer;
    FAttached: Boolean;
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
  System.SysUtils, System.JSON, DelphiAgent.ChatTheme, DelphiAgent.ChatFallback,
  DelphiAgent.ChatStatus, DelphiAgent.ChatPageCommands, DelphiAgent.ChatApprovalCard;
var
  GActiveFrame: TDelphiAgentChatFrame;
procedure TDelphiAgentChatFrame.ApplyTheme;
var
  Palette: TChatPalette;
begin
  Palette := CurrentPalette;
  Color := Palette.Bg;
  ParentBackground := False;
  ApplyVclTheme(Self);
  FWeb.SetBackColor(Palette.Bg);
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
  ChatSession.Attach(Self);
  FTimer.Enabled := True;
end;
destructor TDelphiAgentChatFrame.Destroy;
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
procedure TDelphiAgentChatFrame.PageMessage(const Json: string);
begin
  if FFallback <> nil then
    AppendFallback(FFallback, Json)
  else
    FWeb.PostJson(Json);
end;
{ The page keeps only the latest of each state message; skip unchanged ones. }
procedure TDelphiAgentChatFrame.Push(Kind: TStateKind; const Json: string);
begin
  if (FFallback <> nil) or (Json = FLastSent[Kind]) then
    Exit;
  FLastSent[Kind] := Json;
  FWeb.PostJson(Json);
end;
procedure TDelphiAgentChatFrame.PushState;
begin
  Push(skStatus, PageStatus);
  Push(skCatalog, PageCatalog);
  Push(skCommands, PageCommands);
end;
procedure TDelphiAgentChatFrame.SessionChanged;
begin
  PushState;
  if FFallbackInput <> nil then
  begin
    FFallbackInput.SetCommands(ChatSession.Commands);
    FFallbackStop.Enabled := ChatSession.Busy;
  end;
end;
procedure TDelphiAgentChatFrame.TimerTick(Sender: TObject);
begin
  PushState;
  Push(skContext, PageContext);
end;
procedure TDelphiAgentChatFrame.WebReady(Sender: TObject);
var
  Kind: TStateKind;
begin
  SetInChatApprovals(True);
  { A reloaded page starts empty: send every state again. }
  for Kind := Low(TStateKind) to High(TStateKind) do
    FLastSent[Kind] := '';
  TimerTick(nil);
end;
procedure TDelphiAgentChatFrame.WebMessage(const Json: string);
begin
  case HandlePageRequest(Json) of
    paThemeChanged:
      ThemeChanged;
    paRefresh:
      PushState;
  end;
end;
procedure TDelphiAgentChatFrame.WebFailed(Sender: TObject);
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
procedure TDelphiAgentChatFrame.BuildFallbackInput;
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
  Send.Caption := '보내기';
  Send.OnClick := FallbackSend;
  FFallbackStop := TButton.Create(Self);
  FFallbackStop.Parent := Bottom;
  FFallbackStop.Align := alRight;
  FFallbackStop.Caption := '중지';
  FFallbackStop.OnClick := FallbackStop;
  FFallbackInput := TChatInput.Create(Self);
  FFallbackInput.Parent := Bottom;
  FFallbackInput.Align := alClient;
  FFallbackInput.OnSubmit := FallbackSubmit;
end;
procedure TDelphiAgentChatFrame.FallbackSubmit(const Text: string);
begin
  if SubmitFromPage(Text, False) then
    FFallbackInput.Clear;
end;
procedure TDelphiAgentChatFrame.FallbackSend(Sender: TObject);
begin
  FallbackSubmit(Trim(FFallbackInput.Text));
end;
procedure TDelphiAgentChatFrame.FallbackStop(Sender: TObject);
begin
  if ChatSession.Client <> nil then
    ChatSession.Client.SendAbort;
end;
procedure TDelphiAgentChatFrame.FocusInput;
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
