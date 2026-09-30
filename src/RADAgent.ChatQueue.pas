unit RADAgent.ChatQueue;

{ Work beside a running turn: messages sent while omp works (steer: read at its next step;
  follow-up: after the turn), which the page shows as pending while omp's queue reports list them
  and which can be called off there, "!" shell commands in omp's shell, and calling off a waiting
  retry. Main thread only. }

interface

{ Sends Text into the running turn: now (steer) or after the turn (FollowUp). False when it did
  not reach omp (a notice says so). }
function QueueMessage(const Text, DisplayText, ImagesJson: string; FollowUp: Boolean): Boolean;
{ "!command": omp runs it in its shell and keeps the output in the context. }
function RunShell(const Command: string): Boolean;
function ShellRunning: Boolean;
{ The omp child is gone: the replies to a shell command or to calling off a message never come. }
procedure ResetShell;
{ Stop button while a shell command runs. }
procedure AbortShell;
procedure AbortRetry;
{ The bash reply RunShell waits for; True when handled. }
function HandleShellResponse(const Line: string): Boolean;
{ omp's queue_update event, or its answer to CancelQueued; True when handled. }
function HandleQueueFrame(const Line: string): Boolean;
{ The page's cancel button on a pending message. Sent: the text omp got; Queue: the page's 'steer'
  or 'followUp'. }
procedure CancelQueued(const Sent, Queue: string);

implementation

uses
  System.SysUtils, System.JSON, RADAgent.ChatSession, RADAgent.SessionData, RADAgent.ChatCommand,
  RADAgent.ChatPageMessages, RADAgent.RpcQueue, RADAgent.Lang;

type
  TCancelRequest = record
    Sent, Queue: string;
  end;

var
  GShell: Boolean;
  { remove_queued_message answers carry no message: they come back in the order sent. }
  GCancels: TArray<TCancelRequest>;

function QueueMessage(const Text, DisplayText, ImagesJson: string; FollowUp: Boolean): Boolean;
const
  Kinds: array[Boolean] of string = ('steer', 'follow_up');
  Tags: array[Boolean] of string = ('steer', 'followUp');
var
  Obj: TJSONObject;
  Images: TJSONValue;
begin
  Result := ChatSession.Connected;
  if not Result then
    Exit;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', Kinds[FollowUp]);
    Obj.AddPair('message', Text);
    if ImagesJson <> '' then
    begin
      Images := TJSONObject.ParseJSONValue(ImagesJson);
      if Images is TJSONArray then
        Obj.AddPair('images', Images)
      else
        Images.Free;
    end;
    Result := ChatSession.Client.SendRaw(Kinds[FollowUp], Obj.ToJSON);
  finally
    Obj.Free;
  end;
  if Result then
    ChatSession.Emit(PageQueuedUser(DisplayText, Tags[FollowUp], Text))
  else
    ChatSession.Notice('error', Tr('chatactions.sendFailed'));
end;

function RunShell(const Command: string): Boolean;
begin
  if ChatSession.Busy or GShell then
  begin
    ChatSession.Notice('warn', Tr('chatslash.busy'));
    Exit(False);
  end;
  Result := ChatSession.Connected and (Trim(Command) <> '');
  if not Result then
    Exit;
  GShell := True;
  ChatSession.Emit(PageUser('!' + Command));
  ChatSession.SendCommand('bash', BuildTypeFieldFrame('bash', 'command', Command));
  ChatSession.Changed;
end;

function ShellRunning: Boolean;
begin
  Result := GShell;
end;

procedure ResetShell;
begin
  GCancels := nil;
  if not GShell then
    Exit;
  GShell := False;
  ChatSession.Changed;
end;

procedure AbortShell;
begin
  if GShell then
    ChatSession.SendCommand('abort_bash', BuildIdTypeFrame('req', 'abort_bash'));
end;

procedure AbortRetry;
begin
  ChatSession.SendCommand('abort_retry', BuildIdTypeFrame('req', 'abort_retry'));
end;

procedure ShowBash(const Line: string);
var
  Bash: TBashResult;
  Text: string;
begin
  GShell := False;
  ChatSession.Changed;
  if not ParseBash(Line, Bash) then
    Exit;
  Text := TrimRight(Bash.Output);
  if Bash.Cancelled then
    Text := Text + sLineBreak + Tr('chatslash.shellCancelled')
  else if Bash.ExitCode <> 0 then
    Text := Text + sLineBreak + TrF('chatslash.shellExit', [Bash.ExitCode]);
  if Bash.Truncated then
    Text := Text + sLineBreak + Tr('chatslash.shellTruncated');
  ChatSession.Emit(PageNotice('output', Trim(Text)));
end;

function HandleShellResponse(const Line: string): Boolean;
var
  Ok: Boolean;
begin
  Result := ResponseOf(Line, Ok) = 'bash';
  if Result then
    ShowBash(Line);
end;

function HandleQueueFrame(const Line: string): Boolean;
var
  Snapshot: TQueueSnapshot;
  Removed: Boolean;
  Request: TCancelRequest;
begin
  Result := True;
  if ParseQueueUpdate(Line, Snapshot) then
  begin
    ChatSession.Emit(PageQueue(Snapshot, False));
    Exit;
  end;
  if not ParseRemoveQueued(Line, Removed) then
    Exit(False);
  if Length(GCancels) = 0 then
    Exit;
  Request := GCancels[0];
  Delete(GCancels, 0, 1);
  ChatSession.Emit(PageQueueRemoved(Request.Sent, Request.Queue, Removed));
  if not Removed then
    ChatSession.Notice('info', Tr('chatqueue.notRemoved'));
end;

procedure CancelQueued(const Sent, Queue: string);
const
  OmpQueues: array[Boolean] of string = ('steering', 'followUp');
var
  Request: TCancelRequest;
begin
  Request.Sent := Sent;
  Request.Queue := Queue;
  if not ChatSession.Connected then
  begin
    ChatSession.Emit(PageQueueRemoved(Sent, Queue, False));
    Exit;
  end;
  GCancels := GCancels + [Request];
  ChatSession.SendCommand('remove_queued_message',
    BuildRemoveQueuedFrame('req', Sent, OmpQueues[Queue = 'followUp']));
end;

end.
