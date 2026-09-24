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
  DelphiAgent.HostToolDefs in '..\src\DelphiAgent.HostToolDefs.pas',
  DelphiAgent.ChatCommand in '..\src\DelphiAgent.ChatCommand.pas',
  DelphiAgent.RpcDispatch in '..\src\DelphiAgent.RpcDispatch.pas',
  DelphiAgent.RpcClient in '..\src\DelphiAgent.RpcClient.pas',
  DelphiAgent.RpcJson in '..\src\DelphiAgent.RpcJson.pas',
  DelphiAgent.RpcEvents in '..\src\DelphiAgent.RpcEvents.pas',
  DelphiAgent.RpcResponses in '..\src\DelphiAgent.RpcResponses.pas',
  DelphiAgent.LineDiff in '..\src\DelphiAgent.LineDiff.pas',
  DelphiAgent.RpcChunks in '..\src\DelphiAgent.RpcChunks.pas',
  DelphiAgent.OmpCli in '..\src\DelphiAgent.OmpCli.pas',
  DelphiAgent.OmpProbe in '..\src\DelphiAgent.OmpProbe.pas',
  DelphiAgent.GitRepo in '..\src\DelphiAgent.GitRepo.pas',
  TestCheck in 'TestCheck.pas',
  RpcEventsTests in 'RpcEventsTests.pas',
  LineDiffTests in 'LineDiffTests.pas',
  OmpCompatTests in 'OmpCompatTests.pas',
  GitRepoTests in 'GitRepoTests.pas';

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
  Command := BuildOmpCommandLine('omp', 'D:\work', [], '', '');
  Check(Command.Contains('--mode rpc'), 'command has rpc mode');
  Check(Command.Contains('--cwd'), 'command has cwd');
  Check(not Command.Contains('--config'), 'command omits empty overlay');
  Command := BuildOmpCommandLine('omp', 'D:\work', ['C:\t\host.yml', '', 'D:\work\.omp\delphiagent.yml'],
    'C:\t\guide.md', '--no-lsp');
  Check(Command.Contains('--config "C:\t\host.yml" --config "D:\work\.omp\delphiagent.yml"'),
    'command passes every overlay in order, skipping empty ones');
  Check(Command.Contains('--append-system-prompt "C:\t\guide.md"'), 'command passes the project guide');
  Check(Command.EndsWith(' --no-lsp'), 'command appends extra args');
  Check(SameText(ExtractFileName(OmpExecutable), 'omp.exe') or (OmpExecutable = 'omp'),
    'default executable is omp');
end;

procedure TestPromptGate;
var
  Frame: string;
  Obj: TJSONObject;
  NextId: Integer;
begin
  Check(not CanSendPrompt(False, True, 'hello'), 'prompt blocked before ready');
  Check(not CanSendPrompt(True, False, 'hello'), 'prompt blocked before host tools');
  Check(not TryBuildPromptFrame(False, False, 'req-1', 'hello', Frame), 'try build refuses');
  Check(Frame = '', 'refused frame is empty');
  NextId := 0;
  Check(TryBuildPromptFrame(True, True, NewRequestId(NextId), '요약', Frame), 'try build allows');
  Obj := Parse(Frame);
  try
    Check(Obj.GetValue<string>('type') = 'prompt', 'frame type prompt');
    Check(Obj.GetValue<string>('message') = '요약', 'prompt carries the message');
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

function ToolNames(const Frame: string; out SchemaOk: Boolean): string;
var
  Obj, Item, Params: TJSONObject;
  Tools, Required: TJSONArray;
  Index: Integer;
begin
  Obj := Parse(Frame);
  try
    Tools := Obj.GetValue('tools') as TJSONArray;
    Result := ' ';
    SchemaOk := Obj.GetValue<string>('type') = 'set_host_tools';
    for Index := 0 to Tools.Count - 1 do
    begin
      Item := Tools.Items[Index] as TJSONObject;
      Result := Result + Item.GetValue<string>('name') + ' ';
      Params := Item.GetValue('parameters') as TJSONObject;
      if (Item.GetValue<string>('description') = '') or (Params = nil) or
        (Params.GetValue<string>('type') <> 'object') then
        SchemaOk := False
      else
      begin
        Required := Params.GetValue('required') as TJSONArray;
        if (Required <> nil) and ((Params.GetValue('properties') as TJSONObject)
          .GetValue(Required.Items[0].Value) = nil) then
          SchemaOk := False;
      end;
    end;
  finally
    Obj.Free;
  end;
end;

procedure TestHostToolsAndCompileJson;
var
  Obj, Item: TJSONObject;
  Errors: TJSONArray;
  List: TArray<TAgentCompileError>;
  Names, Frame: string;
  SchemaOk: Boolean;
  Profile: TToolProfile;
