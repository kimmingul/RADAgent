unit RADAgent.IdeFiles;

{ Disk is the truth between the IDE and omp. Before a prompt the project's unsaved modules are
  saved; when omp changed files on disk, the IDE modules the user has not touched since are
  reloaded, and the ones the user is editing are reported, not overwritten. Main thread only. }

interface

uses
  ToolsAPI;

{ Saves every modified module under ProjectDir, the project itself included. Problem names the
  modules that could not be saved. }
function SaveProjectModules(const ProjectDir: string; out Problem: string): Boolean;
{ Reloads modules whose files changed on disk since they were last saved or seen. Conflicts are
  modules changed on disk that also have unsaved edits in the IDE. Returns the reloaded count. }
function ReloadChangedModules(const ProjectDir: string; out Conflicts: TArray<string>): Integer;
{ Loads an unmodified module again from disk. A module with a form is closed and opened again:
  IOTAModule.Refresh reloads the text, but the form designer keeps its old picture of the form
  class (which fields and methods exist, and where), so its next change inserts a field in the
  wrong place or fails ("Expected ')' but ':' found", "A field or method named X already exists"),
  and a failed delete can leave a half-freed component in the Object Inspector. }
procedure ReloadModule(const Module: IOTAModule);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections;

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

procedure RememberFiles(const Files: TArray<string>);
var
  FileName: string;
begin
  for FileName in Files do
    GStamps.AddOrSetValue(LowerCase(FileName), DiskTime(FileName));
end;

procedure Remember(const Module: IOTAModule);
begin
  RememberFiles(ModuleFiles(Module));
end;

function HasForm(const Module: IOTAModule): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTAFormEditor) then
      Exit(True);
  Result := False;
end;

function HasEditView(const Module: IOTAModule): Boolean;
var
  Index: Integer;
  Source: IOTASourceEditor;
begin
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Source) and (Source.EditViewCount > 0) then
      Exit(True);
  Result := False;
end;

procedure ReloadModule(const Module: IOTAModule);
var
  FileName: string;
  Shown: Boolean;
  Reopened: IOTAModule;
begin
  if not HasForm(Module) then
  begin
    Module.Refresh(True);
    Exit;
  end;
  FileName := Module.FileName;
  Shown := HasEditView(Module);
  Module.CloseModule(True);
  Reopened := (BorlandIDEServices as IOTAModuleServices).OpenModule(FileName);
  if Shown and (Reopened <> nil) then
    Reopened.Show;
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
  Files: TArray<string>;
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
    begin
      Conflicts := Conflicts + [Module.FileName];
      Remember(Module);
    end
    else if not FileExists(Module.FileName) then
    begin
      { Deleted on disk (by omp, or by going back to a checkpoint without it). }
      Module.CloseModule(True);
      Inc(Result);
    end
    else
    begin
      { The files, not the module: a form module is closed and opened again. }
      Files := ModuleFiles(Module);
      ReloadModule(Module);
      RememberFiles(Files);
      Inc(Result);
    end;
  end;
end;

initialization
  GStamps := TDictionary<string, TDateTime>.Create;

finalization
  GStamps.Free;

end.
