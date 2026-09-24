unit DelphiAgent.ChatDiskSync;

{ Keeps the IDE and the disk in step around omp's work: the project is saved before every prompt
  and after every approved rad.* change, and files omp changed on disk are loaded back into the
  IDE after each of its tools and at the end of the turn. Main thread only. }

interface

uses
  DelphiAgent.RpcEvents;

{ Saves the project's unsaved modules; a chat notice names the ones that failed. }
function SaveProject: Boolean;
{ After every agent event: reload what omp changed; refresh the todo panel after the todo tool. }
procedure SyncAfterEvent(const Event: TAgentEvent);

implementation

uses
  System.SysUtils, DelphiAgent.ChatSession, DelphiAgent.IdeFiles, DelphiAgent.IdeContext,
  DelphiAgent.ChatCommand;

function ProjectDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(ActiveProjectDir);
end;

function SaveProject: Boolean;
var
  Problem: string;
begin
  Result := (ProjectDir = '') or SaveProjectModules(ProjectDir, Problem);
  if not Result then
    ChatSession.Notice('warn', '저장하지 못한 파일이 있어 omp가 예전 내용을 볼 수 있습니다: ' + Problem);
end;

procedure ReloadFromDisk;
var
  Conflicts: TArray<string>;
  FileName: string;
begin
  if ProjectDir = '' then
    Exit;
  ReloadChangedModules(ProjectDir, Conflicts);
  for FileName in Conflicts do
    ChatSession.Notice('warn', 'omp가 ' + ExtractFileName(FileName) + '을(를) 디스크에서 바꿨지만 IDE에 ' +
      '저장하지 않은 변경이 있어 다시 읽지 않았습니다. 저장하면 omp의 변경을 덮어쓰고, ' +
      'File > Revert로 되돌리면 omp의 변경을 받습니다.');
end;

procedure SyncAfterEvent(const Event: TAgentEvent);
begin
  if (Event.Kind = aekToolEnd) and (Event.ToolName = 'todo') then
    ChatSession.SendCommand('get_state', BuildIdTypeFrame('req', 'get_state'));
  if (Event.Kind = aekToolEnd) or (Event.Kind = aekPromptLocal) or
    ((Event.Kind = aekAgentEnd) and Event.IsTerminal) then
    ReloadFromDisk;
end;

end.
