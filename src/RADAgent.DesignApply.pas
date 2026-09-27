unit RADAgent.DesignApply;

{ Gives the active project the style chosen for DESIGN.md, the way the IDE itself does it. VCL:
  the Custom_Styles project option links the style (and its dark counterpart) into the program,
  and the program source calls TStyleManager.TrySetStyle (RADAgent.DesignProgram). FMX: a
  TStyleBook on the main form loads the style file (it is stored in the form) and, with
  UseStyleManager, styles every form of the application. The caller has asked the user already.
  Main thread only. }

interface

uses
  RADAgent.DesignCatalog;

{ Dark: FileName '' when there is none. False with Problem (English, for the model). Done lists
  what changed. }
function ApplyProjectStyle(const Style, Dark: TDesignStyle; out Done, Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, ToolsAPI, CommonOptionStrs,
  RADAgent.IdeContext, RADAgent.DesignProgram, RADAgent.FormDesigner, RADAgent.FormBatch,
  RADAgent.Approval;

function ProjectSource(const Project: IOTAProject; out FileName: string): IOTASourceEditor;
var
  Index: Integer;
  Ext: string;
begin
  Result := nil;
  FileName := '';
  for Index := 0 to Project.ModuleFileCount - 1 do
  begin
    Ext := LowerCase(ExtractFileExt(Project.ModuleFileEditors[Index].FileName));
    if ((Ext = '.dpr') or (Ext = '.cpp')) and
      Supports(Project.ModuleFileEditors[Index], IOTASourceEditor, Result) then
    begin
      FileName := Project.ModuleFileEditors[Index].FileName;
      Exit;
    end;
  end;
  Result := nil;
end;

function ReadAll(const Source: IOTASourceEditor): string;
var
  Reader: IOTAEditReader;
  Bytes: TBytes;
  Chunk: array[0..16383] of AnsiChar;
  Read, Position: Integer;
begin
  Reader := Source.CreateReader;
  Position := 0;
  repeat
    Read := Reader.GetText(Position, @Chunk[0], SizeOf(Chunk));
    if Read > 0 then
    begin
      SetLength(Bytes, Length(Bytes) + Read);
      Move(Chunk[0], Bytes[Length(Bytes) - Read], Read);
      Inc(Position, Read);
    end;
  until Read < SizeOf(Chunk);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

procedure ReplaceAll(const Source: IOTASourceEditor; const OldText, NewText: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := Source.CreateUndoableWriter;
  Writer.DeleteTo(Length(TEncoding.UTF8.GetBytes(OldText)));
  Writer.Insert(PAnsiChar(UTF8String(NewText)));
  Writer := nil;
end;

function ApplyVcl(const Project: IOTAProject; const Style, Dark: TDesignStyle;
  out Done, Problem: string): Boolean;
var
  Configs: IOTAProjectOptionsConfigurations;
  Linked: array of TLinkedStyle;
  Source: IOTASourceEditor;
  SourceFile, OldText, NewText: string;
begin
  Result := False;
  Source := ProjectSource(Project, SourceFile);
  if Source = nil then
  begin
    Problem := 'The project source (.dpr/.cpp) is not loaded in the IDE.';
    Exit;
  end;
  OldText := ReadAll(Source);
  if not SetProgramStyle(OldText, Style.Name, SameText(ExtractFileExt(SourceFile), '.cpp'),
    NewText, Problem) then
    Exit;
  if not Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
  begin
    Problem := 'The project options cannot be changed through the IDE.';
    Exit;
  end;
  SetLength(Linked, 1);
  Linked[0].Name := Style.Name;
  Linked[0].Path := Style.MacroPath;
  if Dark.FileName <> '' then
  begin
    SetLength(Linked, 2);
    Linked[1].Name := Dark.Name;
    Linked[1].Path := Dark.MacroPath;
  end;
  Configs.BaseConfiguration.Value[sCustom_Styles] :=
    MergeCustomStyles(Configs.BaseConfiguration.Value[sCustom_Styles], Linked);
  Project.MarkModified;
  if NewText <> OldText then
    ReplaceAll(Source, OldText, NewText);
  Done := Format('Custom_Styles links %s; %s calls TStyleManager.TrySetStyle(''%s'').',
    [Style.FileName, ExtractFileName(SourceFile), Style.Name]);
  if Dark.FileName <> '' then
    Done := Done + Format(' %s (%s) is linked too, for a dark mode switch at run time.',
      [Dark.FileName, Dark.Name]);
  Result := True;
end;

{ The unit of the main form: the first form created in the project source, else the first form. }
function MainFormUnit(const Project: IOTAProject; out FormName: string): string;
var
  Source: IOTASourceEditor;
  SourceFile, Text, ClassName: string;
  Index, At, Stop: Integer;
  Info: IOTAModuleInfo;
begin
  Result := '';
  FormName := '';
  ClassName := '';
  Source := ProjectSource(Project, SourceFile);
  if Source <> nil then
  begin
    Text := ReadAll(Source);
    At := Pos('CreateForm(', Text);
    if At > 0 then
    begin
      At := At + Length('CreateForm(');
      if Copy(Text, At, Length('__classid(')) = '__classid(' then
        At := At + Length('__classid(');
      Stop := At;
      while (Stop <= Length(Text)) and CharInSet(Text[Stop], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Stop);
      ClassName := Copy(Text, At, Stop - At);
    end;
  end;
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    Info := Project.GetModule(Index);
    if (Info = nil) or (Info.FormName = '') then
      Continue;
    if (Result = '') or SameText('T' + Info.FormName, ClassName) then
    begin
      Result := Info.FileName;
      FormName := Info.FormName;
      if SameText('T' + Info.FormName, ClassName) then
        Exit;
    end;
  end;
end;

function ApplyFmx(const Project: IOTAProject; const Style: TDesignStyle;
  out Done, Problem: string): Boolean;
var
  UnitFile, FormName, BookName, ResultText: string;
  Editor: IOTAFormEditor;
  Root: TComponent;
  Index: Integer;
  Args, Book, Props, Form, FormProps: TJSONObject;
  Items: TJSONArray;
  IsError: Boolean;
begin
  Result := False;
  UnitFile := MainFormUnit(Project, FormName);
  if UnitFile = '' then
  begin
    Problem := 'The project has no form to hold the TStyleBook; add the main form first.';
    Exit;
  end;
  Editor := FindFormEditor(UnitFile, Problem);
  if Editor = nil then
    Exit;
  Root := RootOf(Editor);
  BookName := 'AppStyleBook';
  for Index := 0 to Root.ComponentCount - 1 do
    if Root.Components[Index].ClassNameIs('TStyleBook') then
    begin
      BookName := Root.Components[Index].Name;
      Break;
    end;
  Args := TJSONObject.Create;
  try
    Args.AddPair('path', UnitFile);
    Items := TJSONArray.Create;
    Args.AddPair('components', Items);
    Book := TJSONObject.Create;
    Items.AddElement(Book);
    Book.AddPair('name', BookName);
    if BookName = 'AppStyleBook' then
      Book.AddPair('class', 'TStyleBook');
    Props := TJSONObject.Create;
    Book.AddPair('properties', Props);
    Props.AddPair('FileName', Style.Path);
    Props.AddPair('UseStyleManager', 'True');
    Form := TJSONObject.Create;
    Items.AddElement(Form);
    Form.AddPair('name', Root.Name);
    FormProps := TJSONObject.Create;
    Form.AddPair('properties', FormProps);
    FormProps.AddPair('StyleBook', BookName);
    ApplyFormBatch(Args.ToJSON, PreApproved(nil), ResultText, IsError);
  finally
    Args.Free;
  end;
  if IsError then
  begin
    Problem := 'Setting up the TStyleBook failed: ' + ResultText;
    Exit;
  end;
  Done := Format('%s.%s loads %s and styles the whole application (UseStyleManager); %s.StyleBook ' +
    'points to it.', [Root.Name, BookName, Style.FileName, Root.Name]);
  Result := True;
end;

function ApplyProjectStyle(const Style, Dark: TDesignStyle; out Done, Problem: string): Boolean;
var
  Project: IOTAProject;
begin
  Result := False;
  Done := '';
  Problem := '';
  Project := CurrentProject;
  if Project = nil then
  begin
    Problem := 'No active project.';
    Exit;
  end;
  if not Style.Loadable or (Style.Path = '') then
  begin
    Problem := Format('%s cannot be loaded by an application (not installed, or a style designer ' +
      'project).', [Style.FileName]);
    Exit;
  end;
  if SameText(Style.Framework, 'FMX') then
    Result := ApplyFmx(Project, Style, Done, Problem)
  else
    Result := ApplyVcl(Project, Style, Dark, Done, Problem);
end;

end.
