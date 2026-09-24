unit DelphiAgent.GitRepo;

{ git for DelphiAgent: the project's repository and one checkpoint commit per user message.
  Checkpoints never touch the user's index, HEAD or branches: they are built in a private index
  file and kept under refs/delphiagent/, each a single commit on top of HEAD holding the whole
  working tree. Commands run synchronously and quickly on a project folder. No ToolsAPI. }

interface

type
  TCheckpoint = record
    Seq: Integer;
    Commit, Prompt, When: string;
  end;

const
  CheckpointRefs = 'refs/delphiagent/cp/';
  SafetyRefs = 'refs/delphiagent/before-restore/';

function GitExecutable: string;
{ Top folder of the repository holding Dir, or ''. }
function GitRoot(const Dir: string): string;
{ git init in Dir, a Delphi .gitignore when there is none, and a first commit of what is there. }
function InitRepo(const Dir: string; out Problem: string): Boolean;
{ Commits the working tree of Root under RefPrefix (numbered). Prompt is the commit body. }
function CreateCheckpoint(const Root, RefPrefix, Prompt: string; out Seq: Integer;
  out Commit, Problem: string): Boolean;
{ Checkpoints under CheckpointRefs, oldest first. }
function ListCheckpoints(const Root: string): TArray<TCheckpoint>;
{ Makes the working tree equal to Commit: writes its files and deletes the files that exist in
  Current (a checkpoint of the tree as it is now) but not in Commit. }
