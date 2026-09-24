unit DelphiAgent.ChatCheckpoints;

{ Every project lives in a git repository, and every user message gets a checkpoint of the project
  as it was just before (DelphiAgent.GitRepo). From a message in the chat the user can go back to
  that state (files and conversation) or start a git branch there; the state before going back is
  kept as a checkpoint too. Main thread only. }

interface

{ The project folder's repository, or a new one (git init). Once per folder per IDE session. }
procedure EnsureProjectRepo(const ProjectDir: string);
{ Checkpoint for the prompt about to be sent; 0 when there is none. Call after saving. }
function CheckpointBeforePrompt(const Prompt: string): Integer;
{ Page messages: one checkpoint for the user message just shown, or all of them for a history. }
function PageCheckpoint(Seq: Integer): string;
function PageCheckpointList: string;
{ Back to the state before message Seq; AsBranch also starts a git branch there. }
procedure GoBackTo(Seq: Integer; AsBranch: Boolean);
{ The get_entries reply a GoBackTo waits for: branches the conversation at that message. }
function HandleEntries(const Line: string): Boolean;
{ What GoBackTo did, for the chat once the branched conversation is shown; '' when nothing. }
function TakeRestoreNotice: string;

implementation

uses
  System.SysUtils, System.StrUtils, System.JSON, DelphiAgent.GitRepo, DelphiAgent.ChatSession, DelphiAgent.IdeContext,
  DelphiAgent.IdeFiles, DelphiAgent.AskDialog, DelphiAgent.ChatCommand, DelphiAgent.RpcJson;

var
  GCheckedDir: string;
  GNotedNoGit: Boolean;
  GPendingPrompt, GRestoreNotice: string;

function ProjectDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(ActiveProjectDir);
end;

procedure EnsureProjectRepo(const ProjectDir: string);
var
  Problem: string;
begin
  if (ProjectDir = '') or SameText(GCheckedDir, ProjectDir) then
    Exit;
  GCheckedDir := ProjectDir;
  if GitExecutable = '' then
  begin
    if not GNotedNoGit then
      ChatSession.Notice('warn', 'git이 없어 메시지별 체크포인트(되돌리기·브랜치)를 만들지 않습니다. ' +
        'Git for Windows를 설치하면 켜집니다.');
    GNotedNoGit := True;
    Exit;
  end;
  if GitRoot(ProjectDir) <> '' then
    Exit;
  if InitRepo(ProjectDir, Problem) then
    ChatSession.Notice('info', 'DelphiAgent가 프로젝트 폴더를 git 저장소로 만들었습니다(.gitignore와 첫 커밋 포함). ' +
      '메시지마다 체크포인트를 남겨 되돌리거나 브랜치를 만들 수 있습니다.')
  else
    ChatSession.Notice('warn', 'git init에 실패해 체크포인트를 만들지 않습니다: ' + Problem);
end;

function CheckpointBeforePrompt(const Prompt: string): Integer;
var
  Root, Commit, Problem: string;
begin
  Result := 0;
  Root := GitRoot(ProjectDir);
  if Root = '' then
    Exit;
  if not CreateCheckpoint(Root, CheckpointRefs, Prompt, Result, Commit, Problem) then
  begin
    Result := 0;
    ChatSession.Notice('warn', '체크포인트를 만들지 못했습니다: ' + Problem);
  end;
end;

function Finish(Obj: TJSONObject): string;
begin
  try
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageCheckpoint(Seq: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'checkpoint');
  Obj.AddPair('seq', TJSONNumber.Create(Seq));
  Result := Finish(Obj);
end;

function PageCheckpointList: string;
var
  Obj, Item: TJSONObject;
  Items: TJSONArray;
  Point: TCheckpoint;
  Root: string;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'checkpoints');
  Items := TJSONArray.Create;
  Obj.AddPair('items', Items);
  Root := GitRoot(ProjectDir);
  if Root <> '' then
    for Point in ListCheckpoints(Root) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('seq', TJSONNumber.Create(Point.Seq));
      Item.AddPair('prompt', Point.Prompt);
      Items.AddElement(Item);
    end;
  Result := Finish(Obj);
end;

function FindCheckpoint(const Root: string; Seq: Integer; out Point: TCheckpoint): Boolean;
var
  Item: TCheckpoint;
begin
  for Item in ListCheckpoints(Root) do
    if Item.Seq = Seq then
    begin
      Point := Item;
      Exit(True);
    end;
  Result := False;
