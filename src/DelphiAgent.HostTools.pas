unit DelphiAgent.HostTools;

{ rad.* host-tool dispatch. Buffer edits live in DelphiAgent.BufferEdits, debugger tools in DelphiAgent.DebugTools. }

interface

uses
  DelphiAgent.BufferEdits;

procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  DelphiAgent.IdeContext, DelphiAgent.Compile,
  DelphiAgent.HostToolDefs, DelphiAgent.DebugTools;

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
    Problem := '열린 버퍼가 없습니다.'
  else
    Result := True;
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
  else
    ResultText := 'unknown host tool';
end;

end.
