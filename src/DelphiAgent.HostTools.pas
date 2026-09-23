unit DelphiAgent.HostTools;

{ rad.* host-tool dispatch. Buffer edits live in DelphiAgent.BufferEdits, debugger reads in
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

function DiffersFromDisk(const Path, Text: string): Boolean;
begin
  if (Path = '') or not FileExists(Path) then
    Exit(True);
  try
    Result := TFile.ReadAllText(Path, TEncoding.UTF8) <> Text;
  except
    Result := True;
  end;
end;

function ListDirtyJson: string;
var
  Items: TArray<TEditorText>;
  Root: TJSONArray;
  Obj: TJSONObject;
  Index: Integer;
begin
  Items := OpenEditorTexts;
  Root := TJSONArray.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if not Items[Index].Modified or
        not DiffersFromDisk(Items[Index].FileName, Items[Index].Text) then
        Continue;
      Obj := TJSONObject.Create;
      Obj.AddPair('path', Items[Index].FileName);
      Obj.AddPair('modified', TJSONTrue.Create);
      Obj.AddPair('lineCount', TJSONNumber.Create(LineCountOf(Items[Index].Text)));
      Root.AddElement(Obj);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

{ "12| text" per line: edits address lines by these numbers, so the model must not count. }
function NumberedLines(const Text: string): string;
var
  Lines: TArray<string>;
  Builder: TStringBuilder;
  Index: Integer;
begin
  Lines := Text.Replace(#13#10, #10).Split([#10]);
  { A final line break does not start another line. }
  if (Length(Lines) > 0) and (Lines[High(Lines)] = '') then
    SetLength(Lines, Length(Lines) - 1);
  Builder := TStringBuilder.Create;
  try
    for Index := 0 to High(Lines) do
      Builder.Append(Index + 1).Append('| ').Append(Lines[Index]).Append(#10);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function ReadBufferText(const Path: string; out Text, Problem: string): Boolean;
begin
  Text := '';
  Problem := '';
  Result := False;
  if Path = '' then
  begin
    Problem := 'path가 비어 있습니다.';
    Exit;
  end;
  Text := BufferText(Path);
  if Text = '' then
  begin
    Problem := '열린 버퍼가 없습니다.';
    Exit;
  end;
  Text := NumberedLines(Text);
  Result := True;
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

function EditsFrom(const ArgumentsJson: string): TArray<TBufferEdit>;
var
  Value, Item: TJSONValue;
  Obj: TJSONObject;
  Edit: TBufferEdit;
begin
  Result := nil;
  Value := TJSONObject.ParseJSONValue(ArgumentsJson);
  try
    if not (Value is TJSONObject) or not (TJSONObject(Value).GetValue('edits') is TJSONArray) then
      Exit;
    for Item in TJSONArray(TJSONObject(Value).GetValue('edits')) do
      if Item is TJSONObject then
      begin
        Obj := TJSONObject(Item);
        Edit.Path := Obj.GetValue<string>('path', '');
        Edit.Content := Obj.GetValue<string>('content', '');
        Edit.NewText := Obj.GetValue<string>('newText', '');
        Edit.StartLine := Obj.GetValue<Integer>('startLine', 0);
        Edit.EndLine := Obj.GetValue<Integer>('endLine', 0);
        Result := Result + [Edit];
      end;
  finally
    Value.Free;
  end;
end;

{ Approved-or-cancelled results; a cancel is not an error. }
procedure Outcome(Ok: Boolean; const OkText, Problem: string; out ResultText: string;
  out IsError: Boolean);
begin
  if Ok then
    ResultText := OkText
  else
    ResultText := Problem;
  IsError := not Ok and (Problem <> SEditCancelled);
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
  else if ToolName = ToolListDirty then
  begin
    ResultText := ListDirtyJson;
    IsError := False;
  end
  else if ToolName = ToolReadBuffer then
  begin
    if ReadBufferText(ArgText(ArgumentsJson, 'path'), ResultText, Problem) then
      IsError := False
    else
      ResultText := Problem;
  end
  else if ToolName = ToolApplyEdit then
  begin
    if ApplyEdit(ArgText(ArgumentsJson, 'path'), ArgText(ArgumentsJson, 'content'),
      ArgText(ArgumentsJson, 'newText'), ArgInt(ArgumentsJson, 'startLine'),
      ArgInt(ArgumentsJson, 'endLine'), Approval, Problem) then
    begin
      ResultText := '{"ok":true}';
      IsError := False;
    end
    else if Problem = SEditCancelled then
    begin
      ResultText := Problem;
      IsError := False;
    end
    else
      ResultText := Problem;
  end
  else if ToolName = ToolApplyEdits then
    Outcome(ApplyEdits(EditsFrom(ArgumentsJson), Approval, Problem), '{"ok":true}', Problem,
      ResultText, IsError)
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
