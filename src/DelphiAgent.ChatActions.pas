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
  DelphiAgent.IdeContext, DelphiAgent.DirtyBuffers, DelphiAgent.Compile, DelphiAgent.AgentSettings,
  DelphiAgent.ChatPageMessages, DelphiAgent.Sessions, DelphiAgent.Options, DelphiAgent.HostTools,
  DelphiAgent.OmpSettings, DelphiAgent.HostToolDefs, DelphiAgent.ChatPlan, DelphiAgent.ChatBtw;

var
  GPickModel: Boolean;
  GHistory: TArray<THistoryItem>;

function PromptWithSnapshots(const Text: string): string;
var
  Open: TArray<TEditorText>;
  Files, Texts, DirtyFiles, DirtyTexts, Snaps: TArray<string>;
  Index: Integer;
  Dir: string;
begin
  { Remember every open buffer for conflict checks; only dirty ones go to disk for omp. }
  Open := OpenEditorTexts;
  SetLength(Files, Length(Open));
  SetLength(Texts, Length(Open));
  for Index := 0 to High(Open) do
  begin
    Files[Index] := Open[Index].FileName;
    Texts[Index] := Open[Index].Text;
    if Open[Index].Modified and SnapshotDirtyBuffers then
    begin
      DirtyFiles := DirtyFiles + [Open[Index].FileName];
      DirtyTexts := DirtyTexts + [Open[Index].Text];
    end;
  end;
  RememberSnapshots(Files, Texts);
  Snaps := WriteSnapshots(AgentTempRoot, DirtyFiles, DirtyTexts);
  { omp expands @path from disk; an unsaved buffer must be read from its snapshot instead. }
  Result := Text;
  Dir := IncludeTrailingPathDelimiter(ActiveProjectDir);
  for Index := 0 to High(Snaps) do
  begin
    Result := StringReplace(Result, '@' + DirtyFiles[Index], '@' + Snaps[Index], [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '@' + ExtractRelativePath(Dir, DirtyFiles[Index]), '@' + Snaps[Index],
      [rfReplaceAll, rfIgnoreCase]);
  end;
  Result := MessageWithSnapshots(Result, Snaps);
end;

function SubmitChat(const Text, Attachment, AttachmentLabel, ImagesJson: string): Boolean;
var
  Session: TChatSession;
  Arg1, Arg2, Display: string;
  PickModels: Boolean;
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
  if ClassifyChat(Text, Arg1, Arg2) = ccPrompt then
  begin
    Display := Text;
    if AttachmentLabel <> '' then
      Display := Display + sLineBreak + '(' + AttachmentLabel + ')';
    Exit(Session.SendPrompt(PromptWithSnapshots(Text + Attachment), Display, ImagesJson));
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
  else if Command = 'switch_session' then
  begin
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
