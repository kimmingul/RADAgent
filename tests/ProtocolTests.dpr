program ProtocolTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Winapi.Windows,
  DelphiAgent.Options in '..\src\DelphiAgent.Options.pas',
  DelphiAgent.RpcProtocol in '..\src\DelphiAgent.RpcProtocol.pas',
  DelphiAgent.DirtyBuffers in '..\src\DelphiAgent.DirtyBuffers.pas',
  DelphiAgent.RpcClient in '..\src\DelphiAgent.RpcClient.pas';

var
  GFailures: Integer;

procedure Check(Condition: Boolean; const Name: string);
begin
  if Condition then
    WriteLn('ok ', Name)
  else
  begin
    WriteLn('FAIL ', Name);
    Inc(GFailures);
  end;
end;

function Parse(const Json: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Json);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise Exception.Create('not json');
  end;
  Result := TJSONObject(Value);
end;

procedure TestCommandLine;
var
  Command: string;
begin
  Command := BuildOmpCommandLine('omp', 'D:\work', '', '');
  Check(Command.Contains('--mode rpc'), 'command has rpc mode');
  Check(Command.Contains('--cwd'), 'command has cwd');
  Check(not Command.Contains('--model'), 'command omits empty model');
  Check(not Command.Contains('--provider'), 'command omits empty provider');
  Check(SameText(ExtractFileName(OmpExecutable), 'omp.exe') or (OmpExecutable = 'omp'),
    'default executable is omp');
  Check(OmpModel = '', 'default model empty');
  Check(OmpProvider = '', 'default provider empty');
end;

procedure TestPromptGate;
var
  Frame: string;
  Obj: TJSONObject;
  Paths: TArray<string>;
  NextId: Integer;
begin
  Check(not CanSendPrompt(False, True, 'hello'), 'prompt blocked before ready');
  Check(not CanSendPrompt(True, False, 'hello'), 'prompt blocked before host tools');
  Check(not TryBuildPromptFrame(False, False, 'req-1', 'hello', Frame), 'try build refuses');
  Check(Frame = '', 'refused frame is empty');
  SetLength(Paths, 1);
  Paths[0] := 'C:\Temp\DelphiAgent\snap-0-Unit1.pas';
  NextId := 0;
  Check(TryBuildPromptFrame(True, True, NewRequestId(NextId),
    MessageWithSnapshots('요약', Paths), Frame), 'try build allows');
  Obj := Parse(Frame);
  try
    Check(Obj.GetValue<string>('type') = 'prompt', 'frame type prompt');
    Check(Obj.GetValue<string>('message').Contains(Paths[0]), 'prompt contains snapshot path');
  finally
    Obj.Free;
  end;
  Obj := Parse(BuildAbortFrame('req-9'));
  try
    Check(Obj.GetValue<string>('type') = 'abort', 'abort type');
  finally
    Obj.Free;
  end;
  Check(not AllowOutbound(False, 'prompt'), 'outbound blocked before ready');
end;

procedure TestHostToolsAndCompileJson;
var
  Obj, Item: TJSONObject;
  Tools, Errors: TJSONArray;
  List: TArray<TAgentCompileError>;
  Names: string;
  Index: Integer;
begin
  Obj := Parse(BuildSetHostToolsFrame('req-3'));
  try
    Check(Obj.GetValue<string>('type') = 'set_host_tools', 'host tools type');
    Tools := Obj.GetValue('tools') as TJSONArray;
    Names := '';
    for Index := 0 to Tools.Count - 1 do
      Names := Names + ' ' + Tools.Items[Index].GetValue<string>('name');
    Check(Names.Contains('rad.compile'), 'tool compile');
    Check(Names.Contains('rad.open_buffer'), 'tool open');
    Check(Names.Contains('rad.insert_at_caret'), 'tool insert');
  finally
    Obj.Free;
  end;
  SetLength(List, 1);
  List[0].FileName := 'Unit1.pas';
  List[0].Line := 12;
  List[0].Col := 4;
  List[0].Msg := 'Undeclared';
  Obj := Parse(BuildCompileResultJson(False, 'Debug', 'Win64', List));
  try
    Check(Obj.GetValue<Boolean>('ok') = False, 'compile ok false');
    Check(Obj.GetValue<string>('config') = 'Debug', 'compile config');
    Check(Obj.GetValue<string>('platform') = 'Win64', 'compile platform');
    Errors := Obj.GetValue('errors') as TJSONArray;
    Item := Errors.Items[0] as TJSONObject;
    Check(Item.GetValue<Integer>('line') = 12, 'compile line');
    Check(Item.GetValue<Integer>('col') = 4, 'compile col');
    Check(Item.GetValue<string>('msg') = 'Undeclared', 'compile msg');
  finally
    Obj.Free;
  end;
end;

procedure TestSnapshotsAndFrames;
var
  Root, ReadBack: string;
  Files, Texts, Paths: TArray<string>;
  Client: TAgentRpcClient;
  Huge: string;
begin
  Root := AgentTempRoot + 'protocol-tests\';
  ForceDirectories(Root);
  SetLength(Files, 1);
  SetLength(Texts, 1);
  Files[0] := 'Unit1.pas';
  Texts[0] := 'unit Unit1;';
  Paths := WriteSnapshots(Root, Files, Texts);
  Check(Length(Paths) = 1, 'one snapshot');
  Check(Paths[0].StartsWith(Root), 'snapshot stays under temp');
  ReadBack := TFile.ReadAllText(Paths[0], TEncoding.UTF8);
  Check(ReadBack = Texts[0], 'snapshot text roundtrip');
  RememberSnapshots(Files, Texts);
  Check(not SnapshotConflicts('Unit1.pas', Texts[0]), 'same text is not a conflict');
  Check(SnapshotConflicts('Unit1.pas', Texts[0] + ' '), 'edited text conflicts');
  Check(IsReadyFrame('{"type":"ready","protocolVersion":1}'), 'ready frame');
  Check(AssistantDelta('{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"안녕"}}') = '안녕',
    'text delta');
  Huge := StringOfChar('x', MaxFrameBytes + 1);
  Check(not AcceptFrameLine(Huge), 'oversize line rejected');
  Client := TAgentRpcClient.Create;
  try
    Check(not Client.SendPrompt('hello'), 'client refuses prompt before ready');
    Check(not Client.Ready, 'client not ready');
  finally
    Client.Free;
  end;
end;

procedure TestLiveReady;
var
  Client: TAgentRpcClient;
  Dir: string;
  Deadline: UInt64;
begin
  Dir := AgentTempRoot + 'rpc-cwd';
  ForceDirectories(Dir);
  Client := TAgentRpcClient.Create;
  try
    Check(Client.Start(OmpExecutable, Dir), 'omp process starts');
    Deadline := GetTickCount64 + 25000;
    while (not Client.HostToolsSent) and (GetTickCount64 < Deadline) do
      CheckSynchronize(100);
    Check(Client.Ready, 'ready received');
    Check(Client.HostToolsSent, 'host tools sent after ready');
    Check(Client.SendPrompt('ping'), 'prompt allowed after ready');
    Client.SendAbort;
  finally
    Client.Free;
  end;
end;

begin
  GFailures := 0;
  try
    TestCommandLine;
    TestPromptGate;
    TestHostToolsAndCompileJson;
    TestSnapshotsAndFrames;
    TestLiveReady;
  except
    on E: Exception do
    begin
      WriteLn('FAIL exception ', E.ClassName, ' ', E.Message);
      Inc(GFailures);
    end;
  end;
  if GFailures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILURES ', GFailures);
  Halt(GFailures);
end.
