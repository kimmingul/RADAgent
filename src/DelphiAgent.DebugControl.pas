unit DelphiAgent.DebugControl;

{ Debugger execution control that runs only after the user approves: run or continue, step,
  pause, reset, add a source breakpoint. Main thread only. Never writes debuggee memory. }

interface

uses
  DelphiAgent.Approval;

type
  TDebugControlArgs = record
    Mode: string;
    FileName: string;
    Line: Integer;
  end;

function IsDebugControlTool(const ToolName: string): Boolean;
procedure ExecuteDebugControl(const ToolName: string; const Args: TDebugControlArgs;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.Actions, Vcl.Forms, Vcl.ActnList, Winapi.Windows, ToolsAPI,
  DelphiAgent.HostToolDefs, DelphiAgent.DebugTools;

const
  STarget = '디버거';
  { The IDE's Run > Run action: builds the active project and starts it under the debugger. }
  RunActionName = 'RunRunCommand';
  SettleMs = 5000;

function IsDebugControlTool(const ToolName: string): Boolean;
begin
  Result := (ToolName = ToolDebugRun) or (ToolName = ToolDebugStep) or
    (ToolName = ToolDebugPause) or (ToolName = ToolDebugReset) or
    (ToolName = ToolDebugAddBreakpoint);
end;

function FindIdeAction(const Name: string): TContainedAction;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
    if SameText(Services.ActionList.Actions[Index].Name, Name) then
      Exit(Services.ActionList.Actions[Index]);
end;

{ Debug events arrive as IDE messages; pump them until the process stops, ends, or time runs out. }
procedure WaitSettled;
var
  Deadline: UInt64;
  Process: IOTAProcess;
begin
  Deadline := GetTickCount64 + SettleMs;
  repeat
    Application.ProcessMessages;
    Sleep(50);
    Process := CurrentProcess;
  until (GetTickCount64 >= Deadline) or ((Process <> nil) and (IsStopped(Process) or
    (Process.ProcessState = psTerminated)));
end;

function StepMode(const Mode: string; out RunMode: TOTARunMode; out Caption: string): Boolean;
begin
  Result := True;
  if (Mode = '') or SameText(Mode, 'over') then
  begin
    RunMode := ormStmtStepOver;
    Caption := '한 줄 실행 (Step Over, F8)';
  end
  else if SameText(Mode, 'into') then
  begin
    RunMode := ormStmtStepInto;
    Caption := '안으로 들어가기 (Step Into, F7)';
  end
  else if SameText(Mode, 'return') then
  begin
    RunMode := ormRunUntilReturn;
    Caption := '함수 끝까지 실행 (Run Until Return, Shift+F8)';
  end
  else
    Result := False;
end;

function Approved(const Approval: IAgentApproval; const Preview: string; out Problem: string): Boolean;
begin
  Result := (Approval <> nil) and Approval.ApproveChange(STarget, '', Preview);
  if not Result then
    Problem := SEditCancelled;
end;

function RunOrContinue(const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Process: IOTAProcess;
  Action: TContainedAction;
begin
  Result := False;
  Process := CurrentProcess;
  if Process = nil then
  begin
    Action := FindIdeAction(RunActionName);
    if Action = nil then
    begin
      Problem := 'IDE의 실행 명령을 찾지 못했습니다.';
      Exit;
    end;
    Action.Update;
    if not Action.Enabled then
    begin
      Problem := '지금은 실행할 수 없습니다. 활성 프로젝트를 확인하세요.';
      Exit;
    end;
    if not Approved(Approval, '활성 프로젝트를 빌드하고 디버거로 실행 (Run, F9)', Problem) then
      Exit;
    Action.Execute;
  end
  else
  begin
    if not IsStopped(Process) then
    begin
      Problem := '프로세스가 이미 실행 중입니다.';
      Exit;
    end;
    if not Approved(Approval, '멈춘 프로그램 계속 실행 (Run, F9)', Problem) then
      Exit;
    Process := CurrentProcess;
    if (Process = nil) or not IsStopped(Process) then
    begin
      Problem := '승인하는 동안 디버거 상태가 바뀌었습니다.';
      Exit;
    end;
    Process.Run(ormRun);
  end;
  WaitSettled;
  Result := True;
end;

function StepProcess(const Mode: string; const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Process: IOTAProcess;
  RunMode: TOTARunMode;
  Caption: string;
begin
  Result := False;
  if not StepMode(Mode, RunMode, Caption) then
  begin
    Problem := 'mode는 over, into, return 중 하나입니다: ' + Mode;
    Exit;
  end;
  Process := CurrentProcess;
  if (Process = nil) or not IsStopped(Process) then
  begin
    Problem := '멈춘 디버그 프로세스가 없습니다.';
    Exit;
  end;
  if not Approved(Approval, Caption, Problem) then
    Exit;
  Process := CurrentProcess;
  if (Process = nil) or not IsStopped(Process) then
  begin
    Problem := '승인하는 동안 디버거 상태가 바뀌었습니다.';
    Exit;
  end;
  Process.Run(RunMode);
  WaitSettled;
  Result := True;
end;

function PauseProcess(const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Process: IOTAProcess;
begin
  Result := False;
  Process := CurrentProcess;
  if (Process = nil) or IsStopped(Process) then
  begin
    Problem := '실행 중인 디버그 프로세스가 없습니다.';
    Exit;
  end;
  if not Approved(Approval, '실행 중인 프로그램 일시 정지 (Pause)', Problem) then
    Exit;
  Process := CurrentProcess;
  if Process = nil then
  begin
    Problem := '승인하는 동안 프로세스가 끝났습니다.';
    Exit;
  end;
  Process.Pause;
  WaitSettled;
  Result := True;
end;

function ResetProgram(const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Process: IOTAProcess;
begin
  Result := False;
  if CurrentProcess = nil then
  begin
    Problem := '디버그 중인 프로세스가 없습니다.';
    Exit;
  end;
  if not Approved(Approval, '디버그 중인 프로그램 종료 (Program Reset, Ctrl+F2)', Problem) then
    Exit;
  Process := CurrentProcess;
  if Process <> nil then
    Process.Terminate;
  WaitSettled;
  Result := True;
end;

function AddBreakpoint(const Args: TDebugControlArgs; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  Services: IOTADebuggerServices;
  Index: Integer;
begin
  Result := False;
  if (Args.FileName = '') or (Args.Line <= 0) then
  begin
    Problem := 'file과 1 이상의 line이 필요합니다.';
    Exit;
  end;
  Services := Debugger;
  for Index := 0 to Services.SourceBkptCount - 1 do
    if (Services.SourceBkpts[Index] <> nil) and
      SameText(Services.SourceBkpts[Index].FileName, Args.FileName) and
      (Services.SourceBkpts[Index].LineNumber = Args.Line) then
    begin
      Problem := '이미 같은 줄에 중단점이 있습니다.';
      Exit;
    end;
  if not Approved(Approval, Format('중단점 추가: %s(%d)', [Args.FileName, Args.Line]), Problem) then
    Exit;
  if Services.NewSourceBreakpoint(Args.FileName, Args.Line, nil) = nil then
  begin
    Problem := '중단점을 만들지 못했습니다.';
    Exit;
  end;
  Result := True;
end;

procedure ExecuteDebugControl(const ToolName: string; const Args: TDebugControlArgs;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);
var
  Ok: Boolean;
  Problem: string;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  IsError := True;
  if Debugger = nil then
  begin
    ResultText := '디버거 서비스를 찾지 못했습니다.';
    Exit;
  end;
  Problem := '';
  if ToolName = ToolDebugRun then
    Ok := RunOrContinue(Approval, Problem)
  else if ToolName = ToolDebugStep then
    Ok := StepProcess(Args.Mode, Approval, Problem)
  else if ToolName = ToolDebugPause then
    Ok := PauseProcess(Approval, Problem)
  else if ToolName = ToolDebugReset then
    Ok := ResetProgram(Approval, Problem)
  else
    Ok := AddBreakpoint(Args, Approval, Problem);
  if Ok then
  begin
    { After a run/step the model sees where the debuggee is now. }
    ResultText := DebugStateJson;
    IsError := False;
  end
  else
  begin
    ResultText := Problem;
    IsError := Problem <> SEditCancelled;
  end;
end;

end.
