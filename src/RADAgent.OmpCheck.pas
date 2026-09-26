unit RADAgent.OmpCheck;

{ Version changes noticed at the first omp start of an IDE session. omp: runs RADAgent.OmpProbe
  when omp changed (a new "omp --version" since the last passing check), in the background, and
  reports in the chat; the settings dialog runs it on demand. RAD Agent: says once in the chat
  that it was installed or updated, with its release notes. Main thread only (the probe itself
  runs on its own thread). }

interface

{ At every omp start; probes once per IDE session, and only for a version not yet checked. }
procedure CheckOmpAfterUpdate(const WorkDir: string);
{ Settings dialog: probes now (a few seconds, blocking) and returns the report text. }
function OmpCheckReport(const WorkDir: string): string;
{ The installed omp's version as far as known ("omp --version" of this session, else the last
  checked one); '' when never seen. }
function KnownOmpVersion: string;
{ At every omp start; a chat notice once when RAD Agent's version differs from the last one seen. }
procedure AnnounceAgentUpdate;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, RADAgent.OmpProbe, RADAgent.AgentSettings,
  RADAgent.ChatSession, RADAgent.ChatPageMessages, RADAgent.AgentVersion, RADAgent.Options, RADAgent.Lang;

type
  TProbeThread = class(TThread)
  private
    FExecutable, FWorkDir, FChecked, FVersion: string;
    FChecks: TArray<TOmpCheck>;
    procedure Report;
    procedure Publish;
  protected
    procedure Execute; override;
  public
    constructor Create(const Executable, WorkDir, Checked: string);
  end;

var
  GThread: TProbeThread;
  GOmpVersion: string;
  GAnnounced: Boolean;

constructor TProbeThread.Create(const Executable, WorkDir, Checked: string);
begin
  FExecutable := Executable;
  FWorkDir := WorkDir;
  FChecked := Checked;
  inherited Create(False);
end;

procedure TProbeThread.Execute;
begin
  FVersion := OmpVersionText(FExecutable);
  if not Terminated then
    Queue(Publish);
  if (FVersion = '') or (FVersion = FChecked) then
    Exit;
  FChecks := ProbeOmp(FExecutable, FWorkDir,
    function: Boolean
    begin
      Result := Terminated;
    end);
  if not Terminated then
    { Bound to this thread: freeing it drops the call if it has not run yet. }
    Queue(Report);
end;

function FailedNames(const Checks: TArray<TOmpCheck>): string;
var
  Item: TOmpCheck;
begin
  Result := '';
  for Item in Checks do
    if not Item.Ok then
      Result := Result + IfThen(Result = '', '', '; ') + Item.Name + ' (' + Item.Detail + ')';
end;

procedure TProbeThread.Publish;
begin
  if (FVersion = '') or (FVersion = GOmpVersion) then
    Exit;
  GOmpVersion := FVersion;
  SetRpcLogHeader('version ' + VersionLine(GOmpVersion));
  AppendRpcLog('version ' + VersionLine(GOmpVersion));
end;

procedure TProbeThread.Report;
begin
  if AllPassed(FChecks) then
  begin
    SetCheckedOmpVersion(FVersion);
    if FVersion <> TestedOmpVersion then
      ChatSession.Notice('info', TrF('ompcheck.passedNotice', [FVersion, Length(FChecks), TestedOmpVersion]));
  end
  else
    ChatSession.Notice('warn', TrF('ompcheck.failedNotice',
      [FVersion, FailedNames(FChecks), TestedOmpVersion]));
end;

procedure CheckOmpAfterUpdate(const WorkDir: string);
begin
  if GThread <> nil then
    Exit;
  GThread := TProbeThread.Create(OmpCommand, WorkDir, CheckedOmpVersion);
end;

function OmpCheckReport(const WorkDir: string): string;
var
  Checks: TArray<TOmpCheck>;
  Version: string;
begin
  Version := OmpVersionText(OmpCommand);
  if Version <> '' then
    GOmpVersion := Version;
  Checks := ProbeOmp(OmpCommand, WorkDir);
  if AllPassed(Checks) then
    SetCheckedOmpVersion(Version);
  Result := ProbeReport(Checks);
end;

function KnownOmpVersion: string;
begin
  Result := GOmpVersion;
  if Result = '' then
    Result := CheckedOmpVersion;
end;

procedure AnnounceAgentUpdate;
var
  Seen: string;
begin
  if GAnnounced or (AgentVersion = '') then
    Exit;
  GAnnounced := True;
  Seen := SeenAgentVersion;
  if Seen = AgentVersion then
    Exit;
  SetSeenAgentVersion(AgentVersion);
  if Seen = '' then
    ChatSession.Emit(PageLinkNotice('info', TrF('ompcheck.agentInstalled', [AgentVersion]),
      Tr('ompcheck.releaseNotes'), ReleaseNotesUrl))
  else
    ChatSession.Emit(PageLinkNotice('info', TrF('ompcheck.agentUpdated', [Seen, AgentVersion]),
      Tr('ompcheck.releaseNotes'), ReleaseNotesUrl));
end;

initialization

finalization
  if GThread <> nil then
  begin
    GThread.Terminate;
    GThread.WaitFor;
    FreeAndNil(GThread);
  end;

end.
