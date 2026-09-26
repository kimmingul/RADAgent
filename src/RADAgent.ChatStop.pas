unit RADAgent.ChatStop;

{ Stopping and losing the omp child. The stop button first sends omp an abort frame. When the
  same turn has not ended StopGraceMs later, or the user presses stop again, the child is killed
  and restarted on the same session file: a child stuck in a request (an unreachable provider)
  answers no frame at all, abort included. Whenever the child goes away, work waiting on it
  (approval cards, a "!" shell command) is dropped with it. Main thread only. }

interface

procedure StopTurn;
{ Stops the omp child after refusing the approvals and ending the shell command waiting on it. }
procedure StopChild;
{ omp ended by itself: closes the turn and, when it had been connected, restarts it on the same
  session - at most once a minute, so a child that keeps dying is not restarted in a loop. }
procedure RecoverExitedChild;

implementation

uses
  System.SysUtils, Winapi.Windows, Vcl.ExtCtrls, RADAgent.ChatSession, RADAgent.ChatApprovalCard,
  RADAgent.ChatTurnTime, RADAgent.ChatQueue, RADAgent.Lang;

const
  StopGraceMs = 5000;
  RecoverGapMs = 60000;

type
  TStopWatch = class
    Timer: TTimer;
    AbortAt: UInt64;
    { The turn the abort was sent for (TChatActivity.StartTick). }
    Turn: UInt64;
    procedure Tick(Sender: TObject);
    procedure Disarm;
  end;

var
  GWatch: TStopWatch;
  GRecoverAt: UInt64;

procedure TStopWatch.Disarm;
begin
  Timer.Enabled := False;
  AbortAt := 0;
end;

function Armed: Boolean;
begin
  Result := (GWatch.AbortAt <> 0) and ChatSession.Busy and (ChatSession.Activity.StartTick = GWatch.Turn);
end;

procedure ForceStop;
begin
  GWatch.Disarm;
  ChatSession.Notice('warn', Tr('chatstop.forced'));
  ReportTurnEnd(True);
  ChatSession.Restart(True);
end;

procedure TStopWatch.Tick(Sender: TObject);
begin
  { The aborted turn ended (a new one may already run): that one is not ours to kill. }
  if not Armed then
    Disarm
  else if GetTickCount64 - AbortAt >= StopGraceMs then
    ForceStop;
end;

procedure StopTurn;
begin
  RefuseAllApprovals;
  ChatSession.Activity.NoteStopRequested;
  if ShellRunning then
  begin
    AbortShell;
    Exit;
  end;
  if (ChatSession.Client = nil) or not ChatSession.Busy then
  begin
    if ChatSession.Client <> nil then
      ChatSession.Client.SendAbort;
    Exit;
  end;
  if Armed then
  begin
    ForceStop;
    Exit;
  end;
  ChatSession.Client.SendAbort;
  ChatSession.Notice('info', Tr('chatstop.stopping'));
  GWatch.AbortAt := GetTickCount64;
  GWatch.Turn := ChatSession.Activity.StartTick;
  GWatch.Timer.Enabled := True;
end;

procedure StopChild;
begin
  RefuseAllApprovals;
  ResetShell;
  GWatch.Disarm;
  if ChatSession.Client <> nil then
    ChatSession.Client.Stop;
end;

procedure RecoverExitedChild;
var
  Session: TChatSession;
begin
  Session := ChatSession;
  if Session.Busy then
  begin
    ReportTurnEnd(True);
    Session.Activity.Reset;
  end;
  RefuseAllApprovals;
  ResetShell;
  GWatch.Disarm;
  if not Session.Client.ExitedConnected or (GetTickCount64 - GRecoverAt < RecoverGapMs) then
    Exit;
  GRecoverAt := GetTickCount64;
  Session.Notice('warn', TrF('chatstop.childExited', [Session.Client.LinkError]));
  Session.Restart(True);
end;

initialization
  GWatch := TStopWatch.Create;
  GWatch.Timer := TTimer.Create(nil);
  GWatch.Timer.Enabled := False;
  GWatch.Timer.Interval := 250;
  GWatch.Timer.OnTimer := GWatch.Tick;

finalization
  GWatch.Timer.Free;
  GWatch.Free;

end.