end;

procedure GoBackTo(Seq: Integer; AsBranch: Boolean);
var
  Root, Current, Problem, Branch: string;
  Point: TCheckpoint;
  Safety: Integer;
  Conflicts: TArray<string>;
begin
  Root := GitRoot(ProjectDir);
  if (Root = '') or not FindCheckpoint(Root, Seq, Point) then
  begin
    ChatSession.Notice('warn', '이 메시지의 체크포인트를 찾지 못했습니다.');
    Exit;
  end;
  if ChatSession.Busy then
  begin
    ChatSession.Notice('warn', 'omp가 일하는 중에는 되돌릴 수 없습니다. 중지한 뒤 다시 누르세요.');
    Exit;
  end;
  if not AskYes('DelphiAgent', '이 메시지를 보내기 전 상태로 파일과 대화를 되돌립니다' +
    IfThen(AsBranch, '. 그 시점에서 새 git 브랜치를 만들어 옮겨 갑니다', '') +
    '. 지금 상태는 체크포인트로 남습니다. 계속할까요?') then
    Exit;
  if not SaveProjectModules(ProjectDir, Problem) or
    not CreateCheckpoint(Root, SafetyRefs, '되돌리기 전 (메시지 체크포인트 ' + IntToStr(Seq) + ')', Safety,
    Current, Problem) or not RestoreCheckpoint(Root, Point.Commit, Current, Problem) then
  begin
    ChatSession.Notice('error', '되돌리지 못했습니다: ' + Problem);
    Exit;
  end;
  ReloadChangedModules(ProjectDir, Conflicts);
  Branch := '';
  if AsBranch then
  begin
    Branch := 'delphiagent/' + FormatDateTime('yyyymmdd-hhnnss', Now);
    if not BranchAtCheckpoint(Root, Point.Commit, Branch, Problem) then
    begin
      ChatSession.Notice('error', '브랜치를 만들지 못했습니다: ' + Problem);
      Branch := '';
    end;
  end;
  { Shown after the conversation reloads (reloading clears the chat). }
  GRestoreNotice := '파일을 메시지 체크포인트 ' + IntToStr(Seq) + '(' + Point.When + ') 상태로 ' +
    '되돌렸습니다' + IfThen(Branch <> '', '. 지금 브랜치: ' + Branch, '') + '. 되돌리기 전 상태는 ' +
    SafetyRefs + Format('%.6d', [Safety]) + '에 있습니다.';
  { The conversation goes back with the files: branch the omp session before that message. }
  GPendingPrompt := Point.Prompt;
  ChatSession.SendCommand('get_entries', BuildIdTypeFrame('req', 'get_entries'));
end;

function TakeRestoreNotice: string;
begin
  Result := GRestoreNotice;
  GRestoreNotice := '';
end;

function HandleEntries(const Line: string): Boolean;
var
  Obj, Data, Entry, Msg: TJSONObject;
  Item: TJSONValue;
  Id, Text, Wanted: string;
begin
  Result := GPendingPrompt <> '';
  if not Result then
    Exit;
  Wanted := Trim(GPendingPrompt);
  GPendingPrompt := '';
  Id := '';
  Obj := JsonObject(Line);
  try
    Data := JsonChild(Obj, 'data');
    if (Data <> nil) and (Data.GetValue('entries') is TJSONArray) then
      for Item in TJSONArray(Data.GetValue('entries')) do
      begin
        if not (Item is TJSONObject) then
          Continue;
        Entry := TJSONObject(Item);
        Msg := JsonChild(Entry, 'message');
        if (JsonStr(Entry, 'type') <> 'message') or (JsonStr(Msg, 'role') <> 'user') then
          Continue;
        Text := Trim(ContentText(Msg.GetValue('content')));
        { The newest message with this text; omp may add expanded @file parts after it. }
        if (Text = Wanted) or Text.StartsWith(Wanted) then
          Id := JsonStr(Entry, 'id');
      end;
  finally
    Obj.Free;
  end;
  if Id = '' then
  begin
    ChatSession.Notice('info', TakeRestoreNotice);
    ChatSession.Notice('warn', 'omp 대화에서 이 메시지를 찾지 못해 대화는 그대로 둡니다.');
    Exit;
  end;
  ChatSession.SendCommand('branch', BuildTypeFieldFrame('branch', 'entryId', Id));
end;

end.
