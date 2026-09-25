unit RADAgent.ProcessRun;

{ Runs a console program without a window and returns what it printed (stdout and stderr
  together, UTF-8). Used for git and the C++ compiler checks. No ToolsAPI. }

interface

{ Exit code, or -1 when the program could not start or did not finish within TimeoutMs.
  Environment: a CREATE_UNICODE_ENVIRONMENT block, or '' for the current one. }
function RunCaptured(const CommandLine, Dir: string; out Output: string; TimeoutMs: Cardinal = 60000;
  const Environment: string = ''): Integer;
{ The current environment block with Name set to Value. }
function EnvironmentWith(const Name, Value: string): string;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows;

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

function RunCaptured(const CommandLine, Dir: string; out Output: string; TimeoutMs: Cardinal;
  const Environment: string): Integer;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  Command: string;
  EnvPtr: Pointer;
  Buffer: array[0..8191] of Byte;
  Bytes: TBytesStream;
  Available, Count, Code: DWORD;
  Deadline: UInt64;
  Finished: Boolean;
begin
  Result := -1;
  Output := '';
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
  Command := CommandLine;
  UniqueString(Command);
  EnvPtr := nil;
  if Environment <> '' then
    EnvPtr := PChar(Environment);
  Bytes := TBytesStream.Create;
  try
    if not CreateProcess(nil, PChar(Command), nil, nil, True, CREATE_NO_WINDOW or
      CREATE_UNICODE_ENVIRONMENT, EnvPtr, PChar(Dir), Startup, Info) then
    begin
      CloseHandle(WritePipe);
      CloseHandle(ReadPipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    Deadline := GetTickCount64 + TimeoutMs;
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

end.