function RestoreCheckpoint(const Root, Commit, Current: string; out Problem: string): Boolean;
{ New branch Name at Commit, checked out without touching the (already restored) files. }
function BranchAtCheckpoint(const Root, Commit, Name: string; out Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows;

const
  RecordEnd = '<<DelphiAgent-end>>';
  GitIgnore =
    '# Delphi build output and IDE state (DelphiAgent)'#13#10'__history/'#13#10'__recovery/'#13#10 +
    '*.dcu'#13#10'*.local'#13#10'*.identcache'#13#10'*.stat'#13#10'*.dsk'#13#10'*.tvsconfig'#13#10 +
    '*.delphilsp.json'#13#10'Win32/'#13#10'Win64/'#13#10'Win64x/'#13#10'Linux64/'#13#10'OSX64/'#13#10 +
    'OSXARM64/'#13#10'Android/'#13#10'Android64/'#13#10'iOSDevice64/'#13#10'.omp/lsp.json'#13#10;

function GitExecutable: string;
var
  Buf: array[0..MAX_PATH] of Char;
  Part: PChar;
begin
  Part := nil;
  if SearchPath(nil, 'git.exe', nil, MAX_PATH, Buf, Part) > 0 then
    Exit(PChar(@Buf[0]));
  Result := GetEnvironmentVariable('ProgramFiles') + '\Git\cmd\git.exe';
  if not FileExists(Result) then
    Result := '';
end;

function EnvironmentWith(const Name, Value: string): string;
var
  Block, Item: PChar;
begin
  Result := '';
  Block := GetEnvironmentStrings;
  try
    Item := Block;
    while Item^ <> #0 do
    begin
      if not string(Item).StartsWith(Name + '=', True) then
        Result := Result + string(Item) + #0;
      Inc(Item, StrLen(Item) + 1);
    end;
  finally
    FreeEnvironmentStrings(Block);
  end;
  Result := Result + Name + '=' + Value + #0#0;
end;

{ Runs git in Dir; stdout and stderr together in Output. IndexFile, when set, is GIT_INDEX_FILE.
  Returns the exit code, -1 when git could not run. }
function RunGit(const Dir, Args: string; out Output: string; const IndexFile: string = ''): Integer;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  CommandLine, Env: string;
  EnvPtr: Pointer;
  Buffer: array[0..8191] of Byte;
  Bytes: TBytesStream;
  Available, Count, Code: DWORD;
  Deadline: UInt64;
  Finished: Boolean;
begin
  Result := -1;
  Output := '';
  if GitExecutable = '' then
    Exit;
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
    Exit;
  SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
  Startup := Default(TStartupInfo);
  Startup.cb := SizeOf(Startup);
  Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  Startup.wShowWindow := SW_HIDE;
  Startup.hStdOutput := WritePipe;
  Startup.hStdError := WritePipe;
  CommandLine := '"' + GitExecutable + '" -c core.quotepath=false ' + Args;
  UniqueString(CommandLine);
  EnvPtr := nil;
  if IndexFile <> '' then
  begin
    Env := EnvironmentWith('GIT_INDEX_FILE', IndexFile);
    EnvPtr := PChar(Env);
  end;
  Bytes := TBytesStream.Create;
  try
    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW or
      CREATE_UNICODE_ENVIRONMENT, EnvPtr, PChar(Dir), Startup, Info) then
    begin
      CloseHandle(WritePipe);
      CloseHandle(ReadPipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    Deadline := GetTickCount64 + 60000;
    Finished := False;
    repeat
      if PeekNamedPipe(ReadPipe, nil, 0, nil, @Available, nil) and (Available > 0) then
      begin
        if ReadFile(ReadPipe, Buffer, SizeOf(Buffer), Count, nil) and (Count > 0) then
          Bytes.WriteBuffer(Buffer, Count);
      end
      else if Finished then
        Break
      else
        Finished := WaitForSingleObject(Info.hProcess, 20) = WAIT_OBJECT_0;
    until GetTickCount64 > Deadline;
    if not Finished then
      TerminateProcess(Info.hProcess, 1);
    GetExitCodeProcess(Info.hProcess, Code);
    CloseHandle(Info.hThread);
    CloseHandle(Info.hProcess);
    CloseHandle(ReadPipe);
    Output := TEncoding.UTF8.GetString(Bytes.Bytes, 0, Bytes.Size);
    if Finished then
      Result := Integer(Code);
  finally
    Bytes.Free;
  end;
end;

function Git(const Dir, Args: string; out Output: string; const IndexFile: string = ''): Boolean;
begin
  Result := RunGit(Dir, Args, Output, IndexFile) = 0;
  Output := Output.TrimRight;
end;

function Quote(const Value: string): string;
begin
  Result := '"' + Value + '"';
end;

{ -c user.* only when the user has not set an identity; commits must not fail over it. }
function Identity(const Root: string): string;
var
  Email: string;
begin
  Result := '';
  if not Git(Root, 'config user.email', Email) or (Email = '') then
    Result := '-c user.name=DelphiAgent -c user.email=delphiagent@localhost ';
end;

function GitRoot(const Dir: string): string;
begin
  if (Dir = '') or not Git(Dir, 'rev-parse --show-toplevel', Result) then
    Result := ''
  else
    Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
end;

function InitRepo(const Dir: string; out Problem: string): Boolean;
var
  Output: string;
begin
  Problem := '';
  Result := Git(Dir, 'init', Output);
  if not Result then
  begin
    Problem := Output;
    Exit;
  end;
  if not FileExists(TPath.Combine(Dir, '.gitignore')) then
    TFile.WriteAllText(TPath.Combine(Dir, '.gitignore'), GitIgnore, TEncoding.ASCII);
  Git(Dir, 'add -A', Output);
  Result := Git(Dir, Identity(Dir) + 'commit -q --allow-empty -m ' + Quote('DelphiAgent: 처음 상태'), Output);
  if not Result then
    Problem := Output;
end;

function GitDir(const Root: string): string;
begin
  if not Git(Root, 'rev-parse --absolute-git-dir', Result) then
    Result := '';
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
end;

function NextSeq(const Root, RefPrefix: string): Integer;
var
  Output, Line: string;
begin
  Result := 1;
  if not Git(Root, 'for-each-ref --format=%(refname) ' + RefPrefix, Output) then
    Exit;
  for Line in Output.Split([#10], TStringSplitOptions.ExcludeEmpty) do
    if StrToIntDef(Copy(Line.Trim, Length(RefPrefix) + 1, MaxInt), 0) >= Result then
      Result := StrToIntDef(Copy(Line.Trim, Length(RefPrefix) + 1, MaxInt), 0) + 1;
end;

function CreateCheckpoint(const Root, RefPrefix, Prompt: string; out Seq: Integer;
  out Commit, Problem: string): Boolean;
var
  Index, Head, Tree, MessageFile, Output, Subject: string;
begin
  Result := False;
  Seq := 0;
  Commit := '';
  Index := GitDir(Root) + '\delphiagent-index';
  if not Git(Root, 'rev-parse --verify -q HEAD', Head) then
    Head := '';
  if Head <> '' then
    Git(Root, 'read-tree HEAD', Output, Index)
  else
    Git(Root, 'read-tree --empty', Output, Index);
  if not Git(Root, 'add -A', Output, Index) or not Git(Root, 'write-tree', Tree, Index) then
  begin
    Problem := Output;
    Exit;
  end;
  Subject := Trim(Copy(Prompt, 1, Pos(#10, Prompt + #10) - 1));
  if Length(Subject) > 72 then
    Subject := Copy(Subject, 1, 71) + '…';
  MessageFile := GitDir(Root) + '\delphiagent-message.txt';
  { The tree is the state before the message was sent. }
  TFile.WriteAllBytes(MessageFile, TEncoding.UTF8.GetBytes('DelphiAgent: 보내기 전 - ' + Subject + #10#10 +
    Prompt + #10));
  if Head <> '' then
    Head := ' -p ' + Head;
  if not Git(Root, Identity(Root) + 'commit-tree ' + Tree + Head + ' -F ' + Quote(MessageFile), Commit) then
  begin
    Problem := Commit;
    Commit := '';
    Exit;
  end;
  Seq := NextSeq(Root, RefPrefix);
  Result := Git(Root, 'update-ref ' + RefPrefix + Format('%.6d', [Seq]) + ' ' + Commit, Output);
  if not Result then
    Problem := Output;
end;

function ListCheckpoints(const Root: string): TArray<TCheckpoint>;
var
  Output, Item: string;
  Fields: TArray<string>;
  Point: TCheckpoint;
  Body: string;
begin
  Result := nil;
  if not Git(Root, 'for-each-ref --sort=refname --format="%(refname)%00%(objectname)%00' +
    '%(creatordate:format:%Y-%m-%d %H:%M)%00%(contents:body)' + RecordEnd + '" ' + CheckpointRefs, Output) then
    Exit;
  for Item in Output.Split([RecordEnd], TStringSplitOptions.None) do
  begin
    Fields := Item.Trim([#10, #13]).Split([#0]);
    if Length(Fields) < 4 then
      Continue;
    Point.Seq := StrToIntDef(Copy(Fields[0], Length(CheckpointRefs) + 1, MaxInt), 0);
    Point.Commit := Fields[1];
    Point.When := Fields[2];
    Body := Fields[3];
    Point.Prompt := Body.Trim([#10, #13]);
    if Point.Seq > 0 then
      Result := Result + [Point];
  end;
end;

function RestoreCheckpoint(const Root, Commit, Current: string; out Problem: string): Boolean;
var
  Index, Output, Path: string;
begin
  Problem := '';
  Index := GitDir(Root) + '\delphiagent-restore-index';
  { Files added after the checkpoint go away; git leaves them alone otherwise. }
  if Git(Root, 'diff --name-only -z --diff-filter=A ' + Commit + ' ' + Current, Output) then
    for Path in Output.Split([#0], TStringSplitOptions.ExcludeEmpty) do
      System.SysUtils.DeleteFile(TPath.Combine(Root, StringReplace(Path, '/', '\', [rfReplaceAll])));
  Result := Git(Root, 'read-tree ' + Commit, Output, Index) and
    Git(Root, 'checkout-index -a -f', Output, Index);
  if not Result then
    Problem := Output;
end;

function BranchAtCheckpoint(const Root, Commit, Name: string; out Problem: string): Boolean;
var
  Output: string;
begin
  Result := Git(Root, 'branch ' + Quote(Name) + ' ' + Commit, Output) and
    Git(Root, 'symbolic-ref HEAD refs/heads/' + Name, Output) and
    Git(Root, 'reset -q', Output);
  if not Result then
    Problem := Output;
end;

end.
