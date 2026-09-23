unit DelphiAgent.ChatSession;

{ One chat per IDE: owns the omp child and the transcript so the dock window can be closed,
  re-docked or rebuilt by a desktop switch without losing the conversation. The frame attaches
  as a view. Main thread only. }

interface

uses
  System.Classes, System.SysUtils, Vcl.ExtCtrls, DelphiAgent.Approval, DelphiAgent.RpcClient,
  DelphiAgent.RpcEvents, DelphiAgent.RpcResponses, DelphiAgent.ChatActivity, DelphiAgent.ChatStream,
  DelphiAgent.ChatCatalog;

type
  IChatView = interface
    ['{6B7E3A0C-4D21-4F58-9A1E-2C6D8B0F4E13}']
    procedure PageMessage(const Json: string);
    procedure SessionChanged;
  end;

  TChatSession = class(TNoRefCountObject, IAgentApproval)
  private
    FClient: TAgentRpcClient;
    FView: IChatView;
    FStream: TChatStream;
    FActivity: TChatActivity;
    FCommands: TArray<TSlashCommand>;
    FState: TStateInfo;
    FCatalog: TChatCatalog;
    FResumeFile: string;
    FStartError: string;
    FNotedNoProject, FSubscribed, FRestartPending: Boolean;
    FTimer: TTimer;
    procedure PostToView(const Json: string);
    procedure ClientStatus;
    procedure ClientEvent(const Event: TAgentEvent);
    procedure ClientResponse(const Line: string);
    procedure StateArrived(const Info: TStateInfo);
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(const View: IChatView);
    procedure Detach(const View: IChatView);
    procedure EnsureStarted;
    procedure ProjectChanged;
    { Restarts omp with the current settings and reopens the same session file. }
    procedure Restart;
    { Restart after the running turn ends. }
    procedure RestartWhenIdle;
    function Connected: Boolean;
    function Busy: Boolean;
    procedure Notice(const Level, Text: string);
    procedure SendCommand(const FrameType, Frame: string);
    { Sends a prompt frame; on success shows DisplayText as the user's message. }
    function SendPrompt(const Message, DisplayText: string): Boolean;
    { Shows a slash command the chat handled locally. }
    procedure ShowUserText(const Text: string);
    { Adds a page message to the transcript and the attached view. }
    procedure Emit(const Json: string);
    procedure ClearTranscript;
    procedure Changed;
    procedure ThemeChanged;
    { Sends the display options to the page and the matching subagent subscription to omp. }
    procedure DisplayChanged;
    { Asks omp for models, thinking levels and login providers; CatalogVersion bumps on replies. }
    procedure RequestCatalog;
    property Client: TAgentRpcClient read FClient;
    property State: TStateInfo read FState;
    property StartError: string read FStartError;
    property Commands: TArray<TSlashCommand> read FCommands;
    property Activity: TChatActivity read FActivity;
    property Catalog: TChatCatalog read FCatalog;
    function ApproveChange(const Target, Before, After: string): Boolean;
    procedure ShowConflict(const FileName: string);
  end;

function ChatSession: TChatSession;
procedure FreeChatSession;

implementation

uses
  System.JSON, Winapi.Windows, DelphiAgent.Options, DelphiAgent.ChatCommand,
  DelphiAgent.ApprovalDialog, DelphiAgent.IdeContext, DelphiAgent.ChatTheme,
  DelphiAgent.ChatPageMessages, DelphiAgent.ChatAttention, DelphiAgent.ChatActions,
  DelphiAgent.AgentSettings, DelphiAgent.OmpSettings;

const
  SNoProject = '활성 프로젝트가 없습니다. 프로젝트를 열면 그 폴더에서 omp를 시작합니다.';

var
  GSession: TChatSession;

function ChatSession: TChatSession;
begin
  if GSession = nil then
    GSession := TChatSession.Create;
  Result := GSession;
end;

procedure FreeChatSession;
begin
  FreeAndNil(GSession);
end;

constructor TChatSession.Create;
begin
  inherited Create;
  FStream := TChatStream.Create(PostToView);
  FCatalog := TChatCatalog.Create;
  FActivity := TChatActivity.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 1000;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  InstallProjectWatch(ProjectChanged);
end;

destructor TChatSession.Destroy;
begin
  FTimer.Free;
  RemoveProjectWatch;
  FView := nil;
  if FClient <> nil then
  begin
    FClient.OnLog := nil;
    FClient.OnStatus := nil;
    FClient.OnHostTool := nil;
    FClient.OnUi := nil;
    FClient.OnResponse := nil;
    FClient.OnAgentEvent := nil;
    FClient.SendAbort;
    FreeAndNil(FClient);
  end;
  FActivity.Free;
  FCatalog.Free;
  FStream.Free;
  inherited Destroy;
end;

procedure TChatSession.PostToView(const Json: string);
begin
  if FView <> nil then
    FView.PageMessage(Json);
end;

procedure TChatSession.Emit(const Json: string);
begin
  FStream.Emit(Json);
end;

procedure TChatSession.Notice(const Level, Text: string);
begin
  Emit(PageNotice(Level, Text));
end;

procedure TChatSession.Changed;
begin
  if FView <> nil then
    FView.SessionChanged;
end;

procedure TChatSession.ClearTranscript;
begin
  FStream.Clear;
  FActivity.Reset;
  Emit(PageClear);
end;

procedure TChatSession.Attach(const View: IChatView);
var
  Json: string;
begin
  FView := View;
  View.PageMessage(PaletteJson(CurrentPalette));
  View.PageMessage(PageDisplay(ChatShows));
  for Json in FStream.Replay do
    View.PageMessage(Json);
  EnsureStarted;
  View.SessionChanged;
end;

procedure TChatSession.Detach(const View: IChatView);
begin
  if FView = View then
    FView := nil;
end;

procedure TChatSession.ThemeChanged;
begin
  PostToView(PaletteJson(CurrentPalette));
  Changed;
end;

procedure TChatSession.DisplayChanged;
const
  Levels: array[Boolean] of string = ('off', 'progress');
begin
  PostToView(PageDisplay(ChatShows));
  if not Connected then
    Exit;
  SendCommand('set_subagent_subscription', BuildTypeFieldFrame('set_subagent_subscription', 'level',
    Levels[csSubagents in ChatShows]));
  FSubscribed := True;
end;

procedure TChatSession.RequestCatalog;
begin
  FCatalog.Request(SendCommand);
end;

function TChatSession.Connected: Boolean;
begin
  Result := (FClient <> nil) and FClient.Ready and FClient.HostToolsSent;
end;

function TChatSession.Busy: Boolean;
begin
  Result := FActivity.Busy;
end;

procedure TChatSession.EnsureStarted;
var
  Dir: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
  begin
    if not FNotedNoProject then
      Notice('info', SNoProject);
    FNotedNoProject := True;
  end
  else
    FNotedNoProject := False;
  if (FClient <> nil) and (FClient.Pid <> 0) and (Dir <> '') and
    not SameText(ExcludeTrailingPathDelimiter(FClient.Cwd), Dir) then
  begin
    FClient.Stop;
    FResumeFile := '';
    ClearTranscript;
    Notice('info', '프로젝트 폴더가 바뀌어 omp를 다시 시작합니다: ' + Dir);
  end;
  if FClient = nil then
  begin
    FClient := TAgentRpcClient.Create;
    FClient.OnLog := procedure(const Text: string) begin Notice('warn', Text); end;
    FClient.OnStatus := ClientStatus;
    FClient.OnHostTool := HandleHostToolCall;
    FClient.OnUi := HandleUiRequest;
    FClient.OnResponse := ClientResponse;
    FClient.OnAgentEvent := ClientEvent;
  end;
  if FClient.Pid = 0 then
  begin
    if Dir = '' then
      Dir := GetCurrentDir;
    FState := Default(TStateInfo);
    FSubscribed := False;
    if FClient.Start(OmpCommand, Dir, ExistingOverlay(Dir), OmpExtraArgs) then
      FStartError := ''
    else
      FStartError := '프로세스 시작 실패 ' + IntToStr(GetLastError);
  end;
  Changed;
end;

procedure TChatSession.Restart;
begin
  if Busy then
    Exit;
  FRestartPending := False;
  FResumeFile := FState.SessionFile;
  if FClient <> nil then
    FClient.Stop;
  Notice('info', '설정을 적용하려고 omp를 다시 시작합니다.');
  EnsureStarted;
end;

procedure TChatSession.RestartWhenIdle;
begin
  if Busy then
    FRestartPending := True
  else
    Restart;
end;

procedure TChatSession.ProjectChanged;
begin
  if (FClient <> nil) and (FClient.Pid <> 0) then
    EnsureStarted
  else
    Changed;
end;

procedure TChatSession.Tick(Sender: TObject);
begin
  if (FView <> nil) and not Connected then
    EnsureStarted
  else if Busy then
    Changed;
end;

procedure TChatSession.SendCommand(const FrameType, Frame: string);
begin
  if FClient <> nil then
    FClient.SendRaw(FrameType, Frame);
end;

procedure TChatSession.ClientStatus;
begin
  if Connected and not FSubscribed then
  begin
    DisplayChanged;
    FCatalog.Request(SendCommand);
  end;
  if Connected and (FResumeFile <> '') then
  begin
    SendCommand('switch_session', BuildTypeFieldFrame('switch_session', 'sessionPath', FResumeFile));
    FResumeFile := '';
  end
  else if Connected and (FState.SessionFile = '') then
    SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
  Changed;
end;

procedure TChatSession.ClientEvent(const Event: TAgentEvent);
begin
  FActivity.Apply(Event);
  if not FStream.Apply(Event) then
    if (Event.Kind = aekAgentEnd) and Event.IsTerminal then
    begin
      Emit(PageTurnEnd);
      RequestAttention;
      if FRestartPending then
        Restart
      else
        SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
    end;
  if (Event.Kind = aekToolEnd) and (Event.ToolName = 'todo') then
    SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
  Changed;
end;

procedure TChatSession.StateArrived(const Info: TStateInfo);
begin
  FState := Info;
  FStream.ShowTodos(Info.Todos);
  FCatalog.Touch;
  Changed;
end;

procedure TChatSession.ClientResponse(const Line: string);
var
  Cmds: TArray<TSlashCommand>;
  Info: TStateInfo;
begin
  { Out parameters reset managed values, so parse into locals. }
  if ParseAvailableCommands(Line, Cmds) then
  begin
    FCommands := Cmds;
    Changed;
  end
  else if ParseStateInfo(Line, Info) then
    StateArrived(Info)
  else
  begin
    FCatalog.Accept(Line);
    { Also the /model picker, which asks for the same model list. }
    HandleCommandResponse(Line);
  end;
end;

function TChatSession.SendPrompt(const Message, DisplayText: string): Boolean;
begin
  Result := Connected and FClient.SendPrompt(Message);
  if not Result then
    Exit;
  Emit(PageUser(DisplayText));
  FActivity.PromptSent;
  Changed;
end;

procedure TChatSession.ShowUserText(const Text: string);
begin
  Emit(PageUser(Text));
end;

function TChatSession.ApproveChange(const Target, Before, After: string): Boolean;
begin
  RequestAttention;
  Result := AskApprovalDiff(Target, Before, After);
end;

procedure TChatSession.ShowConflict(const FileName: string);
begin
  Notice('warn', '충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다. ' + FileName);
end;

end.
