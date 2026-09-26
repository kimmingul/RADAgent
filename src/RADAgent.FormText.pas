unit RADAgent.FormText;

{ rad.form_text_edit: property changes made as text in .dfm/.fmx files, for bulk work the
  designer does one call at a time (fonts, colours, captions across many forms). The edits are
  exact old/new text; they may not add, remove or rename objects (object/inherited/inline/end
  lines), so the unit's field declarations stay right, and every new property must exist on the
  live component. One approval shows the whole diff; then the files are written in their own
  encoding and the IDE reloads the modules. Main thread only. }

interface

uses
  RADAgent.Approval;

(* ArgumentsJson: {"edits":[{"path","old","new"}]}; path is the unit or its form file. *)
function EditFormText(const ArgumentsJson: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.TypInfo,
  System.RegularExpressions, System.Generics.Collections, ToolsAPI, RADAgent.FormDesigner,
  RADAgent.IdeFiles, RADAgent.IdeContext, RADAgent.FormNonVisual;

type
  TFormFile = class
    UnitPath, FormPath, Before, After: string;
    Encoding: TEncoding;
    Editor: IOTAFormEditor;
  end;

function FormFileOf(const Path: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  if (Ext = '.dfm') or (Ext = '.fmx') then
    Exit(Path);
  Result := ChangeFileExt(Path, '.dfm');
  if not FileExists(Result) then
    Result := ChangeFileExt(Path, '.fmx');
end;

function UnitOf(const FormPath: string): string;
begin
  Result := ChangeFileExt(FormPath, '.pas');
  if not FileExists(Result) then
    Result := ChangeFileExt(FormPath, '.cpp');
end;

function StructureLine(const Line: string): Boolean;
begin
  Result := TRegEx.IsMatch(Line, '^\s*(object|inherited|inline)\s+\w*\s*:|^\s*end\s*$', [roIgnoreCase]);
end;

function StructureLines(const Text: string): TArray<string>;
var
  Lines: TArray<string>;
  Line, Trimmed: string;
begin
  Result := nil;
  Lines := Text.Split([#10]);
  for Line in Lines do
  begin
    Trimmed := Trim(Line);
    if StructureLine(Trimmed) then
      Result := Result + [Trimmed];
  end;
end;

function SameStructure(const BeforeText, AfterText: string): Boolean;
var
  BeforeLines, AfterLines: TArray<string>;
  Index: Integer;
begin
  BeforeLines := StructureLines(BeforeText);
  AfterLines := StructureLines(AfterText);
  if Length(BeforeLines) <> Length(AfterLines) then
    Exit(False);
  for Index := 0 to High(BeforeLines) do
    if not SameText(BeforeLines[Index], AfterLines[Index]) then
      Exit(False);
  Result := True;
end;

function ModuleHasUnsavedEdits(const Module: IOTAModule): Boolean;
var
  Index: Integer;
  Editor: IOTAEditor;
begin
  Result := False;
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
  begin
    Editor := Module.ModuleFileEditors[Index];
    if (Editor <> nil) and Editor.Modified then
      Exit(True);
  end;
end;
{ The object a line belongs to: the nearest "object Name:" above it with less indentation. }
function OwnerName(const Lines: TArray<string>; Index: Integer): string;
var
  Indent, At: Integer;
  Match: TMatch;
begin
  Result := '';
  Indent := Length(Lines[Index]) - Length(TrimLeft(Lines[Index]));
  for At := Index - 1 downto 0 do
  begin
    Match := TRegEx.Match(Lines[At], '^(\s*)(?:object|inherited|inline)\s+(\w+)\s*:', [roIgnoreCase]);
    if Match.Success and (Length(Match.Groups[1].Value) < Indent) then
      Exit(Match.Groups[2].Value);
  end;
end;

{ New property lines must name a published property of the live component. }
function CheckProperties(Item: TFormFile; out Problem: string): Boolean;
var
  OldLines: TDictionary<string, Boolean>;
  Lines: TArray<string>;
  Index: Integer;
  Match: TMatch;
  Owner: TComponent;
  Line: string;
begin
  Result := True;
  Problem := '';
  OldLines := TDictionary<string, Boolean>.Create;
  try
    for Line in Item.Before.Split([#10]) do
      OldLines.AddOrSetValue(Trim(Line), True);
    Lines := Item.After.Split([#10]);
    for Index := 0 to High(Lines) do
    begin
      if OldLines.ContainsKey(Trim(Lines[Index])) then
        Continue;
      Match := TRegEx.Match(Lines[Index], '^\s*([A-Za-z_]\w*)(?:\.\w+)*\s*=');
      if not Match.Success then
        Continue;
      Owner := FindNative(Item.Editor, OwnerName(Lines, Index));
      if Owner = nil then
        Continue;
      { Left/Top of a non-visual component are its icon position (DesignInfo), not a property. }
      if (SameText(Match.Groups[1].Value, 'Left') or SameText(Match.Groups[1].Value, 'Top')) and
        IsNonVisual(RootOf(Item.Editor), Owner) then
        Continue;
      if GetPropInfo(Owner, Match.Groups[1].Value) = nil then
      begin
        Problem := Format('%s: %s has no property %s', [ExtractFileName(Item.FormPath), Owner.Name,
          Match.Groups[1].Value]);
        Exit(False);
      end;
    end;
  finally
    OldLines.Free;
  end;
end;

function ValidText(const Text: string): Boolean;
var
  Source, Target: TStringStream;
begin
  Source := TStringStream.Create(Text, TEncoding.UTF8);
  Target := TStringStream.Create('');
  try
    try
      ObjectTextToBinary(Source, Target);
      Result := True;
    except
      Result := False;
    end;
  finally
    Target.Free;
    Source.Free;
  end;
end;

function Prepare(const Edits: TJSONArray; Files: TObjectList<TFormFile>; out Problem: string): Boolean;
var
  Edit: TJSONValue;
  Path, OldText, NewText: string;
  Item: TFormFile;
  Found: TFormFile;
  At: Integer;
  Bytes: TBytes;
begin
  Result := False;
  for Edit in Edits do
  begin
    Path := FormFileOf(ProjectPath(Edit.GetValue<string>('path', '')));
    OldText := Edit.GetValue<string>('old', '');
    NewText := Edit.GetValue<string>('new', '');
    if not FileExists(Path) then
    begin
      Problem := 'Form file not found: ' + Path;
      Exit;
    end;
    Found := nil;
    for Item in Files do
      if SameText(Item.FormPath, Path) then
        Found := Item;
    if Found = nil then
    begin
      Found := TFormFile.Create;
      Files.Add(Found);
      Found.FormPath := Path;
      Found.UnitPath := UnitOf(Path);
      Found.Editor := FindFormEditor(Found.UnitPath, Problem);
      if Found.Editor = nil then
        Exit;
      Bytes := TFile.ReadAllBytes(Path);
      if (Length(Bytes) > 0) and (Bytes[0] = $FF) then
      begin
        Problem := ExtractFileName(Path) + ' is a binary form file; use the rad.form_* tools.';
        Exit;
      end;
      Found.Encoding := nil;
      TEncoding.GetBufferEncoding(Bytes, Found.Encoding, TEncoding.Default);
      Found.Before := Found.Encoding.GetString(Bytes, Length(Found.Encoding.GetPreamble),
        Length(Bytes) - Length(Found.Encoding.GetPreamble));
      Found.After := Found.Before;
    end;
    if (OldText = '') or StructureLine(OldText) or StructureLine(NewText) or
      TRegEx.IsMatch(OldText + #10 + NewText, '(?m)^\s*(object|inherited|inline)\s+\w*\s*:|^\s*end\s*$',
      [roIgnoreCase]) then
    begin
      Problem := 'Only property text may change; add, remove or rename components with rad.form_apply.';
      Exit;
    end;
    At := Found.After.IndexOf(OldText);
    if (At < 0) or (Found.After.IndexOf(OldText, At + 1) >= 0) then
    begin
      Problem := Format('%s: old text must occur exactly once: %s', [ExtractFileName(Path), OldText]);
      Exit;
    end;
    Found.After := Found.After.Remove(At, Length(OldText)).Insert(At, NewText);
  end;
  for Item in Files do
  begin
    if not SameStructure(Item.Before, Item.After) then
    begin
      Problem := 'Only property text may change; add, remove or rename components with rad.form_apply.';
      Exit;
    end;
    if not ValidText(Item.After) then
    begin
      Problem := ExtractFileName(Item.FormPath) + ': the edited form text does not parse.';
      Exit;
    end;
    if not CheckProperties(Item, Problem) then
      Exit;
  end;
  Result := Files.Count > 0;
  if not Result then
    Problem := 'No edits.';
end;

function EditFormText(const ArgumentsJson: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Args: TJSONValue;
  Files: TObjectList<TFormFile>;
  Item: TFormFile;
  Problem, Before, After, Unsaved, Conflicts, CurText: string;
  Module: IOTAModule;
  Bytes: TBytes;
  CurEncoding: TEncoding;
  HasConflict: Boolean;
begin
  Result := False;
  Args := TJSONObject.ParseJSONValue(ArgumentsJson);
  Files := TObjectList<TFormFile>.Create;
  try
    if not ((Args is TJSONObject) and (TJSONObject(Args).GetValue('edits') is TJSONArray)) then
    begin
      ResultText := 'edits must be an array of {path, old, new}.';
      Exit;
    end;
    { The designer may hold changes the files do not have yet. }
    if not SaveProjectModules(ExcludeTrailingPathDelimiter(ActiveProjectDir), Unsaved) then
    begin
      if Unsaved <> '' then
        ResultText := 'Failed to save project modules before editing form text: ' + Unsaved
      else
        ResultText := 'Failed to save project modules before editing form text.';
      Exit;
    end;
    if not Prepare(TJSONArray(TJSONObject(Args).GetValue('edits')), Files, Problem) then
    begin
      if Problem = '' then
        Problem := 'Form file not found.';
      ResultText := Problem;
      Exit;
    end;
    Before := '';
    After := '';
    for Item in Files do
    begin
      Before := Before + '// ' + ExtractFileName(Item.FormPath) + sLineBreak + Item.Before + sLineBreak;
      After := After + '// ' + ExtractFileName(Item.FormPath) + sLineBreak + Item.After + sLineBreak;
    end;
    if (Approval = nil) or not Approval.ApproveChange(Files[0].FormPath, Before, After) then
    begin
      ResultText := SEditCancelled;
      Exit(True);
    end;
    { Re-check every file before writing anything: disk bytes decode to Item.Before
      and module has no unsaved edits. }
    Conflicts := '';
    for Item in Files do
    begin
      HasConflict := False;
      if not FileExists(Item.FormPath) then
        HasConflict := True
      else
      begin
        Bytes := TFile.ReadAllBytes(Item.FormPath);
        CurEncoding := nil;
        TEncoding.GetBufferEncoding(Bytes, CurEncoding, TEncoding.Default);
        CurText := CurEncoding.GetString(Bytes, Length(CurEncoding.GetPreamble),
          Length(Bytes) - Length(CurEncoding.GetPreamble));
        if CurText <> Item.Before then
          HasConflict := True;
      end;
      if not HasConflict then
      begin
        Module := (BorlandIDEServices as IOTAModuleServices).FindModule(Item.UnitPath);
        if (Module = nil) and (Item.Editor <> nil) then
          Module := Item.Editor.Module;
        if Module = nil then
          Module := (BorlandIDEServices as IOTAModuleServices).FindModule(Item.FormPath);
        if ModuleHasUnsavedEdits(Module) then
          HasConflict := True;
      end;
      if HasConflict then
      begin
        if Conflicts <> '' then
          Conflicts := Conflicts + ', ';
        Conflicts := Conflicts + ExtractFileName(Item.FormPath);
      end;
    end;
    if Conflicts <> '' then
    begin
      ResultText := Format('Form file(s) modified on disk or have unsaved edits (%s); please retry.', [Conflicts]);
      Exit;
    end;
    for Item in Files do
    begin
      TFile.WriteAllBytes(Item.FormPath, Item.Encoding.GetPreamble + Item.Encoding.GetBytes(Item.After));
      Module := (BorlandIDEServices as IOTAModuleServices).FindModule(Item.UnitPath);
      if Module <> nil then
        ReloadModule(Module);
    end;
    ResultText := Format('{"ok":true,"files":%d}', [Files.Count]);
    Result := True;
  finally
    Files.Free;
    Args.Free;
  end;
end;

end.
