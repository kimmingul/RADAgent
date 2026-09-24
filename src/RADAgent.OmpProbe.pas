unit RADAgent.OmpProbe;

{ Checks that the installed omp still offers what RADAgent relies on: the command-line flags it
  passes, the RPC handshake (protocol, rad.* host tools, their xd:// devices) and the response
  fields it reads. Starts no model turn and saves no session. Blocking for a few seconds: run it
  off the main thread. Used after an omp update, from the settings dialog and by the tests.
  No ToolsAPI, no VCL. }

interface

uses
  System.SysUtils;

const
  { The omp release RADAgent was built and verified against. }
  TestedOmpVersion = '18.2.11';

type
  TOmpCheck = record
    Name, Detail: string;
    Ok: Boolean;
  end;

{ "18.2.11" from "omp --version" ("omp/18.2.11"), or '' when omp does not answer. }
function OmpVersionText(const Executable: string): string;
{ Negative, zero or positive like CompareStr, by numeric parts ("18.10.0" > "18.9.3"). }
function CompareOmpVersions(const A, B: string): Integer;
{ Every check, in order. Stop (optional) ends the probe early when it returns True. }
function ProbeOmp(const Executable, WorkDir: string; const Stop: TFunc<Boolean> = nil): TArray<TOmpCheck>;
function AllPassed(const Checks: TArray<TOmpCheck>): Boolean;
{ One line per check for a dialog or a log. }
function ProbeReport(const Checks: TArray<TOmpCheck>): string;

implementation

uses
  System.Classes, System.JSON, System.IOUtils, System.StrUtils, Winapi.Windows, RADAgent.OmpCli,
  RADAgent.Options, RADAgent.RpcDispatch, RADAgent.RpcProtocol, RADAgent.RpcChunks,
  RADAgent.RpcJson, RADAgent.RpcResponses, RADAgent.ChatCommand, RADAgent.HostToolDefs,
  RADAgent.Lang;

const
  { Flags RADAgent passes (main child, plan mode, /btw). omp --help does not list --fork. }
  UsedFlags: array[0..13] of string = ('--mode', '--cwd', '--config', '--append-system-prompt',
    '--approval-mode', '--no-tools', '--no-skills', '--no-extensions', '--no-lsp', '--no-title',
    '--session-dir', '--resume', '--model', '--thinking');
  RpcTimeoutMs = 30000;

function OmpVersionText(const Executable: string): string;
var
  Text: string;
begin
  Text := Trim(RunOmp(Executable, '--version', GetCurrentDir, 10000));
  if Text.Contains('/') then
    Text := Copy(Text, LastDelimiter('/', Text) + 1, MaxInt);
  Result := '';
  if (Text <> '') and CharInSet(Text[1], ['0'..'9']) then
    Result := Text;
end;

function CompareOmpVersions(const A, B: string): Integer;
var
  PartsA, PartsB: TArray<string>;
  Index, X, Y: Integer;
begin
  PartsA := A.Split(['.', '-', '+']);
  PartsB := B.Split(['.', '-', '+']);
  for Index := 0 to 2 do
  begin
    X := 0;
    Y := 0;
    if Index < Length(PartsA) then
      X := StrToIntDef(PartsA[Index], 0);
    if Index < Length(PartsB) then
      Y := StrToIntDef(PartsB[Index], 0);
    if X <> Y then
      Exit(X - Y);
  end;
  Result := 0;
end;

function Check(const Name: string; Ok: Boolean; const Detail: string): TOmpCheck;
begin
  Result.Name := Name;
  Result.Ok := Ok;
  Result.Detail := Detail;
end;

function AllPassed(const Checks: TArray<TOmpCheck>): Boolean;
var
  Item: TOmpCheck;
begin
  for Item in Checks do
    if not Item.Ok then
      Exit(False);
  Result := Length(Checks) > 0;
end;

function ProbeReport(const Checks: TArray<TOmpCheck>): string;
var
  Item: TOmpCheck;
  Mark: string;
begin
  Result := '';
  for Item in Checks do
  begin
    if Item.Ok then
      Mark := Tr('ompprobe.pass')
    else
      Mark := Tr('ompprobe.fail');
    Result := Result + Mark + '  ' + Item.Name + ': ' + Item.Detail + sLineBreak;
  end;
end;

type
  { What one short RPC session with omp showed. }
  TRpcFindings = record
    Ready, Negotiated: string;
    Protocol: Integer;
    Responses: TStringList;
    Mounted: Boolean;
    ExitReason: string;
  end;

procedure WriteLine(const Pipes: TRpcPipes; const Frame: string);
var
  Bytes: TBytes;
  Written: DWORD;
begin
  Bytes := TEncoding.UTF8.GetBytes(Frame + #10);
  WriteFile(Pipes.StdIn, Bytes[0], Length(Bytes), Written, nil);
end;

procedure Handle(const Pipes: TRpcPipes; const Line: string; var Found: TRpcFindings; var NextId: Integer);
var
  Kind: string;
  Obj: TJSONObject;
begin
  Kind := FrameTypeOf(Line);
  if Kind = 'ready' then
  begin
    Found.Ready := Line;
    Found.Protocol := ChooseProtocol(Line);
    if Found.Protocol = 2 then
      WriteLine(Pipes, BuildNegotiateFrame(NewRequestId(NextId), 2));
    WriteLine(Pipes, BuildSetHostToolsFrame(NewRequestId(NextId)));
    WriteLine(Pipes, BuildIdTypeFrame(NewRequestId(NextId), 'get_state'));
    WriteLine(Pipes, BuildIdTypeFrame(NewRequestId(NextId), 'get_available_commands'));
    WriteLine(Pipes, BuildIdTypeFrame(NewRequestId(NextId), 'get_available_thinking_levels'));
  end
  else if Kind = 'response' then
  begin
    Obj := JsonObject(Line);
    try
      if JsonStr(Obj, 'command') = 'negotiate_protocol' then
        Found.Negotiated := Line
      else
        Found.Responses.Values[JsonStr(Obj, 'command')] := Line;
    finally
      Obj.Free;
    end;
  end
  else if (Kind = 'notice') and Line.Contains('xd://') and Line.Contains('rad.compile') then
    Found.Mounted := True;
end;

{ Starts omp like RADAgent does (same --config), answers nothing, reads until the replies it
  needs are in. }
function RunRpc(const Executable, WorkDir: string; const Stop: TFunc<Boolean>): TRpcFindings;
var
  Pipes: TRpcPipes;
  Config, Stderr: string;
  Chunks: TRpcChunkAssembler;
  Pending, Buffer: TBytes;
  Available, Count: DWORD;
  Start, Index, NextId: Integer;
  Deadline, Quiet: UInt64;
begin
  Result := Default(TRpcFindings);
  Result.Responses := TStringList.Create;
  Config := AgentTempRoot + 'omp-probe.yml';
  Stderr := AgentTempRoot + 'omp-probe.stderr.log';
  ForceDirectories(AgentTempRoot);
  TFile.WriteAllBytes(Config, TEncoding.UTF8.GetBytes(OmpHostConfig));
  if not SpawnRpcProcess(BuildOmpCommandLine(Executable, WorkDir, [Config], '',
    '--no-session --no-title --no-lsp'), WorkDir, Stderr, Pipes) then
  begin
    Result.ExitReason := Tr('ompprobe.startFailed');
    Exit;
  end;
  Chunks := TRpcChunkAssembler.Create;
  SetLength(Buffer, 65536);
  NextId := 0;
  Deadline := GetTickCount64 + RpcTimeoutMs;
  Quiet := 0;
  try
    while GetTickCount64 < Deadline do
    begin
      if Assigned(Stop) and Stop() then
        Break;
      { All four replies in, and the xd:// notice (or 3 s without it): done. }
      if Result.Responses.Count >= 4 then
      begin
        if Quiet = 0 then
          Quiet := GetTickCount64;
        if Result.Mounted or (GetTickCount64 - Quiet > 3000) then
          Break;
      end;
      if not PeekNamedPipe(Pipes.StdOut, nil, 0, nil, @Available, nil) then
        Break;
      if Available = 0 then
      begin
        Sleep(20);
        Continue;
      end;
      if not ReadFile(Pipes.StdOut, Buffer[0], Length(Buffer), Count, nil) or (Count = 0) then
        Break;
      Start := Length(Pending);
      SetLength(Pending, Start + Integer(Count));
      Move(Buffer[0], Pending[Start], Count);
      Start := 0;
      for Index := 0 to High(Pending) do
        if Pending[Index] = 10 then
        begin
          if Index > Start then
            Handle(Pipes, Chunks.Feed(TEncoding.UTF8.GetString(Pending, Start, Index - Start).TrimRight),
              Result, NextId);
          Start := Index + 1;
        end;
      Pending := Copy(Pending, Start, MaxInt);
    end;
  finally
    Chunks.Free;
    CloseHandle(Pipes.StdIn);
    if WaitForSingleObject(Pipes.Process, 3000) = WAIT_TIMEOUT then
      TerminateProcess(Pipes.Process, 1);
    CloseHandle(Pipes.StdOut);
    CloseHandle(Pipes.Thread);
    CloseHandle(Pipes.Process);
  end;
  if Result.Ready = '' then
    Result.ExitReason := ChildExitReason(Stderr);
end;

function ResponseOk(const Line: string): Boolean;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Line);
  try
    Result := (Obj <> nil) and not IsJsonFalse(Obj.GetValue('success'));
  finally
    Obj.Free;
  end;
end;

function HostToolsCheck(const Line: string): TOmpCheck;
var
  Obj, Data: TJSONObject;
  Names: TJSONValue;
begin
  Obj := JsonObject(Line);
  try
    Data := JsonChild(Obj, 'data');
    Names := nil;
    if Data <> nil then
      Names := Data.GetValue('toolNames');
    if not ResponseOk(Line) or not (Names is TJSONArray) then
      Exit(Check(Tr('ompprobe.checkHostTools'), False, TrF('ompprobe.noResponseOrFailed', [Copy(Line, 1, 200)])));
    Result := Check(Tr('ompprobe.checkHostTools'), Names.ToJSON.Contains('"rad.compile"'),
      TrF('ompprobe.registeredCount', [TJSONArray(Names).Count]));
  finally
    Obj.Free;
  end;
end;

function ProbeOmp(const Executable, WorkDir: string; const Stop: TFunc<Boolean>): TArray<TOmpCheck>;
var
  Version, Help, Missing, Flag, Config: string;
  Found: TRpcFindings;
  Info: TStateInfo;
  Commands: TArray<TSlashCommand>;
  Levels: TArray<string>;
  Settings: TJSONObject;
begin
  Version := OmpVersionText(Executable);
  Result := [Check(Tr('ompprobe.checkVersion'), Version <> '', TrF('ompprobe.testedVersion', [Version, TestedOmpVersion]))];
  if Version = '' then
    Exit;
  Help := RunOmp(Executable, '--help', WorkDir, 10000);
  Missing := '';
  for Flag in UsedFlags do
    if not Help.Contains(Flag) then
      Missing := Missing + ' ' + Flag;
  Result := Result + [Check(Tr('ompprobe.checkCliFlags'), Missing = '', IfThen(Missing = '',
    TrF('ompprobe.allFlagsPresent', [Length(UsedFlags)]), TrF('ompprobe.flagsMissing', [Missing])))];
  Found := RunRpc(Executable, WorkDir, Stop);
  try
    Result := Result + [Check(Tr('ompprobe.checkRpcStart'), Found.Ready <> '',
      IfThen(Found.Ready <> '', 'protocol v' + IntToStr(Found.Protocol), Found.ExitReason))];
    if Found.Ready = '' then
      Exit;
    Result := Result + [Check(Tr('ompprobe.checkRpcProtocol'), (Found.Protocol = 1) or ((Found.Protocol = 2) and
      ResponseOk(Found.Negotiated)), IfThen(Found.Protocol = 2, Tr('ompprobe.v2Negotiated'), IfThen(Found.Protocol = 1, 'v1',
      Tr('ompprobe.neitherV1NorV2'))))];
    Result := Result + [HostToolsCheck(Found.Responses.Values['set_host_tools'])];
    Result := Result + [Check(Tr('ompprobe.checkXdDevices'), Found.Mounted,
      IfThen(Found.Mounted, Tr('ompprobe.radConnected'), Tr('ompprobe.noRadMountNotice')))];
    Result := Result + [Check(Tr('ompprobe.checkState'), ParseStateInfo(Found.Responses.Values['get_state'], Info) and
      (Info.ModelId <> ''), TrF('ompprobe.modelThinkingDetail', [Info.Provider + '/' + Info.ModelId, Info.ThinkingLevel]))];
    Result := Result + [Check(Tr('ompprobe.checkCommands'),
      ParseAvailableCommands(Found.Responses.Values['get_available_commands'], Commands) and (Length(Commands) > 0),
      TrF('ompprobe.countItems', [Length(Commands)]))];
    Result := Result + [Check(Tr('ompprobe.checkThinkingLevels'),
      ParseThinkingLevels(Found.Responses.Values['get_available_thinking_levels'], Levels) and (Length(Levels) > 0),
      string.Join(', ', Levels))];
  finally
    Found.Responses.Free;
  end;
  Config := RunOmp(Executable, 'config list --json', WorkDir, 20000);
  Settings := JsonObject(Config);
  try
    Result := Result + [Check(Tr('ompprobe.checkConfigList'), (Settings <> nil) and
      (Settings.GetValue('tools.approvalMode') <> nil), Tr('ompprobe.approvalModeKey'))];
  finally
    Settings.Free;
  end;
end;

end.
