unit DelphiAgent.RpcDispatch;

{ Splits stdout JSONL and dispatches omp v1 frames. No process and no ToolsAPI. }

interface

uses
  System.SysUtils;

type
  TRpcTextEvent = procedure(const Text: string) of object;
  TRpcNotifyEvent = procedure of object;
  TRpcFrameEvent = procedure(const Frame, FrameType: string) of object;
  TRpcHostEvent = procedure(const CallId, ToolName, Args: string) of object;
  TRpcCancelEvent = procedure(const CallId: string) of object;
  TRpcStopEvent = function: Boolean of object;
  TRpcLineEvent = procedure(const Line: string) of object;

  TRpcDispatch = record
    Post: TRpcTextEvent;
    BecomeReady: TRpcNotifyEvent;
    SendFrame: TRpcFrameEvent;
    HostCall: TRpcHostEvent;
    CancelCall: TRpcCancelEvent;
  end;

procedure DispatchRpcLine(const Line: string; const Events: TRpcDispatch);
procedure ReadStdoutLines(StdOut: THandle; Stopped: TRpcStopEvent; OnLine: TRpcLineEvent);

type
  TRpcPipes = record
    Process: THandle;
    Thread: THandle;
    StdIn: THandle;
    StdOut: THandle;
    Pid: Cardinal;
  end;

function SpawnRpcProcess(const Command, WorkDir, StderrPath: string; out Pipes: TRpcPipes): Boolean;

implementation

uses
  System.JSON, Winapi.Windows, DelphiAgent.RpcProtocol;

procedure Say(const Events: TRpcDispatch; const Text: string);
begin
  if Assigned(Events.Post) and (Text <> '') then
    Events.Post(Text);
end;

function JsonField(Obj: TJSONObject; const Name: string): string;
begin
  Result := '';
  if (Obj <> nil) and (Obj.GetValue(Name) is TJSONString) then
    Result := TJSONString(Obj.GetValue(Name)).Value;
end;

procedure DispatchRpcLine(const Line: string; const Events: TRpcDispatch);
var
  Kind, Response, CallId, ToolName, Args: string;
  Value: TJSONValue;
  Obj: TJSONObject;
begin
  if not AcceptFrameLine(Line) then
  begin
    Say(Events, 'frame exceeds 1MiB');
    Exit;
  end;
  Kind := FrameTypeOf(Line);
  if Kind = 'ready' then
  begin
    if Assigned(Events.BecomeReady) then
      Events.BecomeReady();
    Exit;
  end;
  if Kind = 'extension_ui_request' then
  begin
    Response := BuildExtensionUiResponse(Line);
    if (Response <> '') and Assigned(Events.SendFrame) then
      Events.SendFrame(Response, 'extension_ui_response');
    Exit;
  end;
  if Kind = 'host_tool_cancel' then
  begin
    Value := TJSONObject.ParseJSONValue(Line);
    if Value is TJSONObject then
    begin
      if Assigned(Events.CancelCall) then
        Events.CancelCall(JsonField(TJSONObject(Value), 'targetId'));
      Value.Free;
    end
    else
      Value.Free;
    Exit;
  end;
  { Assistant text, tool rows and errors travel as typed events (DelphiAgent.RpcEvents). }
  if (Kind <> 'host_tool_call') or not Assigned(Events.HostCall) then
    Exit;
  Value := TJSONObject.ParseJSONValue(Line);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Obj := TJSONObject(Value);
  try
    CallId := JsonField(Obj, 'id');
    ToolName := JsonField(Obj, 'toolName');
    Args := '{}';
    if Obj.GetValue('arguments') <> nil then
      Args := Obj.GetValue('arguments').ToJSON;
  finally
    Obj.Free;
  end;
  if CallId <> '' then
    Events.HostCall(CallId, ToolName, Args);
end;

procedure ReadStdoutLines(StdOut: THandle; Stopped: TRpcStopEvent; OnLine: TRpcLineEvent);
var
  Pending, Buffer: TBytes;
  ReadCount: DWORD;
  Index, LineBytes: Integer;
  Line: string;
