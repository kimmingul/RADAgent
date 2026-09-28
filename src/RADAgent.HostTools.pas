unit RADAgent.HostTools;

{ rad.* host-tool dispatch. Caret insertion lives in RADAgent.BufferEdits, debugger reads in
  RADAgent.DebugTools, debugger control in RADAgent.DebugControl, form designer tools in
  RADAgent.FormTools. }

interface

uses
  RADAgent.Approval;

{ ImagePng: base64 PNG sent with the result (rad.form_screenshot), else ''. An exception from
  the IDE becomes an error result: an error dialog would leave the call (and the turn) waiting. }
procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean; out ImagePng: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  RADAgent.IdeContext, RADAgent.Compile, RADAgent.BufferEdits,
  RADAgent.HostToolDefs, RADAgent.DebugTools, RADAgent.DebugControl,
  RADAgent.FormEdits, RADAgent.FormTools, RADAgent.ProjectProfile,
  RADAgent.ModuleCreator, RADAgent.ChatPlan, RADAgent.FormShot, RADAgent.FormText,
  RADAgent.AgentSettings, RADAgent.UnitRename, RADAgent.DesignInit, RADAgent.DesignLint,
  RADAgent.DesignIcons, RADAgent.AppShot, RADAgent.Lang, RADAgent.HostToolArgs;

function ArgText(const ArgumentsJson, Name: string): string;
var
  Value: TJSONValue;
  Obj: TJSONObject;
