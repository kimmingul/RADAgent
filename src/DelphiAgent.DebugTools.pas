unit DelphiAgent.DebugTools;

{ Read-only debugger host tools: state, call stack, side-effect-free evaluate, breakpoints.
  Main thread only. Never resumes, steps, or modifies the debuggee. }

interface

function IsDebugTool(const ToolName: string): Boolean;
procedure ExecuteDebugTool(const ToolName, Expression: string;
  out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.JSON, Winapi.Windows, ToolsAPI, DelphiAgent.HostToolDefs;

const
  MaxStackFrames = 64;
  EvalBufferChars = 4096;
  ProcessStateNames: array[TOTAProcessState] of string = ('nothing', 'running',
    'stopping', 'stopped', 'fault', 'resFault', 'terminated', 'exception', 'noProcess');
  ThreadStateNames: array[TOTAThreadState] of string = ('stopped', 'runnable',
    'blocked', 'none', 'other');

function IsDebugTool(const ToolName: string): Boolean;
begin
  Result := (ToolName = ToolDebugState) or (ToolName = ToolDebugStack) or
    (ToolName = ToolDebugEvaluate) or (ToolName = ToolDebugBreakpoints);
end;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
    Result := nil;
end;

function CurrentProcess: IOTAProcess;
var
  Services: IOTADebuggerServices;
begin
  Result := nil;
  Services := Debugger;
  if (Services <> nil) and (Services.ProcessCount > 0) then
    Result := Services.CurrentProcess;
end;

function IsStopped(const Process: IOTAProcess): Boolean;
begin
  Result := Process.ProcessState in [psStopped, psFault, psResFault, psException];
end;

{ Returns the stopped current thread, or nil with Problem set. }
function StoppedThread(out Problem: string): IOTAThread;
var
  Process: IOTAProcess;
begin
  Result := nil;
  Process := CurrentProcess;
  if Process = nil then
  begin
    Problem := '디버그 중인 프로세스가 없습니다.';
    Exit;
  end;
  if not IsStopped(Process) then
  begin
    Problem := '프로세스가 멈춰 있지 않습니다. 상태=' + ProcessStateNames[Process.ProcessState];
    Exit;
  end;
  Result := Process.CurrentThread;
  if Result = nil then
    Problem := '현재 스레드가 없습니다.';
end;

function StateJson: string;
var
  Process: IOTAProcess;
  Thread: IOTAThread;
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Process := CurrentProcess;
    if Process = nil then
      Obj.AddPair('process', TJSONFalse.Create)
    else
    begin
      Obj.AddPair('process', TJSONTrue.Create);
      Obj.AddPair('pid', TJSONNumber.Create(Process.OSProcessId));
      Obj.AddPair('state', ProcessStateNames[Process.ProcessState]);
      Thread := Process.CurrentThread;
      if Thread <> nil then
      begin
        Obj.AddPair('threadId', TJSONNumber.Create(Thread.OSThreadID));
        Obj.AddPair('threadState', ThreadStateNames[Thread.State]);
        if IsStopped(Process) and (Thread.CurrentFile <> '') then
        begin
          Obj.AddPair('file', Thread.CurrentFile);
          Obj.AddPair('line', TJSONNumber.Create(Thread.CurrentLine));
        end;
      end;
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function StackJson(out ResultText: string): Boolean;
var
  Thread: IOTAThread;
  Problem, FileName: string;
  Frames: TJSONArray;
  Frame: TJSONObject;
  Index, Count, LineNum: Integer;
begin
  Result := False;
  Thread := StoppedThread(Problem);
  if Thread = nil then
  begin
    ResultText := Problem;
    Exit;
  end;
  case Thread.StartCallStackAccess of
    csInaccessible:
      begin
        Thread.EndCallStackAccess;
        ResultText := '이 스레드의 호출 스택을 읽을 수 없습니다.';
        Exit;
      end;
    csWait:
      begin
        Thread.EndCallStackAccess;
        ResultText := '호출 스택이 아직 준비되지 않았습니다. 잠시 후 다시 호출하세요.';
        Exit;
      end;
  end;
  Frames := TJSONArray.Create;
  try
    try
      Count := Thread.CallCount;
      if Count > MaxStackFrames then
        Count := MaxStackFrames;
      for Index := 1 to Count do
      begin
        Frame := TJSONObject.Create;
        Frame.AddPair('index', TJSONNumber.Create(Index));
        Frame.AddPair('header', Thread.CallHeaders[Index]);
        Thread.GetCallPos(Index, FileName, LineNum);
        if FileName <> '' then
        begin
          Frame.AddPair('file', FileName);
          Frame.AddPair('line', TJSONNumber.Create(LineNum));
        end;
        Frames.AddElement(Frame);
      end;
    finally
      Thread.EndCallStackAccess;
    end;
    ResultText := Frames.ToJSON;
    Result := True;
  finally
    Frames.Free;
  end;
end;

function EvaluateJson(const Expression: string; out ResultText: string): Boolean;
var
  Thread: IOTAThread;
  Problem: string;
  Buffer: array[0..EvalBufferChars - 1] of Char;
  CanModify: Boolean;
  Addr: TOTAAddress;
  Size, Val: LongWord;
  Obj: TJSONObject;
begin
  Result := False;
  if Trim(Expression) = '' then
  begin
    ResultText := 'expression이 비어 있습니다.';
    Exit;
  end;
  Thread := StoppedThread(Problem);
  if Thread = nil then
  begin
    ResultText := Problem;
    Exit;
  end;
  Buffer[0] := #0;
  case Thread.Evaluate(Expression, @Buffer[0], Length(Buffer), CanModify, False,
    nil, Addr, Size, Val) of
    erOK:
      begin
        Obj := TJSONObject.Create;
        try
          Obj.AddPair('expression', Expression);
          Obj.AddPair('value', string(PChar(@Buffer[0])));
          ResultText := Obj.ToJSON;
        finally
          Obj.Free;
        end;
        Result := True;
      end;
    erError:
      ResultText := '평가 오류: ' + string(PChar(@Buffer[0]));
    erDeferred:
      ResultText := '평가가 지연되었습니다. 부작용 없는 식으로 다시 시도하세요.';
    erBusy:
      ResultText := '디버거가 바쁩니다. 잠시 후 다시 호출하세요.';
  end;
end;

function BreakpointsJson: string;
var
  Services: IOTADebuggerServices;
  Point: IOTASourceBreakpoint;
  List: TJSONArray;
  Obj: TJSONObject;
  Index: Integer;
begin
  List := TJSONArray.Create;
  try
    Services := Debugger;
    if Services <> nil then
      for Index := 0 to Services.SourceBkptCount - 1 do
      begin
        Point := Services.SourceBkpts[Index];
        if Point = nil then
          Continue;
        Obj := TJSONObject.Create;
        Obj.AddPair('file', Point.FileName);
        Obj.AddPair('line', TJSONNumber.Create(Point.LineNumber));
        if Point.Enabled then
          Obj.AddPair('enabled', TJSONTrue.Create)
        else
          Obj.AddPair('enabled', TJSONFalse.Create);
        if Point.Expression <> '' then
          Obj.AddPair('condition', Point.Expression);
        List.AddElement(Obj);
      end;
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

procedure ExecuteDebugTool(const ToolName, Expression: string;
  out ResultText: string; out IsError: Boolean);
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  ResultText := '';
  IsError := True;
  if Debugger = nil then
  begin
    ResultText := '디버거 서비스를 찾지 못했습니다.';
    Exit;
  end;
  if ToolName = ToolDebugState then
  begin
    ResultText := StateJson;
    IsError := False;
  end
  else if ToolName = ToolDebugStack then
    IsError := not StackJson(ResultText)
  else if ToolName = ToolDebugEvaluate then
    IsError := not EvaluateJson(Expression, ResultText)
  else if ToolName = ToolDebugBreakpoints then
  begin
    ResultText := BreakpointsJson;
    IsError := False;
  end
  else
    ResultText := 'unknown debug tool';
end;

end.
