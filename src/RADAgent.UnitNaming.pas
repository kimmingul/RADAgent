unit RADAgent.UnitNaming;

{ Names for new and renamed units (rad.new_module, rad.rename_unit): required, descriptive, in the
  project's namespace, with a suffix that says what the unit holds. UnitN names are refused. No
  ToolsAPI. }

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

end.
