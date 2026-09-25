unit RADAgent.ChatStop;

{ The stop button. First press sends omp an abort frame. When omp has not ended the turn
  StopGraceMs later, or the user presses stop again, the omp child is killed and restarted on
  the same session file: a child stuck in a request (an unreachable provider) answers no frame
  at all, abort included. Main thread only. }

interface

procedure StopTurn;

implementation

uses
  System.SysUtils, Winapi.Windows, Vcl.ExtCtrls, RADAgent.ChatSession, RADAgent.ChatApprovalCard,
  RADAgent.ChatPageMessages, RADAgent.ChatQueue, RADAgent.Lang;

const
  StopGraceMs = 5000;

type
  TStopWatch = class
    Timer: TTimer;
    AbortAt: UInt64;
    procedure Tick(Sender: TObject);
  end;

var
  GWatch: TStopWatch;

procedure ForceStop;
begin
  GWatch.Timer.Enabled := False;
  GWatch.AbortAt := 0;
  ChatSession.Notice('warn', Tr('chatstop.forced'));
  ChatSession.Emit(PageTurnEnd);
  ChatSession.Restart(True);
end;

procedure TStopWatch.Tick(Sender: TObject);
begin
  if not ChatSession.Busy then
  begin
    Timer.Enabled := False;
    AbortAt := 0;
  end
  else if GetTickCount64 - AbortAt >= StopGraceMs then
    ForceStop;
end;

procedure StopTurn;
begin
  RefuseAllApprovals;
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
  if GWatch.AbortAt <> 0 then
  begin
    ForceStop;
    Exit;
  end;
  ChatSession.Client.SendAbort;
  ChatSession.Notice('info', Tr('chatstop.stopping'));
  GWatch.AbortAt := GetTickCount64;
  GWatch.Timer.Enabled := True;
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
