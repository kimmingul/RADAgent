unit RADAgent.ChatPlan;

{ RADAgent's own plan mode, chosen from the approval menu. omp restarts with
  --approval-mode always-ask so its disk tools ask (and RADAgent denies them), only read-only
  rad.* tools plus rad.submit_plan are registered, and the plan becomes
  <project>\docs\plans\<yyyy-mm-dd-hhnn>-<slug>.md, added to the project and shown as a card
  with "proceed" and "revise". Main thread only. }

interface

function PlanActive: Boolean;
{ Enter plan mode; PreviousMode is the approval mode to go back to. Restarts omp. }
procedure EnterPlanMode(const PreviousMode: string);
{ Leave plan mode for Mode. Restarts omp; FollowUp (if any) is sent once history is back. }
procedure LeavePlanMode(const Mode, FollowUp: string);
{ The approval mode that plan mode returns to. }
function PlanReturnMode: string;
{ rad.submit_plan: writes the document, adds it to the project, shows the card. }
function SubmitPlan(const ArgumentsJson: string; out ResultText: string): Boolean;
{ Card button: leave plan mode and implement the plan file. }
procedure ProceedWithPlan(const Path: string);
{ Prompt sent after a restart, once; '' when none. }
function TakeFollowUp: string;
{ Adds every file under <project>\docs to the project so the Project Manager shows it. }
procedure AddDocsToProject;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, ToolsAPI, RADAgent.ChatSession,
  RADAgent.IdeContext, RADAgent.Lang;

var
  GActive: Boolean;
  GReturnMode: string = 'yolo';
  GFollowUp: string;

function PlanActive: Boolean;
begin
  Result := GActive;
end;

function PlanReturnMode: string;
begin
  Result := GReturnMode;
end;

function TakeFollowUp: string;
begin
  Result := GFollowUp;
  GFollowUp := '';
end;

procedure EnterPlanMode(const PreviousMode: string);
begin
  if GActive then
    Exit;
  GActive := True;
  if PreviousMode <> '' then
    GReturnMode := PreviousMode;
  AddDocsToProject;
  ChatSession.Notice('info', Tr('chatplan.enterNotice'));
  ChatSession.RestartWhenIdle;
end;

procedure LeavePlanMode(const Mode, FollowUp: string);
begin
  GActive := False;
  GFollowUp := FollowUp;
  if Mode <> '' then
    GReturnMode := Mode;
  ChatSession.RestartWhenIdle;
end;