begin
  SetLength(Pending, 0);
  SetLength(Buffer, 8192);
  while not (Assigned(Stopped) and Stopped()) and (StdOut <> 0) do
  begin
    ReadCount := 0;
    if not ReadFile(StdOut, Buffer[0], Length(Buffer), ReadCount, nil) or (ReadCount = 0) then
      Break;
    Index := Length(Pending);
    SetLength(Pending, Index + Integer(ReadCount));
    Move(Buffer[0], Pending[Index], ReadCount);
    Index := 0;
    while Index < Length(Pending) do
    begin
      if Pending[Index] <> 10 then
      begin
        Inc(Index);
        Continue;
      end;
      LineBytes := Index;
      if (LineBytes > 0) and (Pending[LineBytes - 1] = 13) then
        Dec(LineBytes);
      if LineBytes > MaxFrameBytes then
      begin
        if Assigned(OnLine) then
          OnLine('');
      end
      else if (LineBytes > 0) and Assigned(OnLine) then
      begin
        Line := TEncoding.UTF8.GetString(Pending, 0, LineBytes);
        OnLine(Line);
      end;
      if Index + 1 < Length(Pending) then
      begin
        Move(Pending[Index + 1], Pending[0], Length(Pending) - Index - 1);
        SetLength(Pending, Length(Pending) - Index - 1);
      end
      else
        SetLength(Pending, 0);
      Index := 0;
    end;
    if Length(Pending) > MaxFrameBytes then
      SetLength(Pending, 0);
  end;
end;

function SpawnRpcProcess(const Command, WorkDir, StderrPath: string; out Pipes: TRpcPipes): Boolean;
var
  Security: TSecurityAttributes;
  Startup: TStartupInfo;
  ProcessInfo: TProcessInformation;
  StdInRead, StdInWrite, StdOutRead, StdOutWrite, StdErr: THandle;
  Mutable: string;
begin
  Result := False;
  Pipes.Process := 0;
  Pipes.Thread := 0;
  Pipes.StdIn := 0;
  Pipes.StdOut := 0;
  Pipes.Pid := 0;
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  if not CreatePipe(StdInRead, StdInWrite, @Security, 0) then
    Exit;
  if not CreatePipe(StdOutRead, StdOutWrite, @Security, 0) then
  begin
    CloseHandle(StdInRead);
    CloseHandle(StdInWrite);
    Exit;
  end;
  SetHandleInformation(StdInWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(StdOutRead, HANDLE_FLAG_INHERIT, 0);
  StdErr := CreateFile(PChar(StderrPath), GENERIC_WRITE, FILE_SHARE_READ, @Security,
    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if StdErr = INVALID_HANDLE_VALUE then
  begin
    CloseHandle(StdInRead);
    CloseHandle(StdInWrite);
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    Exit;
  end;
  ZeroMemory(@Startup, SizeOf(Startup));
  Startup.cb := SizeOf(Startup);
  Startup.dwFlags := STARTF_USESTDHANDLES;
  Startup.hStdInput := StdInRead;
  Startup.hStdOutput := StdOutWrite;
  Startup.hStdError := StdErr;
  Mutable := Command;
  UniqueString(Mutable);
  ZeroMemory(@ProcessInfo, SizeOf(ProcessInfo));
  if not CreateProcess(nil, PChar(Mutable), nil, nil, True, CREATE_NO_WINDOW, nil,
    PChar(WorkDir), Startup, ProcessInfo) then
  begin
    CloseHandle(StdInRead);
    CloseHandle(StdInWrite);
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErr);
    Exit;
  end;
  CloseHandle(StdInRead);
  CloseHandle(StdOutWrite);
  CloseHandle(StdErr);
  Pipes.StdIn := StdInWrite;
  Pipes.StdOut := StdOutRead;
  Pipes.Process := ProcessInfo.hProcess;
  Pipes.Thread := ProcessInfo.hThread;
  Pipes.Pid := ProcessInfo.dwProcessId;
  Result := True;
end;

end.
