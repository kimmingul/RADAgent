unit RADAgent.ChatQueue;

{ Work beside a running turn: messages sent while omp works (steer: read at its next step;
  follow-up: after the turn), "!" shell commands in omp's shell, and calling off a waiting retry.
  Main thread only. }

interface

{ Sends Text into the running turn: now (steer) or after the turn (FollowUp). False when it did
  not reach omp (a notice says so). }
function QueueMessage(const Text, DisplayText, ImagesJson: string; FollowUp: Boolean): Boolean;
{ "!command": omp runs it in its shell and keeps the output in the context. }
function RunShell(const Command: string): Boolean;
function ShellRunning: Boolean;
{ The omp child that ran the shell command is gone: its reply will never come. }
procedure ResetShell;
{ Stop button while a shell command runs. }
procedure AbortShell;
procedure AbortRetry;
{ The bash reply RunShell waits for; True when handled. }
function HandleShellResponse(const Line: string): Boolean;

implementation

uses
  System.SysUtils, System.JSON, RADAgent.ChatSession, RADAgent.SessionData, RADAgent.ChatCommand,
  RADAgent.ChatPageMessages, RADAgent.Lang;

var
  GShell: Boolean;

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
    ChatSession.Emit(PageQueuedUser(DisplayText, Tags[FollowUp]))
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
  ChatSession.ShowUserText('!' + Command);
  ChatSession.SendCommand('bash', BuildTypeFieldFrame('bash', 'command', Command));
  ChatSession.Changed;
end;

function ShellRunning: Boolean;
begin
  Result := GShell;
end;

procedure ResetShell;
begin
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

end.