function Slug(const Text: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in LowerCase(Text) do
    if CharInSet(Ch, ['a'..'z', '0'..'9']) then
      Result := Result + Ch
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  Result := Copy(Result.Trim(['-']), 1, 48);
  if Result = '' then
    Result := 'plan';
end;

function Items(Obj: TJSONObject; const Name: string): TArray<string>;
var
  Value: TJSONValue;
begin
  Result := nil;
  if Obj.GetValue(Name) is TJSONArray then
    for Value in TJSONArray(Obj.GetValue(Name)) do
      Result := Result + [Value.Value];
end;

procedure AddList(Lines: TStrings; const Heading: string; const Values: TArray<string>; Numbered: Boolean);
var
  Index: Integer;
begin
  Lines.Add('');
  Lines.Add('## ' + Heading);
  Lines.Add('');
  if Length(Values) = 0 then
    Lines.Add('- ' + Tr('chatplan.none'));
  for Index := 0 to High(Values) do
    if Numbered then
      Lines.Add(Format('%d. %s', [Index + 1, Values[Index]]))
    else
      Lines.Add('- ' + Values[Index]);
end;

procedure AddToProject(const Path: string);
var
  Project: IOTAProject;
  Index: Integer;
begin
  Project := CurrentProject;
  if Project = nil then
    Exit;
  for Index := 0 to Project.GetModuleCount - 1 do
    if SameText(Project.GetModule(Index).FileName, Path) then
      Exit;
  { Shows the plan under the project in the Project Manager; the project is not saved. }
  Project.AddFile(Path, False);
end;

procedure AddDocsToProject;
var
  Dir, Path: string;
begin
  Dir := TPath.Combine(ExcludeTrailingPathDelimiter(ActiveProjectDir), 'docs');
  if (ActiveProjectDir = '') or not DirectoryExists(Dir) then
    Exit;
  for Path in TDirectory.GetFiles(Dir, '*', TSearchOption.soAllDirectories) do
    AddToProject(Path);
end;

function CardJson(const Path, Title: string; const Steps: TArray<string>): string;
var
  Obj: TJSONObject;
  List: TJSONArray;
  Step: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'plan');
    Obj.AddPair('path', Path);
    Obj.AddPair('name', ExtractFileName(Path));
    Obj.AddPair('title', Title);
    List := TJSONArray.Create;
    for Step in Steps do
      List.Add(Step);
    Obj.AddPair('steps', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function SubmitPlan(const ArgumentsJson: string; out ResultText: string): Boolean;
var
  Value: TJSONValue;
  Args: TJSONObject;
  Lines: TStringList;
  Dir, Path, Title: string;
  Steps: TArray<string>;
begin
  Result := False;
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
  begin
    ResultText := 'No active project.';
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(ArgumentsJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    ResultText := 'Arguments must be a JSON object.';
    Exit;
  end;
  Args := TJSONObject(Value);
  Lines := TStringList.Create;
  try
    Title := Args.GetValue<string>('title', Tr('chatplan.defaultTitle'));
    Steps := Items(Args, 'steps');
    if Length(Steps) = 0 then
    begin
      ResultText := 'steps is empty.';
      Exit;
    end;
    Path := TPath.Combine(Dir, 'docs\plans\' + FormatDateTime('yyyy-mm-dd-hhnn', Now) + '-' +
      Slug(Args.GetValue<string>('slug', Title)) + '.md');
    Lines.Add('# ' + Title);
    Lines.Add('');
    Lines.Add(TrF('chatplan.created', [FormatDateTime('yyyy-mm-dd hh:nn', Now)]));
    Lines.Add(TrF('chatplan.project', [ExtractFileName(ActiveProjectFile)]));
    Lines.Add(Tr('chatplan.statusPending'));
    Lines.Add('');
    Lines.Add('## ' + Tr('chatplan.goal'));
    Lines.Add('');
    Lines.Add(Args.GetValue<string>('goal', ''));
    Lines.Add('');
    Lines.Add('## ' + Tr('chatplan.context'));
    Lines.Add('');
    Lines.Add(Args.GetValue<string>('context', ''));
    AddList(Lines, Tr('chatplan.steps'), Steps, True);
    AddList(Lines, Tr('chatplan.files'), Items(Args, 'files'), False);
    AddList(Lines, Tr('chatplan.risks'), Items(Args, 'risks'), False);
    AddList(Lines, Tr('chatplan.verification'), Items(Args, 'verification'), False);
    ForceDirectories(ExtractFileDir(Path));
    TFile.WriteAllText(Path, Lines.Text, TEncoding.UTF8);
    AddDocsToProject;
    ChatSession.Emit(CardJson(Path, Title, Steps));
    ResultText := Format('{"ok":true,"file":"%s","status":"Waiting for user review. Stop here and await reply."}',
      [StringReplace(Path, '\', '\\', [rfReplaceAll])]);
    Result := True;
  finally
    Lines.Free;
    Args.Free;
  end;
end;

procedure ProceedWithPlan(const Path: string);
var
  Relative: string;
begin
  Relative := ExtractRelativePath(IncludeTrailingPathDelimiter(ActiveProjectDir), Path);
  ChatSession.Notice('info', TrF('chatplan.implementNotice', [Relative]));
  LeavePlanMode(GReturnMode, TrF('chatplan.proceedPrompt', [Relative]));
end;

end.
