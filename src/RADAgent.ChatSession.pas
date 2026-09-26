unit RADAgent.ChatSession;

{ One chat per IDE: owns the omp child and the transcript so the dock window can be closed,
  re-docked or rebuilt by a desktop switch without losing the conversation. The frame attaches
  as a view. Main thread only. }

interface

uses
  System.Classes, System.SysUtils, Vcl.ExtCtrls, RADAgent.Approval, RADAgent.RpcClient,
  RADAgent.RpcEvents, RADAgent.RpcResponses, RADAgent.ChatActivity, RADAgent.ChatStream,
  RADAgent.ChatCatalog, RADAgent.HostToolDefs;

type
  IChatView = interface
    ['{6B7E3A0C-4D21-4F58-9A1E-2C6D8B0F4E13}']
    procedure PageMessage(const Json: string);
    procedure SessionChanged;
  end;

  TChatSession = class
  private
    FClient: TAgentRpcClient;
    FView: IChatView;
    FApproval: IAgentApproval;
    FStream: TChatStream;
    FActivity: TChatActivity;
    FCommands: TArray<TSlashCommand>;
    FState: TStateInfo;
    FCatalog: TChatCatalog;
    FResumeFile: string;
    FStartError: string;
    FNotedNoProject, FSubscribed, FRestartPending: Boolean;
    FTimer: TTimer;
    procedure ClientStatus;
    procedure ClientEvent(const Event: TAgentEvent);
    procedure ClientResponse(const Line: string);
    procedure StateArrived(const Info: TStateInfo);
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    { Shows a page message on the attached view without keeping it in the transcript. }
    procedure PostToView(const Json: string);
    procedure Attach(const View: IChatView);
    procedure Detach(const View: IChatView);
    procedure EnsureStarted;
    procedure ProjectChanged;
    { Restarts omp on the same session file; Force also ends a running turn (stuck omp). }
    procedure Restart(Force: Boolean = False);
    { Restart after the running turn ends. }
    procedure RestartWhenIdle;
    { The project gained or lost forms: register the rad.* tools that fit it now. }
    procedure RefreshHostTools;
    function Connected: Boolean;
    function Busy: Boolean;
    procedure Notice(const Level, Text: string);
    procedure SendCommand(const FrameType, Frame: string);
    { Sends a prompt frame; on success shows DisplayText as the user's message. }
    function SendPrompt(const Message, DisplayText: string; const ImagesJson: string = ''): Boolean;
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
    property Approval: IAgentApproval read FApproval;
  end;

function ChatSession: TChatSession;
procedure FreeChatSession;

implementation

uses
  System.JSON, Winapi.Windows, RADAgent.Options, RADAgent.ChatCommand,
  RADAgent.ChatApproval, RADAgent.IdeContext, RADAgent.ChatTheme,
  RADAgent.ChatPageMessages, RADAgent.ChatAttention, RADAgent.ChatActions,
  RADAgent.AgentSettings, RADAgent.OmpSettings, RADAgent.OmpLaunch, RADAgent.ProjectProfile,
  RADAgent.ChatDiskSync, RADAgent.ChatStop, RADAgent.Lang;

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
  FApproval := TChatApproval.Create;
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
  { The client drops its queued callbacks when it is freed (FAlive, CheckSynchronize). }
  if FClient <> nil then
    FClient.SendAbort;
  FreeAndNil(FClient);
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
  Dir, Guide, Note, Extra: string;
  Tools: TToolProfile;
  Configs: TArray<string>;
begin
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
  begin
    if not FNotedNoProject then
      Notice('info', Tr('chatsession.noProject'));
    FNotedNoProject := True;
  end
  else
    FNotedNoProject := False;
  if (FClient <> nil) and (FClient.Pid <> 0) and (Dir <> '') and
    not SameText(ExcludeTrailingPathDelimiter(FClient.Cwd), Dir) then
  begin
    StopChild;
    FResumeFile := '';
    ClearTranscript;
    Notice('info', TrF('chatsession.projectDirChanged', [Dir]));
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
    FCatalog.LoadProject(OmpCommand, Dir);
    PrepareLaunch(ExistingOverlay(Dir), FCatalog.Project.BaseList('skills.customDirectories'), Tools,
      Configs, Guide, Note, Extra);
    FClient.ToolProfile := Tools;
    if Note <> '' then
      Notice('info', Note);
    if FClient.Start(OmpCommand, Dir, Configs, Guide, Extra) then
      FStartError := ''
    else
      FStartError := TrF('chatsession.processStartFailed', [GetLastError]);
  end;
  Changed;
end;

procedure TChatSession.Restart(Force: Boolean);
begin
  if Busy and not Force then
    Exit;
  FActivity.Reset;
  FRestartPending := False;
  FResumeFile := FState.SessionFile;
  StopChild;
  Notice('info', Tr('chatsession.restartingToApplySettings'));
  EnsureStarted;
end;

procedure TChatSession.RestartWhenIdle;
begin
  if Busy then
    FRestartPending := True
  else
    Restart;
end;

procedure TChatSession.RefreshHostTools;
begin
  if FClient <> nil then
    FClient.ResendHostTools(ActiveProfile.Tools);
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
  if (FClient <> nil) and FClient.Exited then
    RecoverExitedChild
  else if (FView <> nil) and not Connected then
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
    if ((Event.Kind = aekAgentEnd) and Event.IsTerminal) or (Event.Kind = aekPromptLocal) then
    begin
      Emit(PageTurnEnd);
      RequestAttention;
      if FRestartPending then
        Restart
      else
        SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
    end;
  { omp works on disk: load what its tools changed; refresh the todo panel after the todo tool. }
  SyncAfterEvent(Event);
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

function TChatSession.SendPrompt(const Message, DisplayText, ImagesJson: string): Boolean;
begin
  Result := Connected and FClient.SendPrompt(Message, ImagesJson);
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

end.
