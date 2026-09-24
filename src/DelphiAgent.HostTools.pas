unit DelphiAgent.HostTools;

{ rad.* host-tool dispatch. Caret insertion lives in DelphiAgent.BufferEdits, debugger reads in
  DelphiAgent.DebugTools, debugger control in DelphiAgent.DebugControl, form designer tools in
  DelphiAgent.FormTools. }

interface

uses
  DelphiAgent.Approval;

procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  DelphiAgent.IdeContext, DelphiAgent.Compile, DelphiAgent.BufferEdits,
  DelphiAgent.HostToolDefs, DelphiAgent.DebugTools, DelphiAgent.DebugControl,
  DelphiAgent.FormEdits, DelphiAgent.FormTools, DelphiAgent.ProjectProfile,
  DelphiAgent.ModuleCreator, DelphiAgent.ChatPlan;

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
    Problem := 'file이 비어 있습니다.';
    Exit;
  end;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.OpenModule(FileName);
  if Module = nil then
  begin
    Problem := '파일을 열지 못했습니다.';
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
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);
var
  Problem: string;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  ResultText := '';
  IsError := True;
  if ToolName = ToolCompile then
  begin
    if CurrentProject = nil then
    begin
      ResultText := '{"ok":false,"error":"프로젝트 없음"}';
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
  else if IsFormTool(ToolName) then
    ExecuteFormTool(ToolName, FormArgs(ArgumentsJson), ArgumentsJson, Approval, ResultText, IsError)
  else
    ResultText := 'unknown host tool';
end;

end.
