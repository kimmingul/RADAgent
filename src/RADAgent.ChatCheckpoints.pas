unit RADAgent.ChatCheckpoints;

{ Every project lives in a git repository, and every user message gets a checkpoint of the project
  as it was just before (RADAgent.GitRepo). From a message in the chat the user can go back to
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
  System.SysUtils, System.StrUtils, System.JSON, RADAgent.GitRepo, RADAgent.ChatSession, RADAgent.IdeContext,
  RADAgent.IdeFiles, RADAgent.AskDialog, RADAgent.ChatCommand, RADAgent.RpcJson,
  RADAgent.Lang;

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
      ChatSession.Notice('warn', Tr('chatcheckpoints.noGit'));
    GNotedNoGit := True;
    Exit;
  end;
  if GitRoot(ProjectDir) <> '' then
    Exit;
  if InitRepo(ProjectDir, Problem) then
    ChatSession.Notice('info', Tr('chatcheckpoints.initRepo'))
  else
    ChatSession.Notice('warn', TrF('chatcheckpoints.initFailed', [Problem]));
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
    ChatSession.Notice('warn', TrF('chatcheckpoints.createFailed', [Problem]));
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
    ChatSession.Notice('warn', Tr('chatcheckpoints.notFound'));
    Exit;
  end;
  if ChatSession.Busy then
  begin
    ChatSession.Notice('warn', Tr('chatcheckpoints.busy'));
    Exit;
  end;
  if not AskYes('RAD Agent', IfThen(AsBranch, Tr('chatcheckpoints.confirmBranch'), Tr('chatcheckpoints.confirmRevert'))) then
    Exit;
  if not SaveProjectModules(ProjectDir, Problem) or
    not CreateCheckpoint(Root, SafetyRefs, TrF('chatcheckpoints.safetyBeforeRevert', [Seq]), Safety,
    Current, Problem) or not RestoreCheckpoint(Root, Point.Commit, Current, Problem) then
  begin
    ChatSession.Notice('error', TrF('chatcheckpoints.revertFailed', [Problem]));
    Exit;
  end;
  ReloadChangedModules(ProjectDir, Conflicts);
  Branch := '';
  if AsBranch then
  begin
    Branch := 'radagent/' + FormatDateTime('yyyymmdd-hhnnss', Now);
    if not BranchAtCheckpoint(Root, Point.Commit, Branch, Problem) then
    begin
      ChatSession.Notice('error', TrF('chatcheckpoints.branchFailed', [Problem]));
      Branch := '';
    end;
  end;
  { Shown after the conversation reloads (reloading clears the chat). }
  if Branch <> '' then
    GRestoreNotice := TrF('chatcheckpoints.restoredWithBranch', [Seq, Point.When, Branch, SafetyRefs + Format('%.6d', [Safety])])
  else
    GRestoreNotice := TrF('chatcheckpoints.restored', [Seq, Point.When, SafetyRefs + Format('%.6d', [Safety])]);
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
    ChatSession.Notice('warn', Tr('chatcheckpoints.entryNotFound'));
    Exit;
  end;
  ChatSession.SendCommand('branch', BuildTypeFieldFrame('branch', 'entryId', Id));
end;

end.
