unit DelphiAgent.ChatActions;

{ User actions on the chat session (send, compile, sessions, export, omp approval mode) and the
  replies to the commands they send. Main thread only. }

interface

{ Prompt or slash command. Attachment goes to omp only; AttachmentLabel is shown in the chat. }
{ ImagesJson: ImageContent[] for attached pictures, or ''. }
function SubmitChat(const Text, Attachment, AttachmentLabel: string; const ImagesJson: string = ''): Boolean;
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
  System.SysUtils, System.JSON, DelphiAgent.ChatSession, DelphiAgent.RpcResponses,
  DelphiAgent.RpcProtocol, DelphiAgent.ChatCommand, DelphiAgent.AskDialog,
  DelphiAgent.IdeContext, DelphiAgent.Compile, DelphiAgent.AgentSettings,
  DelphiAgent.ChatPageMessages, DelphiAgent.Sessions, DelphiAgent.Options, DelphiAgent.HostTools,
  DelphiAgent.OmpSettings, DelphiAgent.HostToolDefs, DelphiAgent.ChatPlan, DelphiAgent.ChatBtw,
  DelphiAgent.ChatDiskSync, DelphiAgent.ChatCheckpoints, DelphiAgent.RpcJson;

var
  GPickModel: Boolean;
  GHistory: TArray<THistoryItem>;

function SubmitChat(const Text, Attachment, AttachmentLabel, ImagesJson: string): Boolean;
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
  if not Session.Connected or Session.Busy or (Trim(Text) = '') then
    Exit;
  { omp reads and edits files on disk: they must hold what the IDE shows. }
  SaveProject;
  if ClassifyChat(Text, Arg1, Arg2) = ccPrompt then
  begin
    Display := Text;
    if AttachmentLabel <> '' then
      Display := Display + sLineBreak + '(' + AttachmentLabel + ')';
    Seq := CheckpointBeforePrompt(Text + Attachment);
    Result := Session.SendPrompt(Text + Attachment, Display, ImagesJson);
    if Result and (Seq > 0) then
      Session.Emit(PageCheckpoint(Seq));
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
  ChatSession.Notice('info', '컴파일 중…');
  Json := BuildActiveProjectJson;
  if Json.Contains('"ok":true') then
    ChatSession.Notice('info', '컴파일 성공')
  else if Json.Contains('프로젝트 없음') or Json.Contains('활성 프로젝트가 없습니다') then
    ChatSession.Notice('warn', '컴파일할 프로젝트가 없습니다.')
  else
    ChatSession.Notice('error', '컴파일 실패. 오류는 메시지 창에 있습니다.');
end;

procedure StartNewSession;
begin
  if ChatSession.Connected and not ChatSession.Busy and AskYes('새 세션', '지금 대화를 끝내고 새 세션을 시작할까요?') then
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
    ChatSession.Notice('info', '계획 모드를 끝냈습니다. omp를 다시 시작합니다.');
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
    ChatSession.Notice('warn', '권한 무시: omp 도구와 IDE 변경(버퍼·폼·디버거)을 묻지 않고 반영합니다. ' +
      '저장은 하지 않으며 IDE에서 되돌릴 수 있습니다. omp를 다시 시작합니다.')
  else if Mode = 'write' then
    ChatSession.Notice('info', '쓰기 허용: IDE 변경은 턴마다 한 번 승인합니다. omp를 다시 시작합니다.')
  else
    ChatSession.Notice('info', '항상 묻기: IDE 변경마다 승인합니다. omp를 다시 시작합니다.');
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
    ChatSession.Notice('info', '새 세션을 시작했습니다.');
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
      ChatSession.Emit(PageHistory(GHistory));
      ChatSession.Emit(PageCheckpointList);
      FollowUp := TakeRestoreNotice;
      if FollowUp <> '' then
        ChatSession.Notice('info', FollowUp);
      ChatSession.Notice('info', Format('세션을 불러왔습니다. 메시지 %d개.', [Length(GHistory)]));
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
    ChatSession.Notice('info', '대화를 HTML로 내보냈습니다.')
  else if Command = 'login' then
  begin
    ChatSession.Notice('info', '로그인했습니다.');
    ChatSession.RequestCatalog;
  end;
end;

procedure HandleHostToolCall(const CallId, ToolName, ArgumentsJson: string);
var
  Session: TChatSession;
  Text: string;
  IsError: Boolean;
begin
  Session := ChatSession;
  if (Session.Client = nil) or Session.Client.WasCancelled(CallId) then
    Exit;
  if PlanActive and IsChangingTool(ToolName) then
  begin
    Text := '계획 모드에서는 IDE를 바꿀 수 없습니다. 조사만 하고 rad.submit_plan으로 계획을 제출하세요.';
    IsError := True;
  end
  else
    ExecuteHostTool(ToolName, ArgumentsJson, Session.Approval, Text, IsError);
  { A first form makes the form tools available. }
  if (ToolName = ToolNewModule) and not IsError then
    Session.RefreshHostTools;
  { omp works on disk: what the IDE just changed must be there before omp reads it. }
  if IsChangingTool(ToolName) and not IsError then
    SaveProject;
  if (Session.Client <> nil) and not Session.Client.WasCancelled(CallId) then
    Session.Client.SendHostResult(CallId, Text, IsError);
end;

procedure HandleUiRequest(const Line: string);
var
  Reply, Text: string;
  Cancelled: Boolean;
begin
  if not ExtensionReply(Line, Reply, Text, Cancelled) then
    Exit;
  { omp re-asks for the code after a cancel and has no command to stop a login; only a restart
    ends it. The session resumes on the same file. }
  if Cancelled and (ChatSession.Catalog.PendingLogin <> '') then
  begin
    ChatSession.Notice('info', ChatSession.Catalog.PendingLogin + ' 로그인을 취소했습니다.');
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
