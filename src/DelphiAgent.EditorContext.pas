unit DelphiAgent.EditorContext;

{ What the chat shows about the editor: active file, selection, unsaved buffer count; and
  opening a file at a line for links in the chat page. Main thread only. }

interface

type
  TEditorInfo = record
    FileName: string;
    HasSelection: Boolean;
    StartLine: Integer;
    EndLine: Integer;
    SelectedText: string;
  end;

function ActiveEditorInfo: TEditorInfo;
function UnsavedModuleCount: Integer;
{ Relative paths resolve against the active project folder. False when it cannot be opened. }
function OpenFileAtLine(const Path: string; Line: Integer): Boolean;
{ Prompt attachment for the selection, or '' when there is none. }
function SelectionAttachment(const Info: TEditorInfo): string;

implementation

uses
  System.SysUtils, System.IOUtils, ToolsAPI, DelphiAgent.IdeContext;

function ActiveEditorInfo: TEditorInfo;
var
  Services: IOTAEditorServices;
  View: IOTAEditView;
  Block: IOTAEditBlock;
begin
  Result := Default(TEditorInfo);
  if not Supports(BorlandIDEServices, IOTAEditorServices, Services) then
    Exit;
  View := Services.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Result.FileName := View.Buffer.FileName;
  Block := View.Block;
  if (Block <> nil) and Block.IsValid and (Block.Size > 0) then
  begin
    Result.HasSelection := True;
    Result.StartLine := Block.StartingRow;
    Result.EndLine := Block.EndingRow;
    { A block ending at column 1 does not include that line. }
    if (Block.EndingColumn <= 1) and (Result.EndLine > Result.StartLine) then
      Dec(Result.EndLine);
    Result.SelectedText := Block.Text;
  end;
end;

function UnsavedModuleCount: Integer;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  ModuleIndex, FileIndex: Integer;
begin
  Result := 0;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for ModuleIndex := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[ModuleIndex];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
      if Module.ModuleFileEditors[FileIndex].Modified then
      begin
        Inc(Result);
        Break;
      end;
  end;
end;

function ResolvePath(const Path: string): string;
var
  Dir: string;
  Found: TArray<string>;
begin
  Result := Path;
  if TPath.IsPathRooted(Path) then
    Exit;
  Dir := ActiveProjectDir;
  if (Dir <> '') and FileExists(TPath.Combine(Dir, Path)) then
    Exit(TPath.Combine(Dir, Path));
  { Bare unit names: search the project folder tree. }
  if Dir <> '' then
  begin
    Found := TDirectory.GetFiles(Dir, ExtractFileName(Path), TSearchOption.soAllDirectories);
    if Length(Found) > 0 then
      Exit(Found[0]);
  end;
  Result := Path;
end;

function OpenFileAtLine(const Path: string; Line: Integer): Boolean;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  FullPath: string;
  Services: IOTAEditorServices;
  View: IOTAEditView;
begin
  Result := False;
  FullPath := ResolvePath(Path);
  if not FileExists(FullPath) then
    Exit;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.OpenModule(FullPath);
  if Module = nil then
    Exit;
  Module.ShowFilename(FullPath);
  Result := True;
  if (Line <= 0) or not Supports(BorlandIDEServices, IOTAEditorServices, Services) then
    Exit;
  View := Services.TopView;
  if (View = nil) or (View.Position = nil) then
    Exit;
  View.Position.GotoLine(Line);
  View.Center(Line, 1);
  View.Paint;
end;

function SelectionAttachment(const Info: TEditorInfo): string;
begin
  Result := '';
  if not Info.HasSelection or (Trim(Info.SelectedText) = '') then
    Exit;
  Result := sLineBreak + sLineBreak + Format('Selected editor text (%s, lines %d-%d, unsaved IDE buffer):',
    [Info.FileName, Info.StartLine, Info.EndLine]) + sLineBreak + '```pascal' + sLineBreak +
    Info.SelectedText.TrimRight + sLineBreak + '```';
end;

end.
