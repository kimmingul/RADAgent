unit RADAgent.UnitRename;

{ rad.rename_unit and rad.rename_project: give an existing unit or the project a descriptive name
  (RADAgent.UnitNaming). The IDE saves the module under the new file name (Save As), which moves a
  unit's form file and updates the project, or moves the project file with its program source and
  resources; the project's other units get a renamed unit in their uses clauses, and the old files
  go. Main thread only. }

interface

uses
  ToolsAPI, RADAgent.Approval;

{ Path: the unit's .pas/.cpp, absolute or relative to the project folder. }
function RenameUnit(const Path, NewUnit: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
{ The IDE's Save As without its dialog: the module, its form file, its unit line and the project
  entry take NewFile's name; the old files are removed. }
function SaveUnitAs(const Module: IOTAModule; const NewFile: string): Boolean;
{ The active project becomes <folder>\NewName.dproj (.cbproj) with its program source (.dpr/.cpp),
  resources and output named after it. }
function RenameProject(const NewName: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  RADAgent.IdeContext, RADAgent.IdeFiles, RADAgent.ModuleCreator, RADAgent.UnitNaming,
  RADAgent.FormDesigner, RADAgent.Lang;

function KindOf(const Module: IOTAModule): string;
var
  Index: Integer;
  Editor: IOTAFormEditor;
  Root: TComponent;
  Cls: TClass;
begin
  Result := 'unit';
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTAFormEditor, Editor) then
    begin
      Root := RootOf(Editor);
      Result := 'form';
      Cls := nil;
      if Root <> nil then
        Cls := Root.ClassType;
      while Cls <> nil do
      begin
        if SameText(Cls.ClassName, 'TFrame') or SameText(Cls.ClassName, 'TCustomFrame') then
          Exit('frame');
        if SameText(Cls.ClassName, 'TDataModule') then
          Exit('datamodule');
        Cls := Cls.ClassParent;
      end;
      Exit;
    end;
end;

function FormFileOf(const UnitFile: string): string;
begin
  Result := ChangeFileExt(UnitFile, '.fmx');
  if not FileExists(Result) then
    Result := ChangeFileExt(UnitFile, '.dfm');
end;

function SaveUnitAs(const Module: IOTAModule; const NewFile: string): Boolean;
var
  OldFile, OldForm: string;
begin
  OldFile := Module.FileName;
  OldForm := FormFileOf(OldFile);
  Module.FileName := NewFile;
  Result := Module.Save(False, True) and FileExists(NewFile);
  if not Result then
    Exit;
  if FileExists(ChangeFileExt(NewFile, ExtractFileExt(OldForm))) and FileExists(OldForm) then
    System.SysUtils.DeleteFile(OldForm);
  if FileExists(OldFile) then
    System.SysUtils.DeleteFile(OldFile);
  { C++Builder: the header moves with the .cpp. }
  if SameText(ExtractFileExt(OldFile), '.cpp') and FileExists(ChangeFileExt(NewFile, '.h')) and
    FileExists(ChangeFileExt(OldFile, '.h')) then
    System.SysUtils.DeleteFile(ChangeFileExt(OldFile, '.h'));
end;

{ Rewrites the uses clauses of the project's other units on disk and loads the changed ones again.
  Latin-1 maps every byte to one character, so the file comes back byte for byte apart from the
  (ASCII) unit names, whatever its encoding. }
function UpdateUses(const Project: IOTAProject; const OldUnit, NewUnit, Skip: string): TArray<string>;
var
  Index: Integer;
  FileName, Text, Changed: string;
  Latin1: TEncoding;
  Module: IOTAModule;
begin
  Result := nil;
  Latin1 := TEncoding.GetEncoding(28591);
  try
    for Index := 0 to Project.GetModuleCount - 1 do
    begin
      FileName := Project.GetModule(Index).FileName;
      if SameText(FileName, Skip) or not SameText(ExtractFileExt(FileName), '.pas') or
        not FileExists(FileName) then
        Continue;
      Text := Latin1.GetString(TFile.ReadAllBytes(FileName));
      Changed := RenameInUses(Text, OldUnit, NewUnit);
      if Changed = Text then
        Continue;
      TFile.WriteAllBytes(FileName, Latin1.GetBytes(Changed));
      Result := Result + [ExtractFileName(FileName)];
      Module := (BorlandIDEServices as IOTAModuleServices).FindModule(FileName);
      if Module <> nil then
        ReloadModule(Module);
    end;
  finally
    Latin1.Free;
  end;
end;

function RenameUnit(const Path, NewUnit: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Project: IOTAProject;
  Module: IOTAModule;
  OldFile, NewFile, OldUnit, Problem: string;
  Others: TArray<string>;
  Name: string;
  Updated: TArray<string>;
  Obj: TJSONObject;
  List: TJSONArray;
begin
  Result := False;
  Project := CurrentProject;
  if Project = nil then
  begin
    ResultText := 'No active project.';
    Exit;
  end;
  Module := (BorlandIDEServices as IOTAModuleServices).FindModule(ProjectPath(Path));
  if (Module = nil) and FileExists(ProjectPath(Path)) then
    Module := (BorlandIDEServices as IOTAModuleServices).OpenModule(ProjectPath(Path));
  if Module = nil then
  begin
    ResultText := 'Unit not found: ' + Path;
    Exit;
  end;
  OldFile := Module.FileName;
  OldUnit := ChangeFileExt(ExtractFileName(OldFile), '');
  Others := nil;
  for Name in ProjectUnitNames(Project) do
    if not SameText(Name, OldUnit) then
      Others := Others + [Name];
  if not CheckUnitName(KindOf(Module), NewUnit, SameText(ExtractFileExt(OldFile), '.cpp'), Others, Problem) then
  begin
    ResultText := Problem;
    Exit;
  end;
  NewFile := IncludeTrailingPathDelimiter(ExtractFileDir(OldFile)) + NewUnit + ExtractFileExt(OldFile);
  if FileExists(NewFile) then
  begin
    ResultText := 'File already exists: ' + NewFile;
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveChange(OldFile, '', TrF('unitrename.preview', [OldUnit, NewUnit])) then
  begin
    ResultText := SEditCancelled;
    Exit;
  end;
  { The IDE's Save As: the unit line, the form file and the project follow the new name. }
  if not SaveProjectModules(ExcludeTrailingPathDelimiter(ExtractFileDir(Project.FileName)), Problem) then
  begin
    ResultText := 'Could not save the project first: ' + Problem;
    Exit;
  end;
  if not SaveUnitAs(Module, NewFile) then
  begin
    ResultText := 'The IDE did not save the unit as ' + NewFile + '.';
    Exit;
  end;
  Updated := UpdateUses(Project, OldUnit, NewUnit, NewFile);
  Project.Save(False, True);
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONTrue.Create);
    Obj.AddPair('old', OldUnit);
    Obj.AddPair('new', NewUnit);
    Obj.AddPair('file', NewFile);
    List := TJSONArray.Create;
    for Name in Updated do
      List.Add(Name);
    Obj.AddPair('usesUpdated', List);
    Obj.AddPair('note', 'References outside uses clauses (' + OldUnit + '.Something) are not changed; ' +
      'compile to find any.');
    ResultText := Obj.ToJSON;
  finally
    Obj.Free;
  end;
  Result := True;
end;

function RenameProject(const NewName: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
const
  { Files the IDE writes anew under the new name; the old ones would stay behind. }
  Moved: array[0..4] of string = ('.dpr', '.cpp', '.res', '.dproj', '.cbproj');
var
  Project: IOTAProject;
  OldFile, NewFile, OldName, Problem, Ext: string;
  Obj: TJSONObject;
begin
  Result := False;
  Project := CurrentProject;
  if Project = nil then
  begin
    ResultText := 'No active project.';
    Exit;
  end;
  if not CheckProjectName(NewName, Problem) then
  begin
    ResultText := Problem;
    Exit;
  end;
  OldFile := Project.FileName;
  OldName := ChangeFileExt(ExtractFileName(OldFile), '');
  NewFile := IncludeTrailingPathDelimiter(ExtractFileDir(OldFile)) + NewName + ExtractFileExt(OldFile);
  if FileExists(NewFile) or FileExists(ChangeFileExt(NewFile, '.dpr')) or
    FileExists(ChangeFileExt(NewFile, '.cpp')) then
  begin
    ResultText := 'A project or program file named ' + NewName + ' already exists.';
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveChange(OldFile, '', TrF('unitrename.projectPreview',
    [OldName, NewName])) then
  begin
    ResultText := SEditCancelled;
    Exit;
  end;
  if not SaveProjectModules(ExcludeTrailingPathDelimiter(ExtractFileDir(OldFile)), Problem) then
  begin
    ResultText := 'Could not save the project first: ' + Problem;
    Exit;
  end;
  Project.FileName := NewFile;
  if not Project.Save(False, True) or not FileExists(NewFile) then
  begin
    ResultText := 'The IDE did not save the project as ' + NewFile + '.';
    Exit;
  end;
  { The IDE writes the new .res at the next build; until then the old one carries icon and version. }
  if not FileExists(ChangeFileExt(NewFile, '.res')) and FileExists(ChangeFileExt(OldFile, '.res')) then
    System.SysUtils.RenameFile(ChangeFileExt(OldFile, '.res'), ChangeFileExt(NewFile, '.res'));
  for Ext in Moved do
    if FileExists(ChangeFileExt(NewFile, Ext)) and FileExists(ChangeFileExt(OldFile, Ext)) then
      System.SysUtils.DeleteFile(ChangeFileExt(OldFile, Ext));
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONTrue.Create);
    Obj.AddPair('old', OldName);
    Obj.AddPair('new', NewName);
    Obj.AddPair('file', NewFile);
    Obj.AddPair('note', 'The executable is now ' + NewName + '.exe. Compile to check. Settings named after ' +
      'the old project (' + OldName + '.delphilsp.json, per-user .local/.identcache files) are ' +
      'written anew by the IDE.');
    ResultText := Obj.ToJSON;
  finally
    Obj.Free;
  end;
  Result := True;
end;

end.
