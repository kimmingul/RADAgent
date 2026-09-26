unit RADAgent.ChatTurnTime;

{ The end of a turn, reported three ways: the chat's "done at · took" line under the answer, one
  line in the IDE Messages view, and - when the IDE is in the background - a flashing taskbar
  button and a Windows notification (a setting). Main thread only. }

interface

{ Stopped: the turn was cut short (stop pressed, omp restarted or gone). }
procedure ReportTurnEnd(Stopped: Boolean);
{ A duration in the UI language, e.g. "3m 12s". }
function FormatDuration(Ms: Int64): string;

implementation

uses
  System.SysUtils, System.DateUtils, RADAgent.ChatSession, RADAgent.ChatPageMessages,
  RADAgent.ChatAttention, RADAgent.IdeContext, RADAgent.AgentSettings, RADAgent.RpcJson, RADAgent.Lang;

function FormatDuration(Ms: Int64): string;
var
  Seconds: Int64;
begin
  Seconds := (Ms + 500) div 1000;
  if Seconds < 0 then
    Seconds := 0;
  if Seconds < 60 then
    Result := TrF('turntime.seconds', [Integer(Seconds)])
  else if Seconds < 3600 then
    Result := TrF('turntime.minutes', [Integer(Seconds div 60), Integer(Seconds mod 60)])
  else
    Result := TrF('turntime.hours', [Integer(Seconds div 3600), Integer(Seconds mod 3600 div 60)]);
end;

{ Local wall-clock time of Ms (ms since 1970, UTC). }
function ClockText(Ms: Int64): string;
begin
  Result := FormatDateTime('hh:nn:ss', UnixToDateTime(Ms div 1000, False));
end;

procedure ReportTurnEnd(Stopped: Boolean);
var
  Session: TChatSession;
  StartedAt, EndedAt: Int64;
  Line: string;
begin
  Session := ChatSession;
  Stopped := Stopped or Session.Activity.StopRequested;
  { A turn end without a turn this chat started (a slash command omp answered) has no times. }
  if not Session.Activity.CloseTurn(StartedAt) then
  begin
    Session.Emit(PageTurnEnd(0, 0, Stopped));
    Exit;
  end;
  EndedAt := UnixMs;
  Session.Emit(PageTurnEnd(StartedAt, EndedAt, Stopped));
  if Stopped then
    Line := TrF('turntime.stopped', [ClockText(EndedAt), FormatDuration(EndedAt - StartedAt)])
  else
    Line := TrF('turntime.done', [ClockText(EndedAt), FormatDuration(EndedAt - StartedAt)]);
  ReportToMessageView(Line);
  { The user who stopped the turn is looking at it already. }
  if Stopped then
    Exit;
  RequestAttention;
  if TurnNotifications then
    NotifyInBackground(Line);
end;

end.
