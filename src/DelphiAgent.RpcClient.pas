unit DelphiAgent.RpcClient;
{ omp --mode rpc child. The read thread never calls ToolsAPI. }
interface
uses
  System.Classes, System.SysUtils, DelphiAgent.RpcDispatch;
type
  TRpcLogEvent = procedure(const Text: string) of object;
  TRpcStatusEvent = procedure of object;
  TRpcHostToolEvent = procedure(const CallId, ToolName, ArgumentsJson: string) of object;
  TAgentRpcClient = class
  private
    type
      TRpcReader = class(TThread)
      public
        Client: TAgentRpcClient;
        procedure Execute; override;
      end;
  private
    FProcess: THandle;
    FThreadHandle: THandle;
    FPid: Cardinal;
    FStdIn: THandle;
    FStdOut: THandle;
    FReader: TRpcReader;
    FLock: TObject;
    FCancel: TObject;
    FReady: Boolean;
    FHostToolsSent: Boolean;
    FAlive: Boolean;
    FNextId: Integer;
    FCwd: string;
    FOnLog: TRpcLogEvent;
    FOnStatus: TRpcStatusEvent;
    FOnHostTool: TRpcHostToolEvent;
    FOnModels: TRpcLogEvent;
    FOnUi: TRpcLogEvent;
    FEvents: TRpcDispatch;
    FLinkError: string;
    FModel: string;
    FStateCwd: string;
    FStopping: Boolean;
    procedure WriteFrame(const Frame, FrameType: string);
    procedure QueueFrame(const Frame, FrameType: string);
    procedure QueueHost(const CallId, ToolName, Args: string);
    procedure QueueUi(const Line: string);
    procedure QueueModels(const Text: string);
    procedure NoteReady;
    procedure ReadLoop;
    procedure ReaderLine(const Line: string);
    function ReaderStopped: Boolean;
    procedure SendHostTools;
    procedure Post(const Text: string);
    procedure NoteCancel(const CallId: string);
  public
    constructor Create;
    destructor Destroy; override;
    function Start(const Executable, WorkDir: string): Boolean;
    procedure Stop;
    function SendPrompt(const Message: string): Boolean;
    procedure SendAbort;
    procedure SendRaw(const FrameType, Frame: string);
    procedure SendHostResult(const CallId, Text: string; IsError: Boolean);
    function WasCancelled(const CallId: string): Boolean;
    property Ready: Boolean read FReady;
    property HostToolsSent: Boolean read FHostToolsSent;
    property Pid: Cardinal read FPid;
    property Cwd: string read FCwd;
    property OnLog: TRpcLogEvent read FOnLog write FOnLog;
    property OnStatus: TRpcStatusEvent read FOnStatus write FOnStatus;
    property OnHostTool: TRpcHostToolEvent read FOnHostTool write FOnHostTool;
    property OnModels: TRpcLogEvent read FOnModels write FOnModels;
    property OnUi: TRpcLogEvent read FOnUi write FOnUi;
    property LinkError: string read FLinkError;
    property ModelLabel: string read FModel;
    property StateCwd: string read FStateCwd;
  end;
procedure ShutdownActiveClient;
implementation
uses
  System.JSON, System.SyncObjs, Winapi.Windows,
  DelphiAgent.Options, DelphiAgent.RpcProtocol, DelphiAgent.ChatCommand;
var
  GActive: TAgentRpcClient;
  GGate: TCriticalSection;
procedure ShutdownActiveClient;
begin
  GGate.Acquire;
  try
    if GActive <> nil then
      GActive.Stop;
  finally
    GGate.Release;
  end;
end;
procedure TAgentRpcClient.TRpcReader.Execute;
begin
  if Client <> nil then
    Client.ReadLoop;
end;
constructor TAgentRpcClient.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCancel := TStringList.Create;
  FAlive := True;
end;
destructor TAgentRpcClient.Destroy;
begin
  FAlive := False;
  Stop;
  CheckSynchronize;
  FCancel.Free;
  FLock.Free;
  inherited;
end;
procedure TAgentRpcClient.Post(const Text: string);
begin
  if not FAlive or not Assigned(FOnLog) or (Text = '') then
    Exit;
  TThread.Queue(TThread(nil),
    procedure
    begin
      if FAlive and Assigned(FOnLog) then
        FOnLog(Text);
    end);
