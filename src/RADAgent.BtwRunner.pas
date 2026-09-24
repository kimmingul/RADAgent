unit RADAgent.BtwRunner;

{ One omp --mode rpc child per side question (/btw): no tools, forked from the conversation or
  resuming the topic's own session, one prompt, then stdin closes and the child exits. Polled
  from the main thread; reads never block. Stopping sends the abort frame, as for the main
  child. No ToolsAPI. }

interface

uses
  System.SysUtils, RADAgent.RpcDispatch, RADAgent.RpcChunks;

type
  TBtwRun = class
  private
    FPipes: TRpcPipes;
    FPending, FBuffer: TBytes;
    FQuestion, FText, FError, FSessionFile, FStderr: string;
    FReady, FEnded, FAborted, FFinished, FChanged: Boolean;
    FNextId: Integer;
    FStartTick, FAbortTick: UInt64;
    FChunks: TRpcChunkAssembler;
    procedure WriteFrame(const Frame: string);
    procedure CloseInput;
    procedure Drain;
    procedure HandleLine(const Line: string);
    procedure Finish;
  public
    destructor Destroy; override;
    function Start(const CommandLine, WorkDir, StderrPath, Question: string): Boolean;
    { Reads what the child wrote; True when the answer or the state changed. }
    function Poll: Boolean;
    procedure Abort;
    { Package unload: ends the child now. }
    procedure Kill;
    property Text: string read FText;
    property Error: string read FError;
    property SessionFile: string read FSessionFile;
    property Finished: Boolean read FFinished;
    property Aborted: Boolean read FAborted;
  end;

implementation

uses
  System.Classes, System.JSON, Winapi.Windows, RADAgent.RpcProtocol, RADAgent.RpcJson,
  RADAgent.ChatCommand, RADAgent.Options, RADAgent.Lang;

const
  ReadyTimeoutMs = 90000;
  AbortGraceMs = 10000;

function CloseQuiet(var Handle: THandle): Boolean;
begin
  Result := Handle <> 0;
  if Result then
  begin
    CloseHandle(Handle);
    Handle := 0;
  end;
end;

destructor TBtwRun.Destroy;
begin
  Kill;
  FChunks.Free;
  inherited Destroy;
end;

function TBtwRun.Start(const CommandLine, WorkDir, StderrPath, Question: string): Boolean;
begin
  FQuestion := Question;
  FStderr := StderrPath;
  FStartTick := GetTickCount64;
  SetLength(FBuffer, 65536);
  FChunks := TRpcChunkAssembler.Create;
  AppendRpcLog('btw$ ' + CommandLine);
  Result := SpawnRpcProcess(CommandLine, WorkDir, StderrPath, FPipes);
  if not Result then
  begin
    FError := Tr('btwrunner.startFailed');
    FFinished := True;
  end;
end;

procedure TBtwRun.WriteFrame(const Frame: string);
var
  Bytes: TBytes;
  Offset, Written: DWORD;
