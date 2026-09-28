unit RADAgent.ProjectFollow;

{ The conversation follows its project when the project's folder changes under a running omp
  (Save As of a new project from the default Projects folder, or of any project): omp restarts in
  the new folder and its session file moves to the folder omp keeps that folder's sessions in, so
  reopening the project later lists it. Another project (different ProjectGUID) starts a fresh
  conversation (RADAgent.SessionMove moves the file). }

interface

type
  TFollowLeave = (flFollow, flDefer, flSwitch);

  TProjectFollow = record
  private
    FGuid, FCwd, FCarry: string;
  public
    { Dir differs from the folder omp was started in (both known). }
    function Moved(const Dir: string): Boolean;
    { omp is about to be stopped because Dir changed: flFollow carries SessionFile to the new
      folder, flDefer waits for the running turn of the same project, flSwitch is another project. }
    function Leave(const SessionFile: string; Busy: Boolean): TFollowLeave;
    { omp starts in Dir; ResumeFile is the session a restart would reopen. Returns the file to
      reopen with switch_session now ('' when it has to move first or belongs to another project). }
    function Start(const Dir, ResumeFile: string): string;
    { omp reported its (new) SessionFile: moves a carried session next to it. True with the path
      to switch to. }
    function Arrived(const SessionFile: string; out MovedFile: string): Boolean;
  end;

implementation

uses
  System.SysUtils, RADAgent.IdeContext, RADAgent.SessionMove;

function TProjectFollow.Moved(const Dir: string): Boolean;
begin
  Result := (FCwd <> '') and (Dir <> '') and
    not SameText(ExcludeTrailingPathDelimiter(FCwd), ExcludeTrailingPathDelimiter(Dir));
end;

function TProjectFollow.Leave(const SessionFile: string; Busy: Boolean): TFollowLeave;
begin
  FCarry := '';
  if not SameText(FGuid, ActiveProjectGuid) then
    Exit(flSwitch);
  if Busy then
    Exit(flDefer);
  FCarry := SessionFile;
  Result := flFollow;
end;

function TProjectFollow.Start(const Dir, ResumeFile: string): string;
begin
  Result := ResumeFile;
  if Moved(Dir) and (ResumeFile <> '') then
  begin
    if SameText(FGuid, ActiveProjectGuid) then
      FCarry := ResumeFile;
    Result := '';
  end;
  FGuid := ActiveProjectGuid;
  FCwd := Dir;
end;

function TProjectFollow.Arrived(const SessionFile: string; out MovedFile: string): Boolean;
begin
  MovedFile := '';
  Result := (FCarry <> '') and (SessionFile <> '');
  if not Result then
    Exit;
  MovedFile := MoveSessionFile(FCarry, ExtractFileDir(SessionFile), ExcludeTrailingPathDelimiter(FCwd));
  FCarry := '';
end;

end.
