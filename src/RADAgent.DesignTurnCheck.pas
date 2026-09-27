unit RADAgent.DesignTurnCheck;

{ At the end of each turn, the forms whose files changed during it are checked against the
  project's DESIGN.md (RADAgent.DesignLint) and the chat shows the result, so a turn cannot end
  with an unchecked form or an unverified "0 findings". Nothing runs without DESIGN.md. Main
  thread only. }

interface

{ A prompt was sent: forms changed from now on belong to this turn. }
procedure DesignTurnStarted;
{ The turn ended: lint the changed forms and post one notice per form with findings. }
procedure DesignTurnEnded;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, ToolsAPI, RADAgent.IdeContext, RADAgent.DesignLint,
  RADAgent.ChatSession, RADAgent.RpcJson, RADAgent.Lang;

var
  GStarted: TDateTime;

procedure DesignTurnStarted;
begin
  { A turn may start several agent loops (retries, follow-ups): the first one counts. }
  if GStarted = 0 then
    GStarted := Now;
end;

function FormFile(const UnitFile: string): string;
begin
  Result := ChangeFileExt(UnitFile, '.fmx');
  if not FileExists(Result) then
    Result := ChangeFileExt(UnitFile, '.dfm');
  if not FileExists(Result) then
    Result := '';
end;

{ Units whose form file was written since the turn started. }
function ChangedFormUnits: TArray<string>;
var
  Project: IOTAProject;
  Info: IOTAModuleInfo;
  Index: Integer;
  Form: string;
begin
  Result := nil;
  Project := CurrentProject;
  if Project = nil then
    Exit;
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    Info := Project.GetModule(Index);
    if (Info = nil) or (Info.FormName = '') or (Info.FileName = '') then
      Continue;
    Form := FormFile(Info.FileName);
    if (Form <> '') and (TFile.GetLastWriteTime(Form) >= GStarted) then
      Result := Result + [Info.FileName];
  end;
end;

procedure DesignTurnEnded;
var
  Units: TArray<string>;
  UnitFile, ResultText, Summary: string;
  Obj: TJSONObject;
  Clean: Integer;
begin
  if (GStarted = 0) or (ActiveProjectDir = '') or
    not FileExists(IncludeTrailingPathDelimiter(ActiveProjectDir) + 'DESIGN.md') then
    Exit;
  Units := ChangedFormUnits;
  GStarted := 0;
  Clean := 0;
  for UnitFile in Units do
  begin
    if not DesignLint(UnitFile, ResultText) then
      Continue;
    Obj := JsonObject(ResultText);
    try
      Summary := JsonStr(Obj, 'summary');
      if (Obj <> nil) and (Obj.GetValue('findings') is TJSONArray) and
        (TJSONArray(Obj.GetValue('findings')).Count > 0) then
        ChatSession.Notice('warn', TrF('designturn.findings', [ExtractFileName(UnitFile), Summary]))
      else
        Inc(Clean);
    finally
      Obj.Free;
    end;
  end;
  if Clean > 0 then
    ChatSession.Notice('info', TrF('designturn.clean', [Clean]));
end;

end.
