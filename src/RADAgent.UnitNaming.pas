unit RADAgent.UnitNaming;

{ Names for new and renamed units and projects (rad.new_module, rad.rename_unit,
  rad.rename_project): required, descriptive, in the project's namespace, with a suffix that says
  what a unit holds. UnitN and ProjectN names are refused. Also rewrites uses clauses for a renamed
  unit. No ToolsAPI. }

interface

{ Kind: form, frame, datamodule or unit. Cpp: C++Builder file names (no dots). ProjectUnits: the
  project's other unit names; when most of them share a dotted root (App.), the new name must use
  it too. False with Problem (English, for the model) when the name breaks a rule. }
function CheckUnitName(const Kind, UnitName: string; Cpp: Boolean; const ProjectUnits: TArray<string>;
  out Problem: string): Boolean;
{ The last dotted part: the default component name of a form, frame or data module. }
function LastPart(const UnitName: string): string;
{ The dotted root most project units share ("Nanum"), or '' when there is none. }
function ProjectRoot(const ProjectUnits: TArray<string>): string;
{ Name: the new project name (file name without extension); Delphi program and C++ project names
  are plain identifiers. False with Problem when it breaks a rule. }
function CheckProjectName(const Name: string; out Problem: string): Boolean;
{ Source with every uses clause naming the unit OldUnit (the complete dotted name, any case) naming
  NewUnit instead. Other.OldUnit, comments, string literals and everything outside uses clauses
  stay as they are. }
function RenameInUses(const Source, OldUnit, NewUnit: string): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.RegularExpressions, System.Generics.Collections;

function LastPart(const UnitName: string): string;
begin
  Result := UnitName.Substring(UnitName.LastIndexOf('.') + 1);
end;

function ProjectRoot(const ProjectUnits: TArray<string>): string;
var
  Counts: TDictionary<string, Integer>;
  Name, Root: string;
  Count, Best: Integer;
begin
  Result := '';
  Counts := TDictionary<string, Integer>.Create;
  try
    for Name in ProjectUnits do
      if Name.Contains('.') then
      begin
        Root := Name.Substring(0, Name.IndexOf('.'));
        Counts.TryGetValue(LowerCase(Root), Count);
        Counts.AddOrSetValue(LowerCase(Root), Count + 1);
      end;
    Best := 0;
    for Name in ProjectUnits do
      if Name.Contains('.') then
      begin
        Root := Name.Substring(0, Name.IndexOf('.'));
        Count := Counts[LowerCase(Root)];
        if Count > Best then
        begin
          Best := Count;
          Result := Root;
        end;
      end;
    { A root counts only when it is what most units use. }
    if Best * 2 <= Length(ProjectUnits) then
      Result := '';
  finally
    Counts.Free;
  end;
end;

function RequiredSuffix(const Kind: string): string;
begin
  if SameText(Kind, 'form') then
    Result := 'Form or Dialog'
  else if SameText(Kind, 'frame') then
    Result := 'Frame'
  else if SameText(Kind, 'datamodule') then
    Result := 'DataModule'
  else
    Result := '';
end;

function HasSuffix(const Kind, Last: string): Boolean;
begin
  if SameText(Kind, 'form') then
    Result := EndsText('Form', Last) or EndsText('Dialog', Last)
  else if SameText(Kind, 'frame') then
    Result := EndsText('Frame', Last)
  else if SameText(Kind, 'datamodule') then
    Result := EndsText('DataModule', Last)
  else
    Result := True;
end;

function CheckUnitName(const Kind, UnitName: string; Cpp: Boolean; const ProjectUnits: TArray<string>;
  out Problem: string): Boolean;
var
  Root, Last, Example: string;