begin
  Names := ToolNames(BuildSetHostToolsFrame('req-3'), SchemaOk);
  Check(SchemaOk, 'every tool schema is an object with a declared required field');
  Check(Names.Contains(' ' + ToolFormApply + ' ') and not Names.Contains('rad.apply_edit') and
    not Names.Contains('rad.read_buffer'), 'forms change through the designer; code through omp''s own edits');
  Profile := DefaultToolProfile;
  Profile.HasForms := False;
  Names := ToolNames(BuildSetHostToolsFrame('req-4', Profile), SchemaOk);
  Check(not Names.Contains('rad.form_') and Names.Contains(' ' + ToolNewModule + ' '),
    'project without forms offers no form tools but can add a form');
  Profile := DefaultToolProfile;
  Profile.Framework := 'FMX';
  Frame := BuildSetHostToolsFrame('req-5', Profile);
  Check(Frame.Contains('Position.X') and not Frame.Contains('alClient'), 'FMX form docs use FMX layout');
  Profile.Language := 'cpp';
  Frame := BuildSetHostToolsFrame('req-6', Profile);
  Check(Frame.Contains('C++Builder') and Frame.Contains('.cpp'), 'C++ project docs name C++Builder');
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

procedure TestFrames;
var
  Client: TAgentRpcClient;
  Huge: string;
begin
  Check(IsReadyFrame('{"type":"ready","protocolVersion":1}'), 'ready frame');
  Huge := StringOfChar('x', MaxReassembledFrameBytes + 1);
  Check(not AcceptFrameLine(Huge), 'a frame over the v2 reassembly limit is rejected');
  Client := TAgentRpcClient.Create;
  try
    Check(not Client.SendPrompt('hello'), 'client refuses prompt before ready');
    Check(not Client.Ready, 'client not ready');
  finally
    Client.Free;
  end;
end;

procedure CheckClass(const Text: string; Expected: TChatCommand;
  const Want1, Want2, Name: string);
var
  A1, A2: string;
begin
  Check((ClassifyChat(Text, A1, A2) = Expected) and (A1 = Want1) and (A2 = Want2), Name);
end;

procedure TestClassifyChat;
var
  Obj: TJSONObject;
begin
  CheckClass('안녕', ccPrompt, '', '', 'plain text is prompt');
  CheckClass('  a/b 경로  ', ccPrompt, '', '', 'slash inside text is prompt');
  CheckClass('/clear', ccNewSession, '', '', '/clear new session');
  CheckClass('/NEW', ccNewSession, '', '', '/new case-insensitive');
  CheckClass('/abort', ccAbort, '', '', '/abort');
  CheckClass('/model', ccListModels, '', '', '/model lists');
  CheckClass('/model anthropic claude-x', ccSetModel, 'anthropic', 'claude-x',
    '/model provider id');
  CheckClass('/model anthropic', ccSlashAsPrompt, '', '', '/model one arg falls back');
  CheckClass('/model a b c', ccSlashAsPrompt, '', '', '/model three args falls back');
  CheckClass('/fast', ccFast, '', '', '/fast asks');
  CheckClass('/fast OFF', ccFast, 'OFF', '', '/fast off');
  CheckClass('/fast maybe', ccSlashAsPrompt, '', '', '/fast bad arg falls back');
  CheckClass('/thinking high', ccThinking, 'high', '', '/thinking level');
  CheckClass('/effort', ccThinking, '', '', '/effort asks');
  CheckClass('/thinking very high', ccSlashAsPrompt, '', '', '/thinking two words falls back');
  CheckClass('/goal ship it', ccSlashAsPrompt, '', '', '/goal passes through');
  CheckClass('/fastmode', ccSlashAsPrompt, '', '', 'prefix is not /fast');
  Obj := Parse(BuildSetModelFrame('req-5', 'anthropic', 'claude-x'));
  try
    Check((Obj.GetValue<string>('type') = 'set_model') and
      (Obj.GetValue<string>('provider') = 'anthropic') and
      (Obj.GetValue<string>('modelId') = 'claude-x'), 'set_model fields');
  finally
    Obj.Free;
  end;
  Obj := Parse(BuildSetFastFrame('req-6', False));
  try
    Check((Obj.GetValue<string>('type') = 'set_fast_mode') and
      (Obj.GetValue('enabled') is TJSONFalse), 'set_fast_mode enabled false');
  finally
    Obj.Free;
  end;
  Obj := Parse(BuildSetThinkingFrame('req-7', 'high'));
  try
    Check((Obj.GetValue<string>('type') = 'set_thinking_level') and
      (Obj.GetValue<string>('level') = 'high'), 'set_thinking_level level');
  finally
    Obj.Free;
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
    Check(Client.Start(OmpExecutable, Dir, [], '', ''), 'omp process starts');
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
    TestFrames;
    TestClassifyChat;
    RunRpcEventsTests(Check);
    RunLineDiffTests(Check);
    RunOmpCompatTests(Check);
    RunGitRepoTests(Check);
    TestLiveReady;
    RunLiveOmpProbe(Check);
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