begin
  Result := '';
  Value := TJSONObject.ParseJSONValue(ArgumentsJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Obj := TJSONObject(Value);
  try
    { A number or boolean where the schema says string (value 120, applyStyle false) keeps its text. }
    if (Obj.GetValue(Name) is TJSONString) or (Obj.GetValue(Name) is TJSONNumber) or
      (Obj.GetValue(Name) is TJSONBool) then
      Result := Obj.GetValue(Name).Value;
  finally
    Obj.Free;
  end;
end;

{ FileName may be relative to the project or use forward slashes (ProjectPath). }
function OpenBuffer(const FileName: string; out Problem: string): Boolean;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  FullPath: string;
begin
  Result := False;
  Problem := '';
  if FileName = '' then
  begin
    Problem := 'File name cannot be empty.';
    Exit;
  end;
  FullPath := ProjectPath(FileName);
  if not FileExists(FullPath) then
  begin
    Problem := 'File not found: ' + FullPath;
    Exit;
  end;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.OpenModule(FullPath);
  if Module = nil then
  begin
    Problem := 'Failed to open file.';
    Exit;
  end;
  Module.ShowFilename(FullPath);
  Result := True;
end;

function ArgInt(const ArgumentsJson, Name: string): Integer;
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Text: string;
begin
  Result := 0;
  Value := TJSONObject.ParseJSONValue(ArgumentsJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Obj := TJSONObject(Value);
  try
    if Obj.GetValue(Name) is TJSONNumber then
      Result := TJSONNumber(Obj.GetValue(Name)).AsInt
    else
    begin
      Text := '';
      if Obj.GetValue(Name) is TJSONString then
        Text := TJSONString(Obj.GetValue(Name)).Value;
      Result := StrToIntDef(Text, 0);
    end;
  finally
    Obj.Free;
  end;
end;

function FormArgs(const ArgumentsJson: string): TFormToolArgs;
begin
  Result.Path := ArgText(ArgumentsJson, 'path');
  Result.Component := ArgText(ArgumentsJson, 'component');
  Result.PropName := ArgText(ArgumentsJson, 'property');
  Result.Value := ArgText(ArgumentsJson, 'value');
  Result.ClassName := ArgText(ArgumentsJson, 'class');
  Result.Name := ArgText(ArgumentsJson, 'name');
  Result.Parent := ArgText(ArgumentsJson, 'parent');
  Result.Left := ArgInt(ArgumentsJson, 'left');
  Result.Top := ArgInt(ArgumentsJson, 'top');
  Result.NewName := ArgText(ArgumentsJson, 'newName');
  Result.Event := ArgText(ArgumentsJson, 'event');
  Result.Handler := ArgText(ArgumentsJson, 'handler');
end;

function DebugControlArgs(const ArgumentsJson: string): TDebugControlArgs;
begin
  Result.Mode := ArgText(ArgumentsJson, 'mode');
  Result.FileName := ArgText(ArgumentsJson, 'file');
  if Result.FileName <> '' then
    Result.FileName := ProjectPath(Result.FileName);
  Result.Line := ArgInt(ArgumentsJson, 'line');
end;

{ rad.app_screenshot: after approval run the built program, capture its window, close it. }
function RunAppScreenshot(const ArgumentsJson: string; const Approval: IAgentApproval;
  out ResultText, ImagePng: string): Boolean;
var
  Exe, Problem: string;
begin
  Result := False;
  ImagePng := '';
  if not ProjectExecutable(Exe, Problem) then
  begin
    ResultText := Problem;
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveChange(Exe, '', TrF('hosttools.appScreenshot',
    [ExtractFileName(Exe), ArgText(ArgumentsJson, 'args')])) then
  begin
    ResultText := SEditCancelled;
    Exit(True);
  end;
  Result := AppScreenshot(Exe, ArgText(ArgumentsJson, 'args'), ArgText(ArgumentsJson, 'window'),
    ArgInt(ArgumentsJson, 'waitMs'), ExcludeTrailingPathDelimiter(ActiveProjectDir), ImagePng, ResultText);
end;

procedure DispatchHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean; out ImagePng: string);
var
  Problem: string;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  ResultText := '';
  ImagePng := '';
  IsError := True;
  if not CheckHostToolArgs(ToolName, ArgumentsJson, Problem) then
  begin
    ResultText := Problem;
    Exit;
  end;
  if ToolName = ToolCompile then
  begin
    if CurrentProject = nil then
    begin
      ResultText := '{"ok":false,"error":"No active project."}';
      IsError := True;
    end
    else
    begin
      ResultText := BuildActiveProjectJson;
      IsError := not ResultText.Contains('"ok":true');
    end;
  end
  else if ToolName = ToolSubmitPlan then
    IsError := not SubmitPlan(ArgumentsJson, ResultText)
  else if ToolName = ToolProjectInfo then
  begin
    ResultText := ProjectInfoJson;
    IsError := ResultText.Contains('"ok":false');
  end
  else if ToolName = ToolSetBuildConfig then
    IsError := not SetBuildConfig(ArgText(ArgumentsJson, 'config'), ArgText(ArgumentsJson, 'platform'),
      Approval, ResultText)
  else if ToolName = ToolNewModule then
    IsError := not NewModule(ArgText(ArgumentsJson, 'kind'), ArgText(ArgumentsJson, 'unit'),
      ArgText(ArgumentsJson, 'name'), Approval, ResultText)
  else if ToolName = ToolRenameUnit then
    IsError := not RenameUnit(ArgText(ArgumentsJson, 'path'), ArgText(ArgumentsJson, 'unit'), Approval,
      ResultText)
  else if ToolName = ToolRenameProject then
    IsError := not RenameProject(ArgText(ArgumentsJson, 'name'), Approval, ResultText)
  else if ToolName = ToolDesignStyles then
  begin
    ResultText := DesignStylesJson;
    IsError := ResultText.Contains('"ok":false');
  end
  else if ToolName = ToolDesignInit then
    IsError := not InitDesignTool(ArgText(ArgumentsJson, 'style'), ArgText(ArgumentsJson, 'preset'),
      ArgText(ArgumentsJson, 'applyStyle'), Approval, ResultText)
  else if ToolName = ToolDesignLint then
    IsError := not DesignLint(ArgText(ArgumentsJson, 'path'), ResultText)
  else if ToolName = ToolDesignIcons then
  begin
    ResultText := DesignIconsJson(ArgText(ArgumentsJson, 'query'));
    IsError := ResultText.Contains('"ok":false');
  end
  else if ToolName = ToolStyleLookups then
  begin
    ResultText := ProjectStyleLookups(ArgText(ArgumentsJson, 'style'), ArgText(ArgumentsJson, 'filter'));
    IsError := ResultText.Contains('"ok":false');
  end
  else if ToolName = ToolAppScreenshot then
    IsError := not RunAppScreenshot(ArgumentsJson, Approval, ResultText, ImagePng)
  else if ToolName = ToolListComponents then
  begin
    ResultText := ComponentsJson(ArgText(ArgumentsJson, 'filter'));
    IsError := False;
  end
  else if ToolName = ToolOpenBuffer then
  begin
    if OpenBuffer(ArgText(ArgumentsJson, 'file'), Problem) then
    begin
      ResultText := 'opened';
      IsError := False;
    end
    else
      ResultText := Problem;
  end
  else if ToolName = ToolInsertAtCaret then
  begin
    if InsertAtCaret(ArgText(ArgumentsJson, 'text'), Approval, Problem) then
    begin
      ResultText := 'inserted';
      IsError := False;
    end
    else
      ResultText := Problem;
  end
  else if IsDebugTool(ToolName) then
    ExecuteDebugTool(ToolName, ArgText(ArgumentsJson, 'expression'), ResultText, IsError)
  else if IsDebugControlTool(ToolName) then
    ExecuteDebugControl(ToolName, DebugControlArgs(ArgumentsJson), Approval, ResultText, IsError)
  else if ToolName = ToolFormScreenshot then
    IsError := not FormScreenshot(ArgText(ArgumentsJson, 'path'), ImagePng, ResultText)
  else if ToolName = ToolFormTextEdit then
  begin
    if FormTextAllowed(ExcludeTrailingPathDelimiter(ActiveProjectDir)) then
      IsError := not EditFormText(ArgumentsJson, Approval, ResultText)
    else
      ResultText := 'This project edits forms in the designer only; use rad.form_apply.';
  end
  else if IsFormTool(ToolName) then
    ExecuteFormTool(ToolName, FormArgs(ArgumentsJson), ArgumentsJson, Approval, ResultText, IsError)
  else
    ResultText := 'unknown host tool';
end;

procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean; out ImagePng: string);
begin
  try
    DispatchHostTool(ToolName, ArgumentsJson, Approval, ResultText, IsError, ImagePng);
  except
    on E: Exception do
    begin
      ResultText := Format('The IDE raised %s: %s. Changes made before the error (if any) stay; check ' +
        'with the read tools before retrying.', [E.ClassName, E.Message]);
      IsError := True;
      ImagePng := '';
    end;
  end;
end;

end.
