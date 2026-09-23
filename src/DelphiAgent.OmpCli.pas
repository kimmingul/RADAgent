unit DelphiAgent.OmpCli;

{ Runs short omp CLI commands (config list, agents unpack) and returns their stdout. Blocking;
  used only by the settings dialog. No ToolsAPI. }

interface

{ stdout of "<Executable> <Args>" run in WorkDir, or '' on failure/timeout. }
function RunOmp(const Executable, Args, WorkDir: string; TimeoutMs: Cardinal = 20000): string;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows;

function RunOmp(const Executable, Args, WorkDir: string; TimeoutMs: Cardinal): string;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe, NulHandle: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  CommandLine: string;
  Buffer: array[0..8191] of Byte;
  Output: TBytesStream;
  Available, Count: DWORD;
  Deadline: UInt64;
  Finished: Boolean;
begin
  Result := '';
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
    Exit;
  Output := TBytesStream.Create;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    Startup := Default(TStartupInfo);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    Startup.hStdOutput := WritePipe;
    NulHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_WRITE, @Security, OPEN_EXISTING, 0, 0);
    Startup.hStdError := NulHandle;
    CommandLine := '"' + Executable + '" ' + Args;
    UniqueString(CommandLine);
    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(WorkDir), Startup, Info) then
    begin
      CloseHandle(WritePipe);
      CloseHandle(ReadPipe);
      CloseHandle(NulHandle);
      Exit;
    end;
    CloseHandle(WritePipe);
    CloseHandle(NulHandle);
    Deadline := GetTickCount64 + TimeoutMs;
    Finished := False;
    repeat
      if PeekNamedPipe(ReadPipe, nil, 0, nil, @Available, nil) and (Available > 0) then
      begin
        if ReadFile(ReadPipe, Buffer, SizeOf(Buffer), Count, nil) and (Count > 0) then
          Output.WriteBuffer(Buffer, Count);
      end
      else if Finished then
        Break
      else
      begin
        Finished := WaitForSingleObject(Info.hProcess, 30) = WAIT_OBJECT_0;
      end;
    until GetTickCount64 > Deadline;
    if not Finished then
      TerminateProcess(Info.hProcess, 1);
    CloseHandle(Info.hThread);
    CloseHandle(Info.hProcess);
    CloseHandle(ReadPipe);
    if Finished then
      Result := TEncoding.UTF8.GetString(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
  end;
end;

end.
