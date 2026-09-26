unit RADAgent.DebugControl;

{ Debugger execution control that runs only after the user approves: run or continue, step,
  pause, reset, add a source breakpoint. An exception the debuggee raises while run or step waits
  is reported in the result (RADAgent.DebugExceptionWatch). Main thread only. Never writes
  debuggee memory. }

interface

uses
  RADAgent.Approval;

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
  System.SysUtils, System.Classes, System.Actions, System.JSON, Vcl.Forms, Vcl.ActnList, Winapi.Windows,
  ToolsAPI, RADAgent.HostToolDefs, RADAgent.DebugTools, RADAgent.DebugExceptionWatch, RADAgent.Lang;

const
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
    Caption := Tr('debugcontrol.stepOver');
  end
  else if SameText(Mode, 'into') then
  begin
    RunMode := ormStmtStepInto;
    Caption := Tr('debugcontrol.stepInto');
  end
  else if SameText(Mode, 'return') then
  begin
    RunMode := ormRunUntilReturn;
    Caption := Tr('debugcontrol.stepReturn');
  end
  else
    Result := False;
end;

function Approved(const Approval: IAgentApproval; const Preview: string; out Problem: string): Boolean;
begin
  Result := (Approval <> nil) and Approval.ApproveChange(Tr('debugcontrol.targetDebugger'), '', Preview);
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
      Problem := 'IDE run command not found.';
      Exit;
    end;
    Action.Update;
    if not Action.Enabled then
    begin
      Problem := 'Cannot run now. Check the active project.';
      Exit;
    end;
    if not Approved(Approval, Tr('debugcontrol.runBuild'), Problem) then
      Exit;
    Action.Execute;
  end
  else
  begin
    if not IsStopped(Process) then
    begin
      Problem := 'Process is already running.';
      Exit;
    end;
    if not Approved(Approval, Tr('debugcontrol.runContinue'), Problem) then
      Exit;
    Process := CurrentProcess;
    if (Process = nil) or not IsStopped(Process) then
    begin
      Problem := 'Debugger state changed while waiting for approval.';
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
    Problem := 'Mode must be one of over, into, return: ' + Mode;
    Exit;
  end;
  Process := CurrentProcess;
  if (Process = nil) or not IsStopped(Process) then
  begin
    Problem := 'No paused debug process.';
    Exit;
  end;
  if not Approved(Approval, Caption, Problem) then
    Exit;
  Process := CurrentProcess;
  if (Process = nil) or not IsStopped(Process) then
  begin
    Problem := 'Debugger state changed while waiting for approval.';
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
    Problem := 'No running debug process.';
    Exit;
  end;
    if not Approved(Approval, Tr('debugcontrol.pause'), Problem) then
    Exit;
  Process := CurrentProcess;
  if Process = nil then
  begin
    Problem := 'Process terminated while waiting for approval.';
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
    Problem := 'No process being debugged.';
    Exit;
  end;
    if not Approved(Approval, Tr('debugcontrol.reset'), Problem) then
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
    Problem := 'File name and line number >= 1 are required.';
    Exit;
  end;
  Services := Debugger;
  for Index := 0 to Services.SourceBkptCount - 1 do
    if (Services.SourceBkpts[Index] <> nil) and
      SameText(Services.SourceBkpts[Index].FileName, Args.FileName) and
      (Services.SourceBkpts[Index].LineNumber = Args.Line) then
    begin
      Problem := 'A breakpoint already exists on this line.';
      Exit;
    end;
  if not Approved(Approval, TrF('debugcontrol.addBreakpoint', [Args.FileName, Args.Line]), Problem) then
    Exit;
  if Services.NewSourceBreakpoint(Args.FileName, Args.Line, nil) = nil then
  begin
    Problem := 'Failed to create breakpoint.';
    Exit;
  end;
  Result := True;
end;

procedure ExecuteDebugControl(const ToolName: string; const Args: TDebugControlArgs;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);
var
  Ok: Boolean;
  Problem: string;
  Watch: TDebugExceptionWatch;
  State: TJSONValue;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  IsError := True;
  if Debugger = nil then
  begin
    ResultText := 'Debugger service not found.';
    Exit;
  end;
  Problem := '';
  Watch := TDebugExceptionWatch.Create;
  try
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
      { After a run/step the model sees where the debuggee is now, and why it stopped. }
      ResultText := DebugStateJson;
      if Watch.Message <> '' then
      begin
        State := TJSONObject.ParseJSONValue(ResultText);
        try
          if State is TJSONObject then
          begin
            TJSONObject(State).AddPair('exception', Watch.Message);
            TJSONObject(State).AddPair('note', 'Stopped at the exception. Read the call stack (' +
              ToolDebugStack + ') before changing code; ' + ToolDebugReset + ' ends the process.');
            ResultText := State.ToJSON;
          end;
        finally
          State.Free;
        end;
      end;
      IsError := False;
    end
    else
    begin
      ResultText := Problem;
      IsError := Problem <> SEditCancelled;
    end;
  finally
    Watch.Free;
  end;
end;

end.
