unit RADAgent.ChatDiskSync;

{ Keeps the IDE and the disk in step around omp's work: the project is saved before every prompt
  and after every approved rad.* change, and files omp changed on disk are loaded back into the
  IDE after each of its tools and at the end of the turn. Main thread only. }

interface

uses
  RADAgent.RpcEvents;

{ Saves the project's unsaved modules; a chat notice names the ones that failed. }
function SaveProject: Boolean;
{ After every agent event: reload what omp changed; refresh the todo panel after the todo tool. }
procedure SyncAfterEvent(const Event: TAgentEvent);

implementation

uses
  System.SysUtils, RADAgent.ChatSession, RADAgent.IdeFiles, RADAgent.IdeContext,
  RADAgent.ChatCommand, RADAgent.Lang;

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
    ChatSession.Notice('warn', TrF('chatdisksync.notSaved', [Problem]));
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
    ChatSession.Notice('warn', TrF('chatdisksync.conflict', [ExtractFileName(FileName)]));
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