end;
procedure TAgentRpcClient.WriteFrame(const Frame, FrameType: string);
var
  Bytes: TBytes;
  Offset, Written: DWORD;
begin
  if not AllowOutbound(FReady, FrameType) then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(Frame + #10);
  if Length(Bytes) > MaxFrameBytes then
    Exit;
  AppendRpcLog('> ' + Frame);
  TCriticalSection(FLock).Acquire;
  try
    Offset := 0;
    while (FStdIn <> 0) and (Offset < DWORD(Length(Bytes))) do
    begin
      if not WriteFile(FStdIn, Bytes[Offset], DWORD(Length(Bytes)) - Offset, Written, nil) then
        Exit;
      if Written = 0 then
        Exit;
      Inc(Offset, Written);
    end;
  finally
    TCriticalSection(FLock).Release;
  end;
end;
procedure TAgentRpcClient.QueueFrame(const Frame, FrameType: string);
begin
  TThread.Queue(TThread(nil),
    procedure
    begin
      if FAlive then
        WriteFrame(Frame, FrameType);
    end);
end;
procedure TAgentRpcClient.QueueHost(const CallId, ToolName, Args: string);
begin
  TThread.Queue(TThread(nil), procedure begin if FAlive and Assigned(FOnHostTool) then FOnHostTool(CallId, ToolName, Args); end);
end;
procedure TAgentRpcClient.QueueUi(const Line: string);
begin
  TThread.Queue(TThread(nil), procedure begin if FAlive and Assigned(FOnUi) then FOnUi(Line); end);
end;
procedure TAgentRpcClient.QueueModels(const Text: string);
begin
  TThread.Queue(TThread(nil), procedure begin if FAlive and Assigned(FOnModels) then FOnModels(Text); end);
end;
procedure TAgentRpcClient.NoteCancel(const CallId: string);
var
  List: TStringList;
begin
  if CallId = '' then
    Exit;
  TCriticalSection(FLock).Acquire;
  try
    List := TStringList(FCancel);
    if List.IndexOf(CallId) < 0 then
      List.Add(CallId);
  finally
    TCriticalSection(FLock).Release;
  end;
end;
function TAgentRpcClient.WasCancelled(const CallId: string): Boolean;
begin
  TCriticalSection(FLock).Acquire;
  try
    Result := TStringList(FCancel).IndexOf(CallId) >= 0;
  finally
    TCriticalSection(FLock).Release;
  end;
end;
procedure TAgentRpcClient.NoteReady;
begin
  FReady := True;
  TThread.Queue(TThread(nil), procedure begin if FAlive then SendHostTools; end);
end;
procedure TAgentRpcClient.SendHostTools;
begin
  if FHostToolsSent or not FReady then Exit;
  WriteFrame(BuildSetHostToolsFrame(NewRequestId(FNextId)), 'set_host_tools');
  WriteFrame(BuildIdTypeFrame(NewRequestId(FNextId), 'get_state'), 'get_state');
  WriteFrame(BuildIdTypeFrame(NewRequestId(FNextId), 'get_available_commands'), 'get_available_commands');
  FHostToolsSent := True;
  if Assigned(FOnStatus) then FOnStatus();
end;
procedure TAgentRpcClient.ReaderLine(const Line: string);
var
  Model, Cwd, Models: string;
begin
  if Line = '' then begin Post('frame exceeds 1MiB'); Exit; end;
  AppendRpcLog('< ' + Line);
  if StateModelAndCwd(Line, Model, Cwd) then
  begin
    if Model <> '' then FModel := Model;
    if Cwd <> '' then FStateCwd := Cwd;
    TThread.Queue(TThread(nil), procedure begin if FAlive and Assigned(FOnStatus) then FOnStatus(); end);
  end;
  if Assigned(FOnUi) and (FrameTypeOf(Line) = 'extension_ui_request') then begin QueueUi(Line); Exit; end;
  Models := ModelListText(Line);
  if Models <> '' then
    if Assigned(FOnModels) then QueueModels(Models) else Post(Models);
  DispatchRpcLine(Line, FEvents);
end;
function TAgentRpcClient.ReaderStopped: Boolean;
begin
  Result := TThread.CurrentThread.CheckTerminated or (FStdOut = 0);
end;
procedure TAgentRpcClient.ReadLoop;
begin
  FEvents.Post := Post;
  FEvents.BecomeReady := NoteReady;
  FEvents.SendFrame := QueueFrame;
  FEvents.HostCall := QueueHost;
  FEvents.CancelCall := NoteCancel;
  ReadStdoutLines(FStdOut, ReaderStopped, ReaderLine);
  if FAlive and not FStopping then
  begin
    FLinkError := '파이프가 닫혔습니다';
    TThread.Queue(TThread(nil),
      procedure
      begin
        if FAlive and Assigned(FOnStatus) then
          FOnStatus();
      end);
  end;
end;
function CloseQuiet(var Handle: THandle): Boolean;
begin
  Result := Handle <> 0;
  if Result then
  begin
    CloseHandle(Handle);
    Handle := 0;
  end;
end;
function TAgentRpcClient.Start(const Executable, WorkDir: string): Boolean;
var
  Pipes: TRpcPipes;
begin
  Result := False;
  if FProcess <> 0 then
    Exit(True);
  ForceDirectories(AgentTempRoot);
  if not SpawnRpcProcess(BuildOmpCommandLine(Executable, WorkDir, OmpModel, OmpProvider),
    WorkDir, OmpStderrLog, Pipes) then
    Exit;
  FStdIn := Pipes.StdIn;
  FStdOut := Pipes.StdOut;
  FProcess := Pipes.Process;
  FThreadHandle := Pipes.Thread;
  FPid := Pipes.Pid;
  FCwd := WorkDir;
  FReady := False;
  FHostToolsSent := False;
  FLinkError := '';
  FStopping := False;
  FNextId := 0;
  TStringList(FCancel).Clear;
  FReader := TRpcReader.Create(True);
  FReader.Client := Self;
  FReader.FreeOnTerminate := False;
  FReader.Start;
  GGate.Acquire;
  try
    GActive := Self;
  finally
    GGate.Release;
  end;
  Result := True;
end;
procedure TAgentRpcClient.Stop;
begin
  FStopping := True;
  FReady := False;
  FHostToolsSent := False;
  CloseQuiet(FStdIn);
  if FReader <> nil then
  begin
    FReader.Terminate;
    if FStdOut <> 0 then
      CancelIoEx(FStdOut, nil);
    CloseQuiet(FStdOut);
    FReader.WaitFor;
    FreeAndNil(FReader);
  end
  else
    CloseQuiet(FStdOut);
  if FProcess <> 0 then
  begin
    if WaitForSingleObject(FProcess, 2000) = WAIT_TIMEOUT then
      TerminateProcess(FProcess, 1);
    CloseHandle(FProcess);
    FProcess := 0;
  end;
  if FThreadHandle <> 0 then
  begin
    CloseHandle(FThreadHandle);
    FThreadHandle := 0;
  end;
  FPid := 0;
  GGate.Acquire;
  try
    if GActive = Self then
      GActive := nil;
  finally
    GGate.Release;
  end;
  if FAlive and Assigned(FOnStatus) then
    FOnStatus();
end;
function TAgentRpcClient.SendPrompt(const Message: string): Boolean;
var
  Id, Frame: string;
begin
  Id := NewRequestId(FNextId);
  Result := TryBuildPromptFrame(FReady, FHostToolsSent, Id, Message, Frame);
  if not Result then
  begin
    Dec(FNextId);
    Exit;
  end;
  WriteFrame(Frame, 'prompt');
end;
procedure TAgentRpcClient.SendAbort;
begin
  if not FReady then
    Exit;
  WriteFrame(BuildAbortFrame(NewRequestId(FNextId)), 'abort');
end;
procedure TAgentRpcClient.SendRaw(const FrameType, Frame: string);
var
  Value: TJSONValue;
  Obj: TJSONObject;
begin
  if not FReady then Exit;
  Value := TJSONObject.ParseJSONValue(Frame);
  if not (Value is TJSONObject) then begin Value.Free; Exit; end;
  Obj := TJSONObject(Value);
  Obj.RemovePair('id');
  Obj.AddPair('id', NewRequestId(FNextId));
  WriteFrame(Obj.ToJSON, FrameType);
  Obj.Free;
end;
procedure TAgentRpcClient.SendHostResult(const CallId, Text: string; IsError: Boolean);
begin
  if not FReady or WasCancelled(CallId) then
    Exit;
  WriteFrame(BuildHostToolResultFrame(CallId, Text, IsError), 'host_tool_result');
end;
initialization
  GGate := TCriticalSection.Create;
finalization
  ShutdownActiveClient;
  GGate.Free;
end.