begin
  if FPipes.StdIn = 0 then
    Exit;
  AppendRpcLog('btw> ' + Frame);
  Bytes := TEncoding.UTF8.GetBytes(Frame + #10);
  Offset := 0;
  while Offset < DWORD(Length(Bytes)) do
  begin
    if not WriteFile(FPipes.StdIn, Bytes[Offset], DWORD(Length(Bytes)) - Offset, Written, nil) or
      (Written = 0) then
      Exit;
    Inc(Offset, Written);
  end;
end;

procedure TBtwRun.CloseInput;
begin
  CloseQuiet(FPipes.StdIn);
end;

procedure TBtwRun.HandleLine(const Line: string);
var
  Obj, Data, Msg, Stream: TJSONObject;
  Kind, Reply: string;
begin
  Obj := JsonObject(Line);
  if Obj = nil then
    Exit;
  try
    Kind := JsonStr(Obj, 'type');
    if Kind <> 'message_update' then
      AppendRpcLog('btw< ' + Copy(Line, 1, 2000));
    if Kind = 'ready' then
    begin
      FReady := True;
      case ChooseProtocol(Line) of
        0:
          begin
            FError := Tr('btwrunner.unsupportedProtocol');
            CloseInput;
            Exit;
          end;
        2: WriteFrame(BuildNegotiateFrame(NewRequestId(FNextId), 2));
      end;
      WriteFrame(BuildIdTypeFrame(NewRequestId(FNextId), 'get_state'));
      WriteFrame(BuildPromptFrame(NewRequestId(FNextId), FQuestion));
    end
    else if Kind = 'response' then
    begin
      Data := JsonChild(Obj, 'data');
      if IsJsonFalse(Obj.GetValue('success')) then
      begin
        FError := JsonStr(Obj, 'error');
        if JsonStr(Obj, 'command') = 'prompt' then
          CloseInput;
      end
      else if (JsonStr(Obj, 'command') = 'get_state') and (Data <> nil) then
        FSessionFile := JsonStr(Data, 'sessionFile');
    end
    else if Kind = 'extension_ui_request' then
    begin
      Reply := BuildExtensionUiResponse(Line);
      if Reply <> '' then
        WriteFrame(Reply);
    end
    else if Kind = 'message_update' then
    begin
      Stream := JsonChild(Obj, 'assistantMessageEvent');
      if (Stream <> nil) and (JsonStr(Stream, 'type') = 'text_delta') then
      begin
        FText := FText + JsonStr(Stream, 'delta');
        FChanged := True;
      end;
    end
    else if Kind = 'message_end' then
    begin
      Msg := JsonChild(Obj, 'message');
      if (Msg <> nil) and (JsonStr(Msg, 'role') = 'assistant') then
      begin
        if ContentText(Msg.GetValue('content')) <> '' then
          FText := ContentText(Msg.GetValue('content'));
        if JsonStr(Msg, 'stopReason') = 'error' then
          FError := JsonStr(Msg, 'errorMessage');
        FChanged := True;
      end;
    end
    else if (Kind = 'agent_end') and not IsJsonFalse(Obj.GetValue('isTerminal')) then
    begin
      FEnded := True;
      CloseInput;
    end;
  finally
    Obj.Free;
  end;
end;

procedure TBtwRun.Drain;
var
  Available, Count: DWORD;
  Index, Start, Last: Integer;
begin
  while (FPipes.StdOut <> 0) and PeekNamedPipe(FPipes.StdOut, nil, 0, nil, @Available, nil) and
    (Available > 0) do
  begin
    if Available > DWORD(Length(FBuffer)) then
      Available := Length(FBuffer);
    if not ReadFile(FPipes.StdOut, FBuffer[0], Available, Count, nil) or (Count = 0) then
      Break;
    Start := Length(FPending);
    SetLength(FPending, Start + Integer(Count));
    Move(FBuffer[0], FPending[Start], Count);
    Start := 0;
    for Index := 0 to High(FPending) do
      if FPending[Index] = 10 then
      begin
        Last := Index;
        if (Last > Start) and (FPending[Last - 1] = 13) then
          Dec(Last);
        if Last > Start then
          HandleLine(FChunks.Feed(TEncoding.UTF8.GetString(FPending, Start, Last - Start)));
        Start := Index + 1;
      end;
    FPending := Copy(FPending, Start, MaxInt);
  end;
end;

procedure TBtwRun.Finish;
begin
  FFinished := True;
  CloseInput;
  CloseQuiet(FPipes.StdOut);
  CloseQuiet(FPipes.Thread);
  CloseQuiet(FPipes.Process);
  if (FText <> '') and not FAborted then
    FError := ''
  else if (FError = '') and not FAborted and FileExists(FStderr) then
    { The child died before answering; its last stderr line says why. }
    FError := ChildExitReason(FStderr);
  if (FError = '') and (FText = '') and not FAborted then
    FError := Tr('btwrunner.endedWithoutAnswer');
  if (FError = '') and FileExists(FStderr) then
    System.SysUtils.DeleteFile(FStderr);
end;

function TBtwRun.Poll: Boolean;
var
  Exited: Boolean;
begin
  if FFinished then
    Exit(False);
  FChanged := False;
  Exited := WaitForSingleObject(FPipes.Process, 0) = WAIT_OBJECT_0;
  Drain;
  if not FReady and not Exited and (GetTickCount64 - FStartTick > ReadyTimeoutMs) then
  begin
    FError := Tr('btwrunner.notReady');
    Kill;
    Exit(True);
  end;
  if FAborted and not Exited and (GetTickCount64 - FAbortTick > AbortGraceMs) then
  begin
    Kill;
    Exit(True);
  end;
  if Exited then
  begin
    Finish;
    Exit(True);
  end;
  Result := FChanged;
end;

procedure TBtwRun.Abort;
begin
  if FFinished or FAborted then
    Exit;
  FAborted := True;
  FAbortTick := GetTickCount64;
  if FReady and not FEnded then
    WriteFrame(BuildAbortFrame(NewRequestId(FNextId)));
  { agent_end follows the abort and closes stdin; before ready there is nothing to abort. }
  if not FReady then
    CloseInput;
end;

procedure TBtwRun.Kill;
begin
  if FFinished then
    Exit;
  if FReady and not FEnded then
    WriteFrame(BuildAbortFrame(NewRequestId(FNextId)));
  CloseInput;
  if (FPipes.Process <> 0) and (WaitForSingleObject(FPipes.Process, 1500) = WAIT_TIMEOUT) then
    TerminateProcess(FPipes.Process, 1);
  Finish;
end;

end.
