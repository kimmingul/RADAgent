unit DelphiAgent.RpcProtocol;

{ JSONL frames for omp --mode rpc v1. No ToolsAPI. }

interface

uses
  System.SysUtils;

const
  MaxFrameBytes = 1048576;
  ToolCompile = 'rad.compile';
  ToolOpenBuffer = 'rad.open_buffer';
  ToolInsertAtCaret = 'rad.insert_at_caret';
  ToolListDirty = 'rad.list_dirty';
  ToolReadBuffer = 'rad.read_buffer';
  ToolApplyEdit = 'rad.apply_edit';

type
  TAgentCompileError = record
    FileName: string;
    Line: Integer;
    Col: Integer;
    Msg: string;
  end;

function AcceptFrameLine(const Line: string): Boolean;
function FrameTypeOf(const Line: string): string;
function IsReadyFrame(const Line: string): Boolean;
function CanSendPrompt(Ready, HostToolsSent: Boolean; const Message: string): Boolean;
function AllowOutbound(Ready: Boolean; const FrameType: string): Boolean;
function NewRequestId(var NextId: Integer): string;
function BuildPromptFrame(const Id, Message: string): string;
function BuildAbortFrame(const Id: string): string;
function BuildSetHostToolsFrame(const Id: string): string;
function BuildHostToolResultFrame(const Id, Text: string; IsError: Boolean): string;
function BuildExtensionUiResponse(const RequestLine: string): string;
function AssistantDelta(const Line: string): string;
function ResponseErrorText(const Line: string): string;
function IsTerminalAgentEnd(const Line: string): Boolean;
function MessageWithSnapshots(const Message: string; const Paths: TArray<string>): string;
function TryBuildPromptFrame(Ready, HostToolsSent: Boolean; const Id, Message: string;
  out Frame: string): Boolean;
function BuildCompileResultJson(Ok: Boolean; const ConfigName, PlatformName: string;
  const Errors: TArray<TAgentCompileError>): string;

implementation

uses
  System.Generics.Collections, System.JSON;

function JsonObject(const Line: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if Trim(Line) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(Line);
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

function JsonStr(Obj: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Obj = nil then
    Exit;
  Value := Obj.GetValue(Name);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function AddBool(Obj: TJSONObject; const Name: string; Value: Boolean): TJSONObject;
begin
  if Value then
    Obj.AddPair(Name, TJSONTrue.Create)
  else
    Obj.AddPair(Name, TJSONFalse.Create);
  Result := Obj;
end;

function AcceptFrameLine(const Line: string): Boolean;
begin
  Result := TEncoding.UTF8.GetByteCount(Line) <= MaxFrameBytes;
end;

function FrameTypeOf(const Line: string): string;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Line);
  try
    Result := JsonStr(Obj, 'type');
  finally
    Obj.Free;
  end;
end;

function IsReadyFrame(const Line: string): Boolean;
begin
  Result := FrameTypeOf(Line) = 'ready';
end;

function CanSendPrompt(Ready, HostToolsSent: Boolean; const Message: string): Boolean;
begin
  Result := Ready and HostToolsSent and (Trim(Message) <> '');
end;

function AllowOutbound(Ready: Boolean; const FrameType: string): Boolean;
begin
  Result := Ready and (FrameType <> '');
end;

function NewRequestId(var NextId: Integer): string;
begin
  Inc(NextId);
  Result := 'req-' + IntToStr(NextId);
end;

function BuildPromptFrame(const Id, Message: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'prompt');
    Obj.AddPair('message', Message);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildAbortFrame(const Id: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'abort');
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function ToolDef(const Name, Description, PropList: string): TJSONObject;
var
  Params, Props, Prop: TJSONObject;
  Required: TJSONArray;
  PropName, One: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('description', Description);
  Params := TJSONObject.Create;
  Params.AddPair('type', 'object');
  Props := TJSONObject.Create;
  PropName := PropList;
  if PropName <> '' then
  begin
    Required := TJSONArray.Create;
    while PropName <> '' do
    begin
      if Pos(',', PropName) > 0 then
        One := Copy(PropName, 1, Pos(',', PropName) - 1)
      else
        One := PropName;
      Prop := TJSONObject.Create;
      Prop.AddPair('type', 'string');
      Props.AddPair(One, Prop);
      if Required.Count = 0 then
        Required.Add(One);
      if Pos(',', PropName) > 0 then
        Delete(PropName, 1, Pos(',', PropName))
      else
        PropName := '';
    end;
    Params.AddPair('required', Required);
  end;
  Params.AddPair('properties', Props);
  AddBool(Params, 'additionalProperties', False);
  Result.AddPair('parameters', Params);
end;

function BuildSetHostToolsFrame(const Id: string): string;
var
  Obj: TJSONObject;
  Tools: TJSONArray;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_host_tools');
    Tools := TJSONArray.Create;
    Tools.AddElement(ToolDef(ToolCompile,
      'Build the active Delphi project and return compiler errors.', ''));
    Tools.AddElement(ToolDef(ToolOpenBuffer,
      'Open a file in the IDE editor.', 'file'));
    Tools.AddElement(ToolDef(ToolInsertAtCaret,
      'Insert text at the editor caret after the user approves.', 'text'));
    Tools.AddElement(ToolDef(ToolListDirty,
      'List open IDE buffers that differ from disk. Does not save.', ''));
    Tools.AddElement(ToolDef(ToolReadBuffer,
      'Return unsaved IDE editor text for a path. Does not save.', 'path'));
    Tools.AddElement(ToolDef(ToolApplyEdit,
      'Replace IDE buffer text after the user confirms. Does not save.',
      'path,content,startLine,endLine,newText'));
    Obj.AddPair('tools', Tools);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildHostToolResultFrame(const Id, Text: string; IsError: Boolean): string;
var
  Obj, Content, Part: TJSONObject;
  Parts: TJSONArray;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'host_tool_result');
    Obj.AddPair('id', Id);
    if IsError then
      AddBool(Obj, 'isError', True);
    Content := TJSONObject.Create;
    Parts := TJSONArray.Create;
    Part := TJSONObject.Create;
    Part.AddPair('type', 'text');
    Part.AddPair('text', Text);
    Parts.AddElement(Part);
    Content.AddPair('content', Parts);
    Obj.AddPair('result', Content);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;