begin
  Result := False;
  Problem := '';
  Root := ProjectRoot(ProjectUnits);
  Last := LastPart(UnitName);
  if Root <> '' then
    Example := Root + '.UI.ExportDialog'
  else
    Example := 'ExportDialog';
  if UnitName = '' then
    Problem := 'A unit name is required, e.g. ' + Example + '.'
  else if not IsValidIdent(UnitName, not Cpp) then
    Problem := 'Not a valid unit name: ' + UnitName + IfThen(Cpp, ' (C++Builder file names have no dots)', '')
  else if TRegEx.IsMatch(Last, '^(Unit|Form|Frame|DataModule)\d*$', [roIgnoreCase]) then
    Problem := 'Give the unit a name that says what it is for, not ' + Last + ', e.g. ' + Example + '.'
  else if not HasSuffix(Kind, Last) then
    Problem := 'A ' + LowerCase(Kind) + ' unit name ends in ' + RequiredSuffix(Kind) + ': ' + UnitName +
      ' (e.g. ' + Example + ').'
  else if not Cpp and (Root <> '') and not StartsText(Root + '.', UnitName) then
    Problem := 'The project''s units live under ' + Root + '.; use it: ' + Root + '.' + UnitName + '.'
  else
    Result := True;
end;

function CheckProjectName(const Name: string; out Problem: string): Boolean;
begin
  Result := False;
  if Name = '' then
    Problem := 'A project name is required, e.g. CsvViewer.'
  else if not IsValidIdent(Name) then
    Problem := 'Not a valid project name (a plain identifier, no dots or spaces): ' + Name
  else if TRegEx.IsMatch(Name, '^Project\d*$', [roIgnoreCase]) then
    Problem := 'Give the project a name that says what it is, not ' + Name + '.'
  else
    Result := True;
end;

function RenameInUses(const Source, OldUnit, NewUnit: string): string;
var
  Builder: TStringBuilder;
  I, Len, Start, Done: Integer;
  InUses, AfterDot: Boolean;
  Word: string;

  function IsIdentStart(C: Char): Boolean;
  begin
    Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
  end;

  function IsIdentChar(C: Char): Boolean;
  begin
    Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '0'..'9']);
  end;

begin
  Builder := TStringBuilder.Create;
  try
    Len := Length(Source);
    I := 1;
    Done := 1;
    InUses := False;
    AfterDot := False;
    while I <= Len do
    begin
      if Source[I] = '{' then
      begin
        while (I <= Len) and (Source[I] <> '}') do
          Inc(I);
        Inc(I);
      end
      else if (Source[I] = '(') and (I < Len) and (Source[I + 1] = '*') then
      begin
        Inc(I, 2);
        while (I < Len) and not ((Source[I] = '*') and (Source[I + 1] = ')')) do
          Inc(I);
        Inc(I, 2);
      end
      else if (Source[I] = '/') and (I < Len) and (Source[I + 1] = '/') then
      begin
        while (I <= Len) and not CharInSet(Source[I], [#10, #13]) do
          Inc(I);
      end
      else if Source[I] = '''' then
      begin
        Inc(I);
        while (I <= Len) and ((Source[I] <> '''') or ((I < Len) and (Source[I + 1] = ''''))) do
          if Source[I] = '''' then
            Inc(I, 2)
          else
            Inc(I);
        Inc(I);
      end
      else if IsIdentStart(Source[I]) then
      begin
        { A whole dotted name: Nanum.UI.MainForm, never the Unit2 in Other.Unit2. }
        Start := I;
        repeat
          while (I <= Len) and IsIdentChar(Source[I]) do
            Inc(I);
          if (I < Len) and (Source[I] = '.') and IsIdentStart(Source[I + 1]) then
            Inc(I)
          else
            Break;
        until False;
        Word := Copy(Source, Start, I - Start);
        if not AfterDot and SameText(Word, 'uses') then
          InUses := True
        else if InUses and SameText(Word, OldUnit) then
        begin
          Builder.Append(Source, Done - 1, Start - Done).Append(NewUnit);
          Done := I;
        end;
        AfterDot := False;
      end
      else
      begin
        if Source[I] = ';' then
          InUses := False;
        if not CharInSet(Source[I], [' ', #9, #10, #13]) then
          AfterDot := Source[I] = '.';
        Inc(I);
      end;
    end;
    Builder.Append(Source, Done - 1, Len - Done + 1);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
