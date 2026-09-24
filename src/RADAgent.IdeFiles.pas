unit RADAgent.IdeFiles;

{ Disk is the truth between the IDE and omp. Before a prompt the project's unsaved modules are
  saved; when omp changed files on disk, the IDE modules the user has not touched since are
  reloaded (IOTAModule.Refresh), and the ones the user is editing are reported, not overwritten.
  Main thread only. }

interface

{ Saves every modified module under ProjectDir, the project itself included. Problem names the
  modules that could not be saved. }
function SaveProjectModules(const ProjectDir: string; out Problem: string): Boolean;
{ Reloads modules whose files changed on disk since they were last saved or seen. Conflicts are
  modules changed on disk that also have unsaved edits in the IDE. Returns the reloaded count. }
function ReloadChangedModules(const ProjectDir: string; out Conflicts: TArray<string>): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, ToolsAPI;

var
  { Last write time we know of per file (lower case); a different time on disk means omp wrote it. }
  GStamps: TDictionary<string, TDateTime>;

function InProject(const FileName, ProjectDir: string): Boolean;
begin
  Result := (ProjectDir <> '') and (FileName <> '') and
    SameText(Copy(ExpandFileName(FileName), 1, Length(IncludeTrailingPathDelimiter(ProjectDir))),
    IncludeTrailingPathDelimiter(ProjectDir));
end;

function DiskTime(const FileName: string): TDateTime;
begin
  if FileExists(FileName) then
    Result := TFile.GetLastWriteTime(FileName)
  else
    Result := 0;
end;

function ModuleFiles(const Module: IOTAModule): TArray<string>;
var
  Index: Integer;
begin
  Result := [Module.FileName];
  for Index := 0 to Module.ModuleFileCount - 1 do
    if not SameText(Module.ModuleFileEditors[Index].FileName, Module.FileName) then
      Result := Result + [Module.ModuleFileEditors[Index].FileName];
end;

function ModuleModified(const Module: IOTAModule): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Module.ModuleFileEditors[Index].Modified then
      Exit(True);
  Result := False;
end;

procedure Remember(const Module: IOTAModule);
var
  FileName: string;
begin
  for FileName in ModuleFiles(Module) do
    GStamps.AddOrSetValue(LowerCase(FileName), DiskTime(FileName));
end;

function ProjectModules(const ProjectDir: string): TArray<IOTAModule>;
var
  Services: IOTAModuleServices;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
    if InProject(Services.Modules[Index].FileName, ProjectDir) and
      not Supports(Services.Modules[Index], IOTAProjectGroup) then
      Result := Result + [Services.Modules[Index]];
end;

function SaveProjectModules(const ProjectDir: string; out Problem: string): Boolean;
var
  Module: IOTAModule;
begin
  Problem := '';
  for Module in ProjectModules(ProjectDir) do
  begin
    if ModuleModified(Module) then
      try
        if not Module.Save(False, True) then
          Problem := Problem + ' ' + ExtractFileName(Module.FileName);
      except
        on E: Exception do
          Problem := Problem + ' ' + ExtractFileName(Module.FileName) + '(' + E.Message + ')';
      end;
    Remember(Module);
  end;
  Problem := Trim(Problem);
  Result := Problem = '';
end;

function ChangedOnDisk(const Module: IOTAModule): Boolean;
var
  FileName: string;
  Known: TDateTime;
begin
  Result := False;
  for FileName in ModuleFiles(Module) do
    { A module first seen now has nothing to compare with; it counts from here on. }
    if GStamps.TryGetValue(LowerCase(FileName), Known) and (DiskTime(FileName) <> Known) then
      Result := True;
end;

function ReloadChangedModules(const ProjectDir: string; out Conflicts: TArray<string>): Integer;
var
  Module: IOTAModule;
begin
  Result := 0;
  Conflicts := nil;
  for Module in ProjectModules(ProjectDir) do
  begin
    if not ChangedOnDisk(Module) then
    begin
      Remember(Module);
      Continue;
    end;
    if ModuleModified(Module) then
      Conflicts := Conflicts + [Module.FileName]
    else if not FileExists(Module.FileName) then
    begin
      { Deleted on disk (by omp, or by going back to a checkpoint without it). }
      Module.CloseModule(True);
      Inc(Result);
      Continue;
    end
    else
    begin
      Module.Refresh(True);
      Inc(Result);
    end;
    Remember(Module);
  end;
end;

initialization
  GStamps := TDictionary<string, TDateTime>.Create;

finalization
  GStamps.Free;

end.
