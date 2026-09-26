unit RADAgent.ChatActions;

{ User actions on the chat session (send, compile, sessions, export, omp approval mode) and the
  replies to the commands they send. Main thread only. }

interface

{ Prompt or slash command. Attachment goes to omp only; AttachmentLabel is shown in the chat. }
{ ImagesJson: ImageContent[] for attached pictures, or ''. }
{ While omp works, a prompt joins the running turn: at its next step, or after it (FollowUp). }
function SubmitChat(const Text, Attachment, AttachmentLabel: string; const ImagesJson: string = '';
  FollowUp: Boolean = False): Boolean;
procedure CompileActiveProject;
procedure StartNewSession;
procedure PickSession;
procedure ExportConversation(const Path: string);
{ Saves this project's omp tools.approvalMode and restarts omp (after the turn if busy). }
procedure SetApprovalMode(const Mode: string);
{ Response frames not handled by the session itself. }
procedure HandleCommandResponse(const Line: string);
{ Runs a host tool on the main thread with the session as the approval owner. }
procedure HandleHostToolCall(const CallId, ToolName, ArgumentsJson: string);
{ omp extension UI (select/confirm/input) as modal dialogs. }
procedure HandleUiRequest(const Line: string);

implementation

uses
  System.SysUtils, System.JSON, RADAgent.ChatSession, RADAgent.RpcResponses,
  RADAgent.RpcProtocol, RADAgent.ChatCommand, RADAgent.AskDialog,
  RADAgent.IdeContext, RADAgent.Compile, RADAgent.AgentSettings,
  RADAgent.ChatPageMessages, RADAgent.Sessions, RADAgent.Options, RADAgent.HostTools,
  RADAgent.OmpSettings, RADAgent.HostToolDefs, RADAgent.ChatPlan, RADAgent.ChatBtw,
  RADAgent.ChatDiskSync, RADAgent.ChatCheckpoints, RADAgent.RpcJson, RADAgent.ChatSlash, RADAgent.ChatQueue, RADAgent.ChatUsage,
  RADAgent.ChatTurnTime, RADAgent.Lang;

var
  GPickModel: Boolean;
  GHistory: TArray<THistoryItem>;

{ False, with a notice, when a file could not be saved: omp would work on outdated files. }
function SaveBeforeSend: Boolean;
begin
  Result := SaveProject;
  if not Result then
    ChatSession.Notice('error', Tr('chatactions.notSentUnsaved'));
end;
function SubmitChat(const Text, Attachment, AttachmentLabel, ImagesJson: string; FollowUp: Boolean): Boolean;
var
  Session: TChatSession;
  Arg1, Arg2, Display: string;
  PickModels: Boolean;
  Seq: Integer;
begin
  Session := ChatSession;
  Result := False;
  { Side questions run in their own omp child, also while the agent is busy. }
  if Text.StartsWith('/btw ', True) then
  begin
    AskBtw(Copy(Trim(Text), 5, MaxInt), '');
    Exit(True);
  end;
  if not Session.Connected or (Trim(Text) = '') then
    Exit;
  { RADAgent's own commands (settings, copy, ...) also work while omp is busy. }
  if Text.TrimLeft.StartsWith('/') and RunLocalSlash(Text) then
    Exit(True);
  Display := Text;
  if AttachmentLabel <> '' then
    Display := Display + sLineBreak + '(' + AttachmentLabel + ')';
  if Session.Busy or ShellRunning then
  begin
    if ShellRunning or Text.TrimLeft.StartsWith('/') or Text.TrimLeft.StartsWith('!') then
    begin
      Session.Notice('warn', Tr('chatslash.busy'));
      Exit;
    end;
    if not SaveBeforeSend then
      Exit;
    Seq := CheckpointBeforePrompt(Text + Attachment);
    Result := QueueMessage(Text + Attachment, Display, ImagesJson, FollowUp);
    if Result and (Seq > 0) then
      Session.Emit(PageCheckpoint(Seq));
    Exit;
  end;
  { omp reads and edits files on disk: they must hold what the IDE shows. }
  if not SaveBeforeSend then
    Exit;
  if Text.TrimLeft.StartsWith('!') then
    Exit(RunShell(Copy(Trim(Text), 2, MaxInt)));
  if ClassifyChat(Text, Arg1, Arg2) = ccPrompt then
  begin
    Seq := CheckpointBeforePrompt(Text + Attachment);
    Result := Session.SendPrompt(Text + Attachment, Display, ImagesJson);
    if Result and (Seq > 0) then
      Session.Emit(PageCheckpoint(Seq))
    else if not Result then
      Session.Notice('error', Tr('chatactions.sendFailed'));
    Exit;
  end;
  if DispatchSlash(Text, Session.SendCommand, PickModels) then
  begin
    GPickModel := PickModels;
    Session.ShowUserText(Text);
    Exit(True);
  end;
  Result := Session.SendPrompt(Text, Text);
end;

procedure CompileActiveProject;
var
  Json: string;
begin
  if CurrentProject = nil then
  begin
    ReportNoProject;
    ChatSession.Notice('warn', Tr('chatactions.noProjectToCompile'));
    Exit;
  end;
  ChatSession.Notice('info', Tr('chatactions.compiling'));
  Json := BuildActiveProjectJson;
  if Json.Contains('"ok":true') then
    ChatSession.Notice('info', Tr('chatactions.compileSuccess'))
  else
    ChatSession.Notice('error', Tr('chatactions.compileFailed'));
end;

procedure StartNewSession;
begin
  if ChatSession.Connected and not ChatSession.Busy and
    AskYes(Tr('chatactions.newSessionTitle'), Tr('chatactions.newSessionConfirm')) then
    ChatSession.SendCommand('new_session', BuildIdTypeFrame('req', 'new_session'));
end;

procedure PickSession;
var
  Path: string;
  Obj: TJSONObject;
begin
  if not ChatSession.Connected or ChatSession.Busy then
    Exit;
  Path := ChooseSession(ListSessions(ChatSession.State.SessionFile));
  if (Path = '') or SameText(Path, ChatSession.State.SessionFile) then
    Exit;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'switch_session');
    Obj.AddPair('sessionPath', Path);
    ChatSession.SendCommand('switch_session', Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

procedure ExportConversation(const Path: string);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'export_html');
    Obj.AddPair('outputPath', Path);
    ChatSession.SendCommand('export_html', Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

procedure SetApprovalMode(const Mode: string);
var
  Project: TOmpProjectSettings;
begin
  if Mode = 'plan' then
  begin
    EnterPlanMode(ChatSession.Catalog.ApprovalMode);
    Exit;
  end;
  if PlanActive and (Mode = ChatSession.Catalog.ApprovalMode) then
  begin
    LeavePlanMode(Mode, '');
    ChatSession.Notice('info', Tr('chatactions.planModeExited'));
    Exit;
  end;
  if PlanActive then
    LeavePlanMode(Mode, '');
  Project := ChatSession.Catalog.Project;
  if (Project = nil) or (Mode = ChatSession.Catalog.ApprovalMode) then
    Exit;
  { A value equal to omp's own drops the override. }
  if Mode = Project.BaseText('tools.approvalMode') then
    Project.SetOverlayText('tools.approvalMode', '')
  else
    Project.SetOverlayText('tools.approvalMode', Mode);
  Project.Save;
  { IDE changes follow the same mode at once; omp itself picks it up after the restart. }
  ChatSession.Catalog.SetApprovalMode(Mode);
  if Mode = 'yolo' then
    ChatSession.Notice('warn', Tr('chatactions.approvalModeYolo'))
  else if Mode = 'write' then
    ChatSession.Notice('info', Tr('chatactions.approvalModeWrite'))
  else
    ChatSession.Notice('info', Tr('chatactions.approvalModeAsk'));
  ChatSession.RestartWhenIdle;
end;

function BranchText(const Line: string): string;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Line);
  try
    Result := JsonStr(JsonChild(Obj, 'data'), 'text');
  finally
    Obj.Free;
  end;
end;

function PageSetInput(const Text: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'setInput');
    Obj.AddPair('text', Text);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure LoadHistoryPage(const Cursor: string);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'get_messages_page');
    Obj.AddPair('limit', TJSONNumber.Create(256));
    if Cursor <> '' then
      Obj.AddPair('cursor', Cursor);
    ChatSession.SendCommand('get_messages_page', Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

procedure RefreshState;
begin
  ChatSession.SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
end;

procedure HandleCommandResponse(const Line: string);
var
  Command, Provider, ModelId, Cursor, FollowUp: string;
  Items: TArray<THistoryItem>;
  Root: TJSONValue;
  Ok: Boolean;
begin
  if HandleSlashResponse(Line) or HandleShellResponse(Line) or HandleUsageResponse(Line) then
    Exit;
  Root := TJSONObject.ParseJSONValue(Line);
  try
    if not (Root is TJSONObject) then
      Exit;
    Command := TJSONObject(Root).GetValue<string>('command', '');
    Ok := TJSONObject(Root).GetValue<Boolean>('success', False);
  finally
    Root.Free;
  end;
  if not Ok then
    Exit;
  if (Command = 'get_available_models') and GPickModel then
  begin
    GPickModel := False;
    if ChooseModel(ModelListText(Line), Provider, ModelId) then
      ChatSession.SendCommand('set_model', BuildSetModelFrame('req', Provider, ModelId));
  end
  else if Command = 'new_session' then
  begin
    ChatSession.ClearTranscript;
    ChatSession.Notice('info', Tr('chatactions.newSessionStarted'));
    RefreshState;
  end
  else if Command = 'get_entries' then
    HandleEntries(Line)
  else if (Command = 'switch_session') or (Command = 'branch') then
  begin
    { branch: going back to a checkpoint; its message goes back into the input box. }
    if Command = 'branch' then
      ChatSession.PostToView(PageSetInput(BranchText(Line)));
    ChatSession.ClearTranscript;
    GHistory := nil;
    RefreshState;
    LoadHistoryPage('');
  end
  else if ParseMessagesPage(Line, Items, Cursor) then
  begin
    GHistory := GHistory + Items;
    if Cursor <> '' then
      LoadHistoryPage(Cursor)
    else
    begin
      AttachCheckpoints(GHistory);
      AttachTurnTimes(GHistory);
      ChatSession.Emit(PageHistory(GHistory));
      FollowUp := TakeRestoreNotice;
      if FollowUp <> '' then
        ChatSession.Notice('info', FollowUp);
      ChatSession.Notice('info', TrF('chatactions.sessionLoaded', [Length(GHistory)]));
      GHistory := nil;
      { A plan the user approved goes out once the restarted omp has the history back. }
      FollowUp := TakeFollowUp;
      if FollowUp <> '' then
        SubmitChat(FollowUp, '', '');
    end;
  end
  else if (Command = 'set_model') or (Command = 'set_thinking_level') or (Command = 'set_fast_mode') then
    RefreshState
  else if Command = 'export_html' then
    ChatSession.Notice('info', Tr('chatactions.exportedHtml'))
  else if Command = 'login' then
  begin
    ChatSession.Notice('info', Tr('chatactions.loggedIn'));
    ChatSession.RequestCatalog;
  end;
end;

procedure HandleHostToolCall(const CallId, ToolName, ArgumentsJson: string);
var
  Session: TChatSession;
  Text, Image: string;
  IsError: Boolean;
  Generation: Integer;
begin
  Session := ChatSession;
  if (Session.Client = nil) or Session.Client.WasCancelled(CallId) then
    Exit;
  { Approvals pump messages: the child that asked may be gone (restart, project switch) when the
    tool returns, and its call id means nothing to the next one. }
  Generation := Session.Client.Generation;
  Image := '';
  if PlanActive and IsChangingTool(ToolName) then
  begin
    Text := 'The IDE cannot be modified in plan mode. Investigate only, and submit the plan via rad.submit_plan.';
    IsError := True;
  end
  else
    ExecuteHostTool(ToolName, ArgumentsJson, Session.Approval, Text, IsError, Image);
  if (Session.Client = nil) or (Session.Client.Generation <> Generation) then
    Exit;
  { A first form makes the form tools available. }
  if (ToolName = ToolNewModule) and not IsError then
    Session.RefreshHostTools;
  { The DelphiLSP settings are named after the project: omp gets them anew after the turn. }
  if (ToolName = ToolRenameProject) and not IsError then
    Session.RestartWhenIdle;
  { omp works on disk: what the IDE just changed must be there before omp reads it. }
  if IsChangingTool(ToolName) and not IsError and not SaveProject then
    Text := Text + sLineBreak + 'Warning: the change is in the IDE but could not be saved to disk, so ' +
      'files on disk may be outdated. Ask the user to save before reading or editing them.';
  if not Session.Client.WasCancelled(CallId) then
    Session.Client.SendHostResult(CallId, Text, IsError, Image);
end;

procedure HandleUiRequest(const Line: string);
var
  Reply, Text: string;
  Cancelled: Boolean;
  Generation: Integer;
begin
  if ChatSession.Client = nil then
    Exit;
  Generation := ChatSession.Client.Generation;
  if not ExtensionReply(Line, Reply, Text, Cancelled) then
    Exit;
  { The dialog or card pumped messages; a reply for a child that is gone must not reach the next. }
  if ChatSession.Client.Generation <> Generation then
    Exit;
  { omp re-asks for the code after a cancel and has no command to stop a login; only a restart
    ends it. The session resumes on the same file. }
  if Cancelled and (ChatSession.Catalog.PendingLogin <> '') then
  begin
    ChatSession.Notice('info', TrF('chatactions.loginCancelled', [ChatSession.Catalog.PendingLogin]));
    ChatSession.Catalog.SetPendingLogin('');
    ChatSession.Restart;
    Exit;
  end;
  if Text <> '' then
    ChatSession.Notice('info', Text);
  if Reply <> '' then
    ChatSession.SendCommand('extension_ui_response', Reply);
end;

end.
