unit DelphiAgent.IdeContext;

{ Active project, editor file, and caret. ToolsAPI calls stay on the main thread. }

interface

uses
  System.SysUtils, ToolsAPI;

function CurrentProject: IOTAProject;

type
  TEditorText = record
    FileName: string;
    Text: string;
    Line: Integer;
    Col: Integer;
  end;

function ActiveProjectFile: string;
function ActiveProjectDir: string;
function DirtyEditorTexts: TArray<TEditorText>;
function CurrentEditorText: TEditorText;
function BufferText(const FileName: string): string;
procedure ReportToMessageView(const Text: string);
procedure ReportNoProject;

type
  TProjectChanged = procedure of object;

procedure InstallProjectWatch(const OnChange: TProjectChanged);
procedure RemoveProjectWatch;

implementation

uses
  System.Classes, System.IOUtils, Winapi.Windows;

type
  TProjectWatch = class(TNotifierObject, IOTAIDENotifier)
  protected
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

var
  GLastProjectFile: string;
  GWatch: IOTAIDENotifier;
  GWatchIndex: Integer;
  GOnProjectChange: TProjectChanged;

procedure RequireMainThread;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
end;

function MessageServices: IOTAMessageServices;
begin
  Result := BorlandIDEServices as IOTAMessageServices;
end;

procedure ReportToMessageView(const Text: string);
begin
  RequireMainThread;
  MessageServices.AddToolMessage('', Text, 'DelphiAgent', 0, 0);
end;

procedure ReportNoProject;
begin
  ReportToMessageView('활성 프로젝트가 없어 프롬프트를 보내지 않았습니다.');
end;

function ProjectFromGroup(const Group: IOTAProjectGroup): IOTAProject;
begin
  Result := nil;
  if Group = nil then
    Exit;
  Result := Group.ActiveProject;
end;

procedure RememberProject(const FileName: string);
begin
  if FileName <> '' then
    GLastProjectFile := FileName;
end;

function EditorFileName: string;
var
  Services: IOTAEditorServices;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, Services) then
    Exit;
  if (Services.TopView <> nil) and (Services.TopView.Buffer <> nil) then
    Result := Services.TopView.Buffer.FileName;
end;

function DprojBeside(const StartFile: string): string;
var
  Dir, Parent: string;
  Found: TArray<string>;
  Depth: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(StartFile);
  Depth := 0;
  while (Dir <> '') and (Depth < 8) do
  begin
    Found := TDirectory.GetFiles(Dir, '*.dproj', TSearchOption.soTopDirectoryOnly);
    if Length(Found) > 0 then
      Exit(Found[0]);
    Parent := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
    if SameText(ExcludeTrailingPathDelimiter(Parent), ExcludeTrailingPathDelimiter(Dir)) then
      Break;
    Dir := IncludeTrailingPathDelimiter(Parent);
    Inc(Depth);
  end;
end;

function CurrentProject: IOTAProject;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Module: IOTAModule;
  Index: Integer;
  NearFile: string;
begin
  RequireMainThread;
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Result := ProjectFromGroup(Modules.MainProjectGroup);
  if Result <> nil then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[Index];
    if Supports(Module, IOTAProjectGroup, Group) then
    begin
      Result := ProjectFromGroup(Group);
      if Result <> nil then
        Exit;
    end;
  end;
  for Index := 0 to Modules.ModuleCount - 1 do
    if Supports(Modules.Modules[Index], IOTAProject, Result) then
      Exit;
  NearFile := DprojBeside(EditorFileName);
  if NearFile = '' then
    NearFile := GLastProjectFile;
  if NearFile = '' then
    Exit;
  Module := Modules.FindModule(NearFile);
  if not Supports(Module, IOTAProject, Result) then
    Result := nil;
end;

function ActiveProjectFile: string;
var
  Project: IOTAProject;
begin
  Result := '';
  Project := CurrentProject;
  if Project <> nil then
    Result := Project.FileName;
  if Result = '' then
    Result := DprojBeside(EditorFileName);
  if Result = '' then
    Result := GLastProjectFile;
  RememberProject(Result);
end;

function ActiveProjectDir: string;
var
  FileName: string;
begin
  FileName := ActiveProjectFile;
  if FileName = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(FileName));
end;

