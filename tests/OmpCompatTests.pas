unit OmpCompatTests;

{ What keeps DelphiAgent working across omp updates: protocol choice and v2 chunk reassembly on the
  real stdout reader, approval prompts matched by meaning, local slash commands ending the turn,
  and (live) the probe against the installed omp. }

interface

uses
  TestCheck;

procedure RunOmpCompatTests(const Check: TCheckProc);
{ Starts the installed omp; run last. }
procedure RunLiveOmpProbe(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding, Winapi.Windows,
  DelphiAgent.RpcProtocol, DelphiAgent.RpcDispatch, DelphiAgent.RpcEvents, DelphiAgent.ChatCommand,
  DelphiAgent.OmpProbe, DelphiAgent.Options;

type
  TLineSink = class
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Line: string);
  end;

constructor TLineSink.Create;
begin
  Lines := TStringList.Create;
end;

destructor TLineSink.Destroy;
begin
  Lines.Free;
  inherited;
end;

procedure TLineSink.Add(const Line: string);
begin
  Lines.Add(Line);
end;

{ Feeds Text through a real pipe into ReadStdoutLines, as omp's stdout would. }
function ReadThroughPipe(const Text: string): TStringList;
var
  Security: TSecurityAttributes;
  ReadEnd, WriteEnd: THandle;
  Bytes: TBytes;
  Sink: TLineSink;
  Writer: TThread;
begin
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  CreatePipe(ReadEnd, WriteEnd, @Security, 0);
  Bytes := TEncoding.UTF8.GetBytes(Text);
  Writer := TThread.CreateAnonymousThread(
    procedure
    var
      Written: DWORD;
      Offset: Integer;
    begin
      Offset := 0;
      while Offset < Length(Bytes) do
      begin
        WriteFile(WriteEnd, Bytes[Offset], Length(Bytes) - Offset, Written, nil);
        Inc(Offset, Written);
      end;
      CloseHandle(WriteEnd);
    end);
  Writer.FreeOnTerminate := False;
  Writer.Start;
  Sink := TLineSink.Create;
  try
    ReadStdoutLines(ReadEnd, nil, Sink.Add);
    Writer.WaitFor;
    Result := TStringList.Create;
    Result.Assign(Sink.Lines);
  finally
    Writer.Free;
    Sink.Free;
    CloseHandle(ReadEnd);
  end;
end;

function ChunkFrames(const Id, Json: string; PartBytes: Integer; SkipIndex: Integer = -1): string;
var
  Bytes, Part: TBytes;
  Count, Index, Start, Size: Integer;
  Obj: TJSONObject;
begin
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Count := (Length(Bytes) + PartBytes - 1) div PartBytes;
  Result := '';
  for Index := 0 to Count - 1 do
  begin
    if Index = SkipIndex then
      Continue;
    Start := Index * PartBytes;
    Size := Length(Bytes) - Start;
    if Size > PartBytes then
      Size := PartBytes;
    Part := Copy(Bytes, Start, Size);
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('type', 'rpc_chunk');
      Obj.AddPair('chunkId', Id);
      Obj.AddPair('index', TJSONNumber.Create(Index));
      Obj.AddPair('count', TJSONNumber.Create(Count));
      Obj.AddPair('byteLength', TJSONNumber.Create(Length(Bytes)));
      Obj.AddPair('data', TNetEncoding.Base64String.EncodeBytesToString(Part));
      Result := Result + Obj.ToJSON + #10;
    finally
      Obj.Free;
    end;
  end;
end;

procedure TestReader(const Check: TCheckProc);
var
  Big, Lines: string;
  Got: TStringList;
begin
  { A logical frame of 1.5 MB with non-ASCII text, split at byte boundaries inside characters. }
  Big := '{"type":"response","command":"get_messages_page","data":"' +
    StringOfChar('가', 500000) + '"}';
  Got := ReadThroughPipe('{"type":"ready"}' + #10 + ChunkFrames('rpc-1', Big, 700001) +
    '{"type":"agent_end"}' + #10);
  try
    Check((Got.Count = 3) and (Got[1] = Big), 'v2 chunk run arrives as the original frame, in order');
    Check(AcceptFrameLine(Got[1]), 'a rebuilt frame over 1 MiB is accepted');
  finally
    Got.Free;
  end;
  Got := ReadThroughPipe(ChunkFrames('rpc-2', Big, 700001, 1) + '{"type":"agent_end"}' + #10);
  try
    Check((Got.Count >= 2) and (Got[0] = '') and (Got[Got.Count - 1] = '{"type":"agent_end"}'),
      'an interrupted chunk run is dropped and reported, the next frame still arrives');
  finally
    Got.Free;
  end;
  Lines := '{"type":"x","t":"' + StringOfChar('x', MaxFrameBytes) + '"}' + #10 + '{"type":"ok"}' + #10;
  Got := ReadThroughPipe(Lines);
  try
    Check((Got.Count = 2) and (Got[0] = '') and (Got[1] = '{"type":"ok"}'),
      'a physical line over 1 MiB is dropped and reported');
  finally
    Got.Free;
  end;
end;

procedure TestProtocolChoice(const Check: TCheckProc);
var
  NextId: Integer;
begin
  Check(ChooseProtocol('{"type":"ready","supportedProtocolVersions":[1,2]}') = 2, 'v2 chosen when offered');
  Check(ChooseProtocol('{"type":"ready","supportedProtocolVersions":[1]}') = 1, 'v1 when only v1');
  Check(ChooseProtocol('{"type":"ready"}') = 1, 'old ready without a list means v1');
  Check(ChooseProtocol('{"type":"ready","supportedProtocolVersions":[3]}') = 0, 'unknown versions only: none');
  NextId := 4;
  Check(WithRequestId('get_state', '{"type":"get_state","id":"req"}', NextId).Contains('"id":"req-5"'),
    'page commands get a fresh request id');
  Check(WithRequestId('extension_ui_response', '{"type":"extension_ui_response","id":"ui7"}', NextId)
    .Contains('"id":"ui7"'), 'a UI reply keeps the id it answers');
  Check(CompareOmpVersions('18.10.0', '18.9.3') > 0, 'versions compare by number');
  Check(CompareOmpVersions('18.2.11', '18.2.11') = 0, 'same version');
end;

function Ui(const Title: string; const Options: array of string): TExtensionUi;
var
  Index: Integer;
begin
  Result := Default(TExtensionUi);
  Result.Method := 'select';
  Result.Title := Title;
  SetLength(Result.Options, Length(Options));
  for Index := 0 to High(Options) do
    Result.Options[Index] := Options[Index];
end;

procedure TestApprovalMatching(const Check: TCheckProc);
begin
  Check(ApprovalTargetsRad(Ui('Allow tool: write'#10'Path: xd://rad.apply_edits', ['Approve', 'Deny'])),
    'write to an xd://rad.* device is a rad approval');
  Check(ApprovalTargetsRad(Ui('Allow tool: rad.compile', ['Allow', 'Reject'])),
    'a rad.* tool called by name is a rad approval');
  Check(not ApprovalTargetsRad(Ui('Allow tool: write'#10'Path: C:\p\Unit1.pas', ['Approve', 'Deny'])),
    'a disk write is not a rad approval');
  Check(ApproveOption(Ui('Allow tool: bash', ['Deny', 'Allow once'])) = 'Allow once',
    'approve option found by wording, not position');
  Check(DenyOption(Ui('Allow tool: bash', ['Approve', 'Reject'])) = 'Reject', 'deny option found by wording');
  Check(ApproveOption(Ui('Allow tool: bash', ['Later', 'Never'])) = '', 'no approve-like option: none');
end;

procedure TestLocalPrompts(const Check: TCheckProc);
var
  Event: TAgentEvent;
begin
  Event := ParseAgentEvent('{"id":"p1","type":"response","command":"prompt","success":true,' +
    '"data":{"agentInvoked":false}}');
  Check(Event.Kind = aekPromptLocal, 'prompt answered locally ends the turn');
  Check(ParseAgentEvent('{"type":"prompt_result","id":"p1","agentInvoked":false}').Kind = aekPromptLocal,
    'late prompt_result ends the turn');
  Check(ParseAgentEvent('{"id":"p1","type":"response","command":"prompt","success":true,' +
    '"data":{"agentInvoked":true}}').Kind = aekNone, 'a prompt that starts a turn waits for agent_end');
  Event := ParseAgentEvent('{"type":"command_output","text":"Context \u001b[38;2;1;2;3m50%\u001b[39m used"}');
  Check((Event.Kind = aekCommandOutput) and (Event.Text = 'Context 50% used'),
    'command output arrives without terminal colours');
end;

procedure RunOmpCompatTests(const Check: TCheckProc);
begin
  TestReader(Check);
  TestProtocolChoice(Check);
  TestApprovalMatching(Check);
  TestLocalPrompts(Check);
end;

procedure RunLiveOmpProbe(const Check: TCheckProc);
var
  Dir: string;
  Item: TOmpCheck;
begin
  Dir := AgentTempRoot + 'rpc-cwd';
  ForceDirectories(Dir);
  for Item in ProbeOmp(OmpExecutable, Dir) do
    Check(Item.Ok, 'omp probe: ' + Item.Name + ' - ' + Item.Detail);
end;

end.
