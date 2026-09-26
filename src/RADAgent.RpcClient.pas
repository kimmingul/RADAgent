unit RADAgent.RpcClient;
{ omp --mode rpc child. The read thread never calls ToolsAPI. }
interface
uses
  System.Classes, System.SysUtils, RADAgent.RpcDispatch, RADAgent.RpcEvents,
  RADAgent.HostToolDefs;
type
  TRpcLogEvent = reference to procedure(const Text: string);
  TRpcStatusEvent = procedure of object;
  TRpcHostToolEvent = reference to procedure(const CallId, ToolName, ArgumentsJson: string);
  TRpcAgentEvent = procedure(const Event: TAgentEvent) of object;
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
    FOnResponse: TRpcLogEvent;
    FOnAgentEvent: TRpcAgentEvent;
    FOnUi: TRpcLogEvent;
    FEvents: TRpcDispatch;
    FLinkError: string;
    FStopping, FExited, FExitedConnected: Boolean;
    FProtocol: Integer;
    { Bumped by Start and Stop; a reader's queued work (FReaderGen) dies with its child. }
    FGeneration, FReaderGen: Integer;
    FToolProfile: TToolProfile;
    function WriteFrame(const Frame, FrameType: string): Boolean;
    procedure RunLive(const Work: TProc);
    procedure QueueFrame(const Frame, FrameType: string);
    procedure QueueHost(const CallId, ToolName, Args: string);
    procedure QueueUi(const Line: string);
    procedure QueueResponse(const Line: string);
    procedure QueueEvent(const Event: TAgentEvent);
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
    function Start(const Executable, WorkDir: string; const Configs: array of string; const AppendPrompt, ExtraArgs: string): Boolean;
    procedure Stop;
    function SendPrompt(const Message: string; const ImagesJson: string = ''): Boolean;
    procedure SendAbort;
    { False when the frame did not reach omp (not ready, over MaxFrameBytes, broken pipe). }
    function SendRaw(const FrameType, Frame: string): Boolean;
    procedure SendHostResult(const CallId, Text: string; IsError: Boolean; const ImagePng: string = '');
    procedure ResendHostTools(const Profile: TToolProfile);
    function WasCancelled(const CallId: string): Boolean;
    property Ready: Boolean read FReady;
    property HostToolsSent: Boolean read FHostToolsSent;
    property Pid: Cardinal read FPid;
    property Cwd: string read FCwd;
    property OnLog: TRpcLogEvent read FOnLog write FOnLog;
    property OnStatus: TRpcStatusEvent read FOnStatus write FOnStatus;
    property OnHostTool: TRpcHostToolEvent read FOnHostTool write FOnHostTool;
    { Response frames and available_commands_update, raw JSON line, on the main thread. }
    property OnResponse: TRpcLogEvent read FOnResponse write FOnResponse;
    property OnAgentEvent: TRpcAgentEvent read FOnAgentEvent write FOnAgentEvent;
    property OnUi: TRpcLogEvent read FOnUi write FOnUi;
    property LinkError: string read FLinkError;
    { The child's stdout ended without Stop (until Stop/Start); it had been connected. }
    property Exited: Boolean read FExited;
    property ExitedConnected: Boolean read FExitedConnected;
    { Changes when the child is stopped or started: stale replies must not reach a new child. }
    property Generation: Integer read FGeneration;
    property ToolProfile: TToolProfile read FToolProfile write FToolProfile;
  end;
procedure ShutdownActiveClient;
implementation
uses
  System.SyncObjs, Winapi.Windows,
  RADAgent.Options, RADAgent.RpcProtocol, RADAgent.ChatCommand, RADAgent.Lang;
var
  GActive: TAgentRpcClient;
  GGate: TCriticalSection;
{ Only: replace GActive only while it is Only (nil: always). }
procedure SetActive(Client, Only: TAgentRpcClient);
begin
  GGate.Acquire;
  try
    if (Only = nil) or (GActive = Only) then GActive := Client;
  finally
    GGate.Release;
  end;
end;
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
  FToolProfile := DefaultToolProfile;
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
procedure TAgentRpcClient.RunLive(const Work: TProc);
var
  Gen: Integer;
begin
  Gen := FReaderGen;
  TThread.Queue(TThread(nil), procedure begin if FAlive and (Gen = FGeneration) then Work(); end);
end;
procedure TAgentRpcClient.Post(const Text: string);
begin
  if FAlive and Assigned(FOnLog) and (Text <> '') then
    RunLive(procedure begin if Assigned(FOnLog) then FOnLog(Text); end);
end;
function TAgentRpcClient.WriteFrame(const Frame, FrameType: string): Boolean;
var
  Bytes: TBytes;
  Offset, Written: DWORD;
begin
  Result := False;
  if not AllowOutbound(FReady, FrameType) then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(Frame + #10);
  if Length(Bytes) > MaxFrameBytes then
  begin
    AppendRpcLog(Format('> [not sent: %s frame of %d bytes]', [FrameType, Length(Bytes)]));
    Exit;
  end;
  AppendRpcLog('> ' + Frame);
  TCriticalSection(FLock).Acquire;
  try
    Offset := 0;
    while (FStdIn <> 0) and (Offset < DWORD(Length(Bytes))) do
    begin
      if not WriteFile(FStdIn, Bytes[Offset], DWORD(Length(Bytes)) - Offset, Written, nil) or (Written = 0) then
        Exit;
      Inc(Offset, Written);
    end;
    Result := Offset = DWORD(Length(Bytes));
  finally
    TCriticalSection(FLock).Release;
  end;
end;
procedure TAgentRpcClient.QueueFrame(const Frame, FrameType: string);
begin
  RunLive(procedure begin WriteFrame(Frame, FrameType); end);
end;
procedure TAgentRpcClient.QueueHost(const CallId, ToolName, Args: string);
begin
  RunLive(procedure begin if Assigned(FOnHostTool) then FOnHostTool(CallId, ToolName, Args); end);
end;
procedure TAgentRpcClient.QueueUi(const Line: string);
begin
  RunLive(procedure begin if Assigned(FOnUi) then FOnUi(Line); end);
end;
procedure TAgentRpcClient.QueueResponse(const Line: string);
begin
  RunLive(procedure begin if Assigned(FOnResponse) then FOnResponse(Line); end);
end;
procedure TAgentRpcClient.QueueEvent(const Event: TAgentEvent);
begin
  RunLive(procedure begin if Assigned(FOnAgentEvent) then FOnAgentEvent(Event); end);
end;
procedure TAgentRpcClient.NoteCancel(const CallId: string);
begin
  if CallId = '' then
    Exit;
  TCriticalSection(FLock).Acquire;
  try
    if TStringList(FCancel).IndexOf(CallId) < 0 then
      TStringList(FCancel).Add(CallId);
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
  RunLive(procedure begin SendHostTools; end);
end;
procedure TAgentRpcClient.SendHostTools;
begin
  if FHostToolsSent or not FReady then Exit;
  if FProtocol = 0 then begin FLinkError := Tr('rpcclient.unsupportedProtocol'); Exit; end;
  { v2 carries frames over 1 MiB losslessly as rpc_chunk runs (ReadStdoutLines rebuilds them). }
  if FProtocol = 2 then WriteFrame(BuildNegotiateFrame(NewRequestId(FNextId), 2), 'negotiate_protocol');
  WriteFrame(BuildSetHostToolsFrame(NewRequestId(FNextId), FToolProfile), 'set_host_tools');
  WriteFrame(BuildIdTypeFrame(NewRequestId(FNextId), 'get_state'), 'get_state');
  WriteFrame(BuildIdTypeFrame(NewRequestId(FNextId), 'get_available_commands'), 'get_available_commands');
  FHostToolsSent := True;
  if Assigned(FOnStatus) then FOnStatus();
end;
procedure TAgentRpcClient.ReaderLine(const Line: string);
var
  Kind: string;
  Event: TAgentEvent;
begin
  if Line = '' then begin Post(Tr('rpcclient.droppedFrame')); Exit; end;
  AppendRpcLog('< ' + Line);
  Kind := FrameTypeOf(Line);
  if Kind = 'ready' then FProtocol := ChooseProtocol(Line);
  if Assigned(FOnUi) and (Kind = 'extension_ui_request') then begin QueueUi(Line); Exit; end;
  if (Kind = 'response') or (Kind = 'available_commands_update') then
    QueueResponse(Line);
  Event := ParseAgentEvent(Line);
  if Event.Kind <> aekNone then
    QueueEvent(Event);
  DispatchRpcLine(Line, FEvents);
end;
function TAgentRpcClient.ReaderStopped: Boolean;
begin
  Result := TThread.CurrentThread.CheckTerminated or (FStdOut = 0);
end;
procedure TAgentRpcClient.ReadLoop;
var
  Reason: string;
begin
  FEvents.Post := Post;
  FEvents.BecomeReady := NoteReady;
  FEvents.SendFrame := QueueFrame;
  FEvents.HostCall := QueueHost;
  FEvents.CancelCall := NoteCancel;
  ReadStdoutLines(FStdOut, ReaderStopped, ReaderLine);
  if FAlive and not FStopping then
  begin
    Reason := ChildExitReason(OmpStderrLog);
    { The child is gone: nothing may be sent or counted as connected any more. }
    RunLive(procedure
      begin
        FExitedConnected := FHostToolsSent;
        FExited := True;
        FReady := False;
        FHostToolsSent := False;
        FLinkError := Reason;
        if Assigned(FOnStatus) then FOnStatus();
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
function TAgentRpcClient.Start(const Executable, WorkDir: string; const Configs: array of string;
  const AppendPrompt, ExtraArgs: string): Boolean;
var
  Pipes: TRpcPipes;
begin
  Result := False;
  if FProcess <> 0 then
    Exit(True);
  ForceDirectories(AgentTempRoot);
  if not SpawnRpcProcess(BuildOmpCommandLine(Executable, WorkDir, Configs, AppendPrompt, ExtraArgs),
    WorkDir, OmpStderrLog, Pipes) then
    Exit;
  FStdIn := Pipes.StdIn;
  FStdOut := Pipes.StdOut;
  FProcess := Pipes.Process;
  FThreadHandle := Pipes.Thread;
  FPid := Pipes.Pid;
  FCwd := WorkDir;
  FReady := False; FHostToolsSent := False; FExited := False; FExitedConnected := False;
  Inc(FGeneration);
  FReaderGen := FGeneration;
  FLinkError := '';
  FStopping := False;
  FNextId := 0;
  FProtocol := 1;
  TStringList(FCancel).Clear;
  FReader := TRpcReader.Create(True);
  FReader.Client := Self;
  FReader.FreeOnTerminate := False;
  FReader.Start;
  SetActive(Self, nil);
  Result := True;
end;
procedure TAgentRpcClient.Stop;
begin
  Inc(FGeneration);
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
  if (FProcess <> 0) and (WaitForSingleObject(FProcess, 2000) = WAIT_TIMEOUT) then
    TerminateProcess(FProcess, 1);
  CloseQuiet(FProcess);
  CloseQuiet(FThreadHandle);
  FPid := 0; FExited := False;
  SetActive(nil, Self);
  if FAlive and Assigned(FOnStatus) then FOnStatus();
end;
function TAgentRpcClient.SendPrompt(const Message, ImagesJson: string): Boolean;
var
  Id, Frame: string;
begin
  Id := NewRequestId(FNextId);
  Result := TryBuildPromptFrame(FReady, FHostToolsSent, Id, Message, Frame, ImagesJson);
  if not Result then
    Dec(FNextId)
  else
    Result := WriteFrame(Frame, 'prompt');
end;
procedure TAgentRpcClient.SendAbort;
begin
  if FReady then
    WriteFrame(BuildAbortFrame(NewRequestId(FNextId)), 'abort');
end;
function TAgentRpcClient.SendRaw(const FrameType, Frame: string): Boolean;
var
  Line: string;
begin
  Line := '';
  if FReady then
    Line := WithRequestId(FrameType, Frame, FNextId);
  Result := (Line <> '') and WriteFrame(Line, FrameType);
end;
procedure TAgentRpcClient.SendHostResult(const CallId, Text: string; IsError: Boolean; const ImagePng: string);
begin
  if not FReady or WasCancelled(CallId) then
    Exit;
  { omp must get an answer for every call, so an oversized result becomes an error it can act on. }
  if not WriteFrame(BuildHostToolResultFrame(CallId, Text, IsError, ImagePng), 'host_tool_result') then
    WriteFrame(BuildHostToolResultFrame(CallId, 'The result was too large to send (over 1 MiB). ' +
      'Ask for less, e.g. a narrower range or fewer items.', True), 'host_tool_result');
end;
{ The rad.* tools again for a changed project, e.g. after its first form. }
procedure TAgentRpcClient.ResendHostTools(const Profile: TToolProfile);
begin
  FToolProfile := Profile;
  if FHostToolsSent then WriteFrame(BuildSetHostToolsFrame(NewRequestId(FNextId), FToolProfile), 'set_host_tools');
end;
initialization
  GGate := TCriticalSection.Create;
finalization
  ShutdownActiveClient;
  GGate.Free;
end.