function ReadSource(const Source: IOTASourceEditor): string;
var
  Reader: IOTAEditReader;
  Chunk: TBytes;
  Data: TBytes;
  Count, Offset, Total: Integer;
begin
  Reader := Source.CreateReader;
  try
    SetLength(Chunk, 8192);
    SetLength(Data, 0);
    Offset := 0;
    repeat
      Count := Reader.GetText(Offset, PAnsiChar(@Chunk[0]), Length(Chunk));
      if Count <= 0 then
        Break;
      Total := Length(Data);
      SetLength(Data, Total + Count);
      Move(Chunk[0], Data[Total], Count);
      Inc(Offset, Count);
    until Count < Length(Chunk);
  finally
    Reader := nil;
  end;
  Result := TEncoding.UTF8.GetString(Data);
end;

function SourceFromEditor(const Editor: IOTAEditor): IOTASourceEditor;
begin
  if not Supports(Editor, IOTASourceEditor, Result) then
    Result := nil;
end;

function DirtyEditorTexts: TArray<TEditorText>;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  Source: IOTASourceEditor;
  ModuleIndex, FileIndex, Count: Integer;
  Item: TEditorText;
begin
  RequireMainThread;
  SetLength(Result, 0);
  Modules := BorlandIDEServices as IOTAModuleServices;
  for ModuleIndex := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[ModuleIndex];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
    begin
      Editor := Module.ModuleFileEditors[FileIndex];
      Source := SourceFromEditor(Editor);
      if (Source = nil) or not Source.Modified then
        Continue;
      Item.FileName := Source.FileName;
      Item.Text := ReadSource(Source);
      Item.Line := 1;
      Item.Col := 1;
      Count := Length(Result);
      SetLength(Result, Count + 1);
      Result[Count] := Item;
    end;
  end;
end;

function CurrentEditorText: TEditorText;
var
  Services: IOTAEditorServices;
  View: IOTAEditView;
  Source: IOTASourceEditor;
begin
  RequireMainThread;
  Result.FileName := '';
  Result.Text := '';
  Result.Line := 0;
  Result.Col := 0;
  Services := BorlandIDEServices as IOTAEditorServices;
  View := Services.TopView;
  if View = nil then
    Exit;
  Result.Line := View.CursorPos.Line;
  Result.Col := View.CursorPos.Col;
  if View.Buffer = nil then
    Exit;
  Result.FileName := View.Buffer.FileName;
  if Supports(View.Buffer, IOTASourceEditor, Source) then
    Result.Text := ReadSource(Source);
end;

function BufferText(const FileName: string): string;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Source: IOTASourceEditor;
  FileIndex: Integer;
begin
  RequireMainThread;
  Result := '';
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.FindModule(FileName);
  if Module = nil then
    Exit;
  for FileIndex := 0 to Module.ModuleFileCount - 1 do
  begin
    Source := SourceFromEditor(Module.ModuleFileEditors[FileIndex]);
    if (Source <> nil) and SameText(Source.FileName, FileName) then
    begin
      Result := ReadSource(Source);
      Exit;
    end;
  end;
end;

procedure TProjectWatch.AfterSave;
begin
end;

procedure TProjectWatch.BeforeSave;
begin
end;

procedure TProjectWatch.Destroyed;
begin
end;

procedure TProjectWatch.Modified;
begin
end;

procedure TProjectWatch.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TProjectWatch.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TProjectWatch.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
  case NotifyCode of
    ofnFileOpened, ofnFileClosing, ofnActiveProjectChanged,
    ofnEndProjectGroupOpen, ofnEndProjectGroupClose:
      if Assigned(GOnProjectChange) then
        GOnProjectChange;
  end;
end;

procedure InstallProjectWatch(const OnChange: TProjectChanged);
var
  Services: IOTAServices;
begin
  GOnProjectChange := OnChange;
  if GWatchIndex >= 0 then
    Exit;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  GWatch := TProjectWatch.Create;
  GWatchIndex := Services.AddNotifier(GWatch);
end;

procedure RemoveProjectWatch;
var
  Services: IOTAServices;
begin
  GOnProjectChange := nil;
  if (GWatchIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(GWatchIndex);
  GWatchIndex := -1;
  GWatch := nil;
end;

initialization
  GWatchIndex := -1;

finalization
  RemoveProjectWatch;

end.
