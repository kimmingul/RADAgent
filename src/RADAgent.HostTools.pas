unit RADAgent.HostTools;

{ rad.* host-tool dispatch. Caret insertion lives in RADAgent.BufferEdits, debugger reads in
  RADAgent.DebugTools, debugger control in RADAgent.DebugControl, form designer tools in
  RADAgent.FormTools. }

interface

uses
  RADAgent.Approval;

{ ImagePng: base64 PNG sent with the result (rad.form_screenshot), else ''. }
procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean; out ImagePng: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  RADAgent.IdeContext, RADAgent.Compile, RADAgent.BufferEdits,
  RADAgent.HostToolDefs, RADAgent.DebugTools, RADAgent.DebugControl,
  RADAgent.FormEdits, RADAgent.FormTools, RADAgent.ProjectProfile,
  RADAgent.ModuleCreator, RADAgent.ChatPlan, RADAgent.FormShot, RADAgent.FormText,
  RADAgent.AgentSettings;

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
    if Obj.GetValue(Name) is TJSONString then
      Result := TJSONString(Obj.GetValue(Name)).Value;
  finally
    Obj.Free;
  end;
end;

function OpenBuffer(const FileName: string; out Problem: string): Boolean;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
begin
  Result := False;
  Problem := '';
  if FileName = '' then
  begin
    Problem := 'File name cannot be empty.';
    Exit;
  end;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.OpenModule(FileName);
  if Module = nil then
  begin
    Problem := 'Failed to open file.';
    Exit;
  end;
  Module.ShowFilename(FileName);
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
  Result.Line := ArgInt(ArgumentsJson, 'line');
end;

procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean; out ImagePng: string);
var
  Problem: string;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  ResultText := '';
  ImagePng := '';
  IsError := True;
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
    IsError := not NewModule(ArgText(ArgumentsJson, 'kind'), ArgText(ArgumentsJson, 'name'),
      Approval, ResultText)
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

end.
