unit DelphiAgent.OmpCheck;

{ Runs DelphiAgent.OmpProbe when omp changed (a new "omp --version" since the last passing check),
  in the background at the first omp start of an IDE session, and reports in the chat. The settings
  dialog runs it on demand. Main thread only (the probe itself runs on its own thread). }

interface

{ At every omp start; probes once per IDE session, and only for a version not yet checked. }
procedure CheckOmpAfterUpdate(const WorkDir: string);
{ Settings dialog: probes now (a few seconds, blocking) and returns the report text. }
function OmpCheckReport(const WorkDir: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, DelphiAgent.OmpProbe, DelphiAgent.AgentSettings,
  DelphiAgent.ChatSession;

type
  TProbeThread = class(TThread)
  private
    FExecutable, FWorkDir, FChecked, FVersion: string;
    FChecks: TArray<TOmpCheck>;
    procedure Report;
  protected
    procedure Execute; override;
  public
    constructor Create(const Executable, WorkDir, Checked: string);
  end;

var
  GThread: TProbeThread;

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

procedure TProbeThread.Report;
begin
  if AllPassed(FChecks) then
  begin
    SetCheckedOmpVersion(FVersion);
    if FVersion <> TestedOmpVersion then
      ChatSession.Notice('info', Format('omp %s를 확인했습니다: 호환성 검사 %d개 모두 통과 ' +
        '(DelphiAgent 검증 버전 %s).', [FVersion, Length(FChecks), TestedOmpVersion]));
  end
  else
    ChatSession.Notice('warn', Format('omp %s 호환성 검사에서 문제가 있습니다: %s. DelphiAgent의 일부 ' +
      '기능이 동작하지 않을 수 있습니다. 설정 > 고급 > omp 호환성 검사에서 다시 볼 수 있습니다. ' +
      '검증 버전 %s의 omp를 쓰면 해결됩니다(canary 채널이면 "omp update --stable").',
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
  Checks := ProbeOmp(OmpCommand, WorkDir);
  if AllPassed(Checks) then
    SetCheckedOmpVersion(Version);
  Result := ProbeReport(Checks);
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