function BuildExtensionUiResponse(const RequestLine: string): string;
var
  Request, Obj: TJSONObject;
  Method, Id: string;
  Options: TJSONArray;
begin
  Result := '';
  Request := JsonObject(RequestLine);
  if Request = nil then
    Exit;
  try
    if JsonStr(Request, 'type') <> 'extension_ui_request' then
      Exit;
    Id := JsonStr(Request, 'id');
    if Id = '' then
      Exit;
    Method := JsonStr(Request, 'method');
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('type', 'extension_ui_response');
      Obj.AddPair('id', Id);
      if (Method = 'input') or (Method = 'editor') then
        AddBool(Obj, 'cancelled', True)
      else if Method = 'select' then
      begin
        Options := Request.GetValue('options') as TJSONArray;
        if (Options <> nil) and (Options.Count > 0) and (Options.Items[0] is TJSONString) then
          Obj.AddPair('value', TJSONString(Options.Items[0]).Value)
        else
          AddBool(Obj, 'cancelled', True);
      end
      else
        AddBool(Obj, 'confirmed', True);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  finally
    Request.Free;
  end;
end;
function AssistantDelta(const Line: string): string;
var
  Obj, Event: TJSONObject;
begin
  Result := '';
  Obj := JsonObject(Line);
  if Obj = nil then
    Exit;
  try
    if JsonStr(Obj, 'type') <> 'message_update' then
      Exit;
    if not (Obj.GetValue('assistantMessageEvent') is TJSONObject) then
      Exit;
    Event := TJSONObject(Obj.GetValue('assistantMessageEvent'));
    if JsonStr(Event, 'type') <> 'text_delta' then
      Exit;
    Result := JsonStr(Event, 'delta');
  finally
    Obj.Free;
  end;
end;
function ResponseErrorText(const Line: string): string;
var
  Obj: TJSONObject;
  Success: TJSONValue;
begin
  Result := '';
  Obj := JsonObject(Line);
  if Obj = nil then
    Exit;
  try
    if JsonStr(Obj, 'type') <> 'response' then
      Exit;
    Success := Obj.GetValue('success');
    if (Success is TJSONFalse) or ((Success is TJSONString) and
      SameText(TJSONString(Success).Value, 'false')) then
      Result := JsonStr(Obj, 'error');
  finally
    Obj.Free;
  end;
end;
function IsTerminalAgentEnd(const Line: string): Boolean;
var
  Obj: TJSONObject;
  Terminal: TJSONValue;
begin
  Result := False;
  Obj := JsonObject(Line);
  if Obj = nil then
    Exit;
  try
    if JsonStr(Obj, 'type') <> 'agent_end' then
      Exit;
    Terminal := Obj.GetValue('isTerminal');
    Result := not (Terminal is TJSONFalse);
  finally
    Obj.Free;
  end;
end;
function MessageWithSnapshots(const Message: string; const Paths: TArray<string>): string;
var
  Index: Integer;
begin
  Result := Message;
  if Length(Paths) = 0 then
    Exit;
  Result := Result + sLineBreak + sLineBreak + 'Dirty buffer snapshots:';
  for Index := 0 to High(Paths) do
    Result := Result + sLineBreak + Paths[Index];
end;
function TryBuildPromptFrame(Ready, HostToolsSent: Boolean; const Id, Message: string;
  out Frame: string): Boolean;
begin
  Frame := '';
  Result := CanSendPrompt(Ready, HostToolsSent, Message);
  if not Result then
    Exit;
  if not AllowOutbound(Ready, 'prompt') then
  begin
    Result := False;
    Exit;
  end;
  Frame := BuildPromptFrame(Id, Message);
end;
function BuildCompileResultJson(Ok: Boolean; const ConfigName, PlatformName: string;
  const Errors: TArray<TAgentCompileError>): string;
var
  Obj, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
begin
  Obj := TJSONObject.Create;
  try
    AddBool(Obj, 'ok', Ok);
    Obj.AddPair('config', ConfigName);
    Obj.AddPair('platform', PlatformName);
    List := TJSONArray.Create;
    for Index := 0 to High(Errors) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('file', Errors[Index].FileName);
      Item.AddPair('line', TJSONNumber.Create(Errors[Index].Line));
      Item.AddPair('col', TJSONNumber.Create(Errors[Index].Col));
      Item.AddPair('msg', Errors[Index].Msg);
      List.AddElement(Item);
    end;
    Obj.AddPair('errors', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;
end.
