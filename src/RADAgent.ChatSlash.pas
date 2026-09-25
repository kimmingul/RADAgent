unit RADAgent.ChatSlash;

{ The slash commands omp's terminal keeps to itself (RADAgent.SlashRoutes), carried out with RPC
  requests and RADAgent's own windows, and the subagent transcripts. Main thread only. }

interface

{ True when RADAgent handled Text (or explained why it cannot); False: omp gets it. }
function RunLocalSlash(const Text: string): Boolean;
procedure ShowSubagentLog(const Id: string);
{ Replies to the commands sent here; True when nothing else should handle Line. }
function HandleSlashResponse(const Line: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, Vcl.Clipbrd,
  RADAgent.ChatSession, RADAgent.SlashRoutes, RADAgent.SessionData, RADAgent.RpcResponses,
  RADAgent.ChatCommand, RADAgent.ChatPageMessages, RADAgent.AskDialog, RADAgent.ChatActions,
  RADAgent.SettingsDialog, RADAgent.RpcJson, RADAgent.ChatQueue, RADAgent.Lang;

type
  TPending = (pdNone, pdBranch, pdTree, pdCopy, pdCopyCode, pdHub, pdSubagent, pdClear, pdDelete);

var
  GPending: TPending;
  { /delete: the session file to remove once omp has left it; /clear: the name to keep. }
  GOldFile, GOldName, GSubagent: string;

function Frame(const FrameType, Field, Value: string): string;
begin
  Result := BuildTypeFieldFrame(FrameType, Field, Value);
end;

procedure Ask(Pending: TPending; const Command: string);
begin
  GPending := Pending;
  ChatSession.SendCommand(Command, BuildIdTypeFrame('req', Command));
end;

function Idle: Boolean;
begin
  Result := not ChatSession.Busy and not ShellRunning;
  if not Result then
    ChatSession.Notice('warn', Tr('chatslash.busy'));
end;

procedure Login(const Args: string);
var
  Items: TStringList;
  Providers: TArray<TLoginProvider>;
  Provider: TLoginProvider;
  Index: Integer;
  Id: string;
begin
  Providers := ChatSession.Catalog.LoginProviders;
  Id := '';
  for Provider in Providers do
    if SameText(Provider.Id, Args) then
      Id := Provider.Id;
  if Id = '' then
  begin
    Items := TStringList.Create;
    try
      for Provider in Providers do
        if Provider.Authenticated then
          Items.Add(TrF('settingsaccount.providerLoggedIn', [Provider.Name]))
        else
          Items.Add(Provider.Name);
      Index := AskIndex(Tr('chatslash.loginTitle'), Items);
    finally
      Items.Free;
    end;
    if Index < 0 then
      Exit;
    Id := Providers[Index].Id;
  end;
  ChatSession.SendCommand('login', Frame('login', 'providerId', Id));
end;

function RunLocalSlash(const Text: string): Boolean;
var
  Names: TArray<string>;
  Command: TSlashCommand;
  Name, Args: string;
  Session: TChatSession;
begin
  Session := ChatSession;
  Names := nil;
  for Command in Session.Commands do
    Names := Names + [Command.Name];
  Result := RouteSlash(Text, Names, Name, Args) <> srNone;
  if not Result then
    Exit;
  if RouteSlash(Text, Names, Name, Args) <> srQueue then
    Session.ShowUserText(Text);
  case RouteSlash(Text, Names, Name, Args) of
    srNone:
      Exit(False);
    srClear:
      if Idle then
      begin
        GOldFile := Session.State.SessionFile;
        GOldName := Session.State.SessionName;
        GPending := pdClear;
        Session.SendCommand('new_session', Frame('new_session', 'parentSession', GOldFile));
      end;
    srDelete:
      if Idle and (Session.State.SessionFile <> '') and
        AskYes('RAD Agent', TrF('chatslash.deleteConfirm', [ExtractFileName(Session.State.SessionFile)])) then
      begin
        GOldFile := Session.State.SessionFile;
        GPending := pdDelete;
        Session.SendCommand('new_session', BuildIdTypeFrame('req', 'new_session'));
      end;
    srResume:
      if Idle then
        PickSession;
    srTree:
      if Idle then
        Ask(pdTree, 'get_tree');
    srBranch, srFork:
      if Idle then
        Ask(pdBranch, 'get_branch_messages');
    srLogin:
      Login(Args);
    srCopy:
      if SameText(Args, 'code') then
        Ask(pdCopyCode, 'get_last_assistant_text')
      else
        Ask(pdCopy, 'get_last_assistant_text');
    srRestart:
      begin
        Session.Notice('info', Tr('chatslash.restarting'));
        Session.RestartWhenIdle;
      end;
    srSettings:
      ShowSettings(0);
    srExtensions:
      ShowSettings(3);
    srAgents:
      ShowSettings(2);
    srPlan:
      SetApprovalMode('plan');
    srHotkeys:
      Session.PostToView(PageSheet(Tr('chatslash.hotkeysTitle'), Tr('chatslash.hotkeys')));
    srHub:
      Ask(pdHub, 'get_subagents');
    srQueue:
      if Args = '' then
        Session.Notice('warn', Tr('chatslash.queueUsage'))
      else if Session.Busy then
        QueueMessage(Args, Args, '', True)
      else
        SubmitChat(Args, '', '');
    srExit:
      Session.Notice('info', Tr('chatslash.exit'));
    srTerminalOnly:
      Session.Notice('warn', TrF('chatslash.terminalOnly', [Name]));
  end;
end;

procedure ShowSubagentLog(const Id: string);
var
  Transcript: string;
begin
  if Id = '' then
    Exit;
  GSubagent := Id;
  GPending := pdSubagent;
  { Finished subagents leave the registry; their transcript stays beside the session file. }
  Transcript := ChatSession.State.SessionFile;
  if Transcript <> '' then
    Transcript := TPath.Combine(ChangeFileExt(Transcript, ''), Id + '.jsonl');
  if (Transcript <> '') and FileExists(Transcript) then
    ChatSession.SendCommand('get_subagent_messages', Frame('get_subagent_messages', 'sessionFile', Transcript))
  else
    ChatSession.SendCommand('get_subagent_messages', Frame('get_subagent_messages', 'subagentId', Id));
end;

procedure PickBranch(const Line: string);
var
  Messages: TArray<TBranchMessage>;
  Items: TStringList;
  Message: TBranchMessage;
  Index: Integer;
begin
  if not ParseBranchMessages(Line, Messages) or (Length(Messages) = 0) then
  begin
    ChatSession.Notice('info', Tr('chatslash.noMessages'));
    Exit;
  end;
  Items := TStringList.Create;
  try
    for Message in Messages do
      Items.Add(Copy(CollapseWhitespace(Message.Text), 1, 120));
    Index := AskIndex(Tr('chatslash.branchTitle'), Items, Items.Count - 1);
  finally
    Items.Free;
  end;
  if Index >= 0 then
    ChatSession.SendCommand('branch', Frame('branch', 'entryId', Messages[Index].EntryId));
end;

procedure PickTree(const Line: string);
const
  Marks: array[Boolean] of string = ('○ ', '● ');
var
  Lines: TArray<TTreeLine>;
  Items: TStringList;
  Item: TTreeLine;
  Index, Start: Integer;
begin
  if not ParseTree(Line, Lines) or (Length(Lines) = 0) then
  begin
    ChatSession.Notice('info', Tr('chatslash.noMessages'));
    Exit;
  end;
  Items := TStringList.Create;
  try
    Start := 0;
    for Index := 0 to High(Lines) do
    begin
      Item := Lines[Index];
      if Item.IsUser then
        Items.Add(StringOfChar(' ', Item.Depth * 4) + Marks[Item.OnPath] + '› ' + Item.Text)
      else
        Items.Add(StringOfChar(' ', Item.Depth * 4 + 4) + Item.Text);
      if Item.OnPath then
        Start := Index;
    end;
    Index := AskIndex(Tr('chatslash.treeTitle'), Items, Start);
  finally
    Items.Free;
  end;
  if Index < 0 then
    Exit;
  if not Lines[Index].IsUser then
    ChatSession.Notice('warn', Tr('chatslash.treePickUser'))
  else
    ChatSession.SendCommand('branch', Frame('branch', 'entryId', Lines[Index].EntryId));
end;

procedure CopyAnswer(const Line: string; CodeOnly: Boolean);
var
  Text: string;
begin
  Text := ResponseText(Line);
  if CodeOnly then
    Text := LastCodeBlock(Text);
  if Text = '' then
    ChatSession.Notice('warn', Tr('chatslash.nothingToCopy'))
  else
  begin
    Clipboard.AsText := Text;
    ChatSession.Notice('info', Tr('chatslash.copied'));
  end;
end;

procedure SessionReplaced(Pending: TPending);
begin
  ChatSession.ClearTranscript;
  ChatSession.SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
  if (Pending = pdClear) and (GOldName <> '') then
    ChatSession.SendCommand('set_session_name', Frame('set_session_name', 'name', GOldName));
  if Pending = pdClear then
    ChatSession.Notice('info', Tr('chatslash.cleared'));
  if (Pending = pdDelete) and (GOldFile <> '') then
  begin
    System.SysUtils.DeleteFile(GOldFile);
    if TDirectory.Exists(ChangeFileExt(GOldFile, '')) then
      TDirectory.Delete(ChangeFileExt(GOldFile, ''), True);
    ChatSession.Notice('info', TrF('chatslash.deleted', [ExtractFileName(GOldFile)]));
  end;
  GOldFile := '';
  GOldName := '';
end;

function ResponseError(const Line: string): string;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Line);
  try
    Result := JsonStr(Obj, 'error');
  finally
    Obj.Free;
  end;
end;

function HandleSlashResponse(const Line: string): Boolean;
var
  Command, Text: string;
  Ok: Boolean;
  Pending: TPending;
begin
  Command := ResponseOf(Line, Ok);
  Result := False;
  Pending := GPending;
  if (Command = 'new_session') and (Pending in [pdClear, pdDelete]) then
  begin
    GPending := pdNone;
    if not Ok then
      Exit(False);
    SessionReplaced(Pending);
    Exit(True);
  end;
  if Pending = pdNone then
    Exit;
  if not Ok then
  begin
    if (Command = 'get_branch_messages') or (Command = 'get_tree') or (Command = 'get_subagents') or
      (Command = 'get_last_assistant_text') or (Command = 'get_subagent_messages') then
    begin
      GPending := pdNone;
      ChatSession.Notice('error', ResponseError(Line));
      Result := True;
    end;
    Exit;
  end;
  Result := True;
  if (Command = 'get_branch_messages') and (Pending = pdBranch) then
    PickBranch(Line)
  else if (Command = 'get_tree') and (Pending = pdTree) then
    PickTree(Line)
  else if (Command = 'get_last_assistant_text') and (Pending in [pdCopy, pdCopyCode]) then
    CopyAnswer(Line, Pending = pdCopyCode)
  else if (Command = 'get_subagents') and (Pending = pdHub) then
  begin
    Text := SubagentListMarkdown(Line);
    if Text = '' then
      Text := Tr('chatslash.noSubagents');
    ChatSession.PostToView(PageSheet(Tr('chatslash.hubTitle'), Text));
  end
  else if (Command = 'get_subagent_messages') and (Pending = pdSubagent) then
  begin
    Text := TranscriptMarkdown(Line);
    if Text = '' then
      Text := Tr('chatslash.noMessages');
    ChatSession.PostToView(PageSheet(GSubagent, Text));
  end
  else
    Exit(False);
  GPending := pdNone;
end;

end.
