unit DelphiAgent.HostTools;

{ rad.* host tools. Buffer edits wait for approval. Debugger tools live in DelphiAgent.DebugTools. }

interface

type
  IAgentApproval = interface
    ['{B1C2A8E4-7F0D-4C3A-9E21-6D5A4B3C2D10}']
    function ApproveBufferChange(const FileName, Preview: string): Boolean;
    procedure ShowConflict(const FileName: string);
  end;

procedure ExecuteHostTool(const ToolName, ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  DelphiAgent.IdeContext, DelphiAgent.DirtyBuffers, DelphiAgent.Compile,
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

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  Services: IOTAEditorServices;
  View: IOTAEditView;
  Current: TEditorText;
begin
  Result := False;
  Problem := '';
  if Text = '' then
  begin
    Problem := 'text가 비어 있습니다.';
    Exit;
  end;
  Services := BorlandIDEServices as IOTAEditorServices;
  View := Services.TopView;
  if (View = nil) or (View.Position = nil) or (View.Buffer = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  Current := CurrentEditorText;
  if SnapshotConflicts(Current.FileName, Current.Text) then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Current.FileName);
    Problem := '충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다.';
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveBufferChange(Current.FileName, Text) then
  begin
    Problem := '사용자가 버퍼 반영을 승인하지 않았습니다.';
    Exit;
  end;
  if SnapshotConflicts(Current.FileName, BufferText(Current.FileName)) then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Current.FileName);
    Problem := '충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다.';
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  View.Position.InsertText(Text);
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

function LineCountOf(const Text: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if Text = '' then
    Exit;
  Result := 1;
  for Index := 1 to Length(Text) do
    if Text[Index] = #10 then
      Inc(Result);
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
  Items := DirtyEditorTexts;
  Root := TJSONArray.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if not DiffersFromDisk(Items[Index].FileName, Items[Index].Text) then
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

function FindSource(const Path: string): IOTASourceEditor;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
begin
  Result := nil;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.FindModule(Path);
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Result) and
      SameText(Result.FileName, Path) then
      Exit;
  Result := nil;
end;

function LineByte(const Text: string; LineNo: Integer): Integer;
var
  Line, Index: Integer;
begin
  if LineNo <= 1 then
    Exit(0);
  Line := 1;
  Index := 1;
  while (Index <= Length(Text)) and (Line < LineNo) do
  begin
    if Text[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetByteCount(Copy(Text, 1, Index - 1));
end;

function ApplyEdit(const ArgumentsJson: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  Path, Content, NewText, Current, Preview: string;
  StartLine, EndLine, StartPos, EndPos: Integer;
  Source: IOTASourceEditor;
  Writer: IOTAEditWriter;
  Bytes: TBytes;
begin
  Result := False;
  Problem := '';
  Path := ArgText(ArgumentsJson, 'path');
  Content := ArgText(ArgumentsJson, 'content');
  NewText := ArgText(ArgumentsJson, 'newText');
  StartLine := ArgInt(ArgumentsJson, 'startLine');
  EndLine := ArgInt(ArgumentsJson, 'endLine');
  Source := FindSource(Path);
  if Source = nil then
  begin
    Problem := '열린 버퍼가 없습니다.';
    Exit;
  end;
  Current := BufferText(Path);
  if Content <> '' then
    Preview := Content
  else if (StartLine > 0) and (EndLine >= StartLine) then
    Preview := NewText
  else
  begin
    Problem := 'content 또는 줄 범위가 없습니다.';
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveBufferChange(Path, Preview) then
  begin
    Problem := '{"ok":false,"cancelled":true}';
    Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(Preview + #0);
  Writer := Source.CreateUndoableWriter;
  try
    if Content <> '' then
      Writer.Insert(PAnsiChar(Bytes))
    else
    begin
      StartPos := LineByte(Current, StartLine);
      EndPos := LineByte(Current, EndLine + 1);
      Writer.CopyTo(StartPos);
      Writer.DeleteTo(EndPos);
      Writer.Insert(PAnsiChar(Bytes));
    end;
  finally
    Writer := nil;
  end;
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
    if ApplyEdit(ArgumentsJson, Approval, Problem) then
    begin
      ResultText := '{"ok":true}';
      IsError := False;
    end
    else if Problem = '{"ok":false,"cancelled":true}' then
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
