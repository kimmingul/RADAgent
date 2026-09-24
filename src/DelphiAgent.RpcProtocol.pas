unit DelphiAgent.RpcProtocol;

{ JSONL frames for omp --mode rpc (protocol v1, and v2 when omp offers it). No ToolsAPI. }

interface

uses
  System.SysUtils;

const
  { One physical stdout line (v1 and v2). }
  MaxFrameBytes = 1048576;
  { One logical frame rebuilt from v2 rpc_chunk frames. }
  MaxReassembledFrameBytes = 67108864;

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
{ Protocol to use after this ready frame: 2 when offered, else 1; 0 when omp offers neither. }
function ChooseProtocol(const ReadyLine: string): Integer;
function BuildNegotiateFrame(const Id: string; Version: Integer): string;
{ A command frame from the page or a dialog with a fresh request id; UI replies keep theirs.
  '' when Frame is not a JSON object. }
function WithRequestId(const FrameType, Frame: string; var NextId: Integer): string;
function CanSendPrompt(Ready, HostToolsSent: Boolean; const Message: string): Boolean;
function AllowOutbound(Ready: Boolean; const FrameType: string): Boolean;
function NewRequestId(var NextId: Integer): string;
{ ImagesJson: optional ImageContent[] (objects with type "image", data, mimeType). }
function BuildPromptFrame(const Id, Message: string; const ImagesJson: string = ''): string;
function BuildAbortFrame(const Id: string): string;
function BuildHostToolResultFrame(const Id, Text: string; IsError: Boolean): string;
function BuildExtensionUiResponse(const RequestLine: string): string;
function TryBuildPromptFrame(Ready, HostToolsSent: Boolean; const Id, Message: string;
  out Frame: string; const ImagesJson: string = ''): Boolean;
function BuildCompileResultJson(Ok: Boolean; const ConfigName, PlatformName: string;
  const Errors: TArray<TAgentCompileError>): string;

implementation

uses
  System.Generics.Collections, System.JSON, DelphiAgent.RpcJson;

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
  { Physical lines over MaxFrameBytes never get here (ReadStdoutLines drops them). }
  Result := TEncoding.UTF8.GetByteCount(Line) <= MaxReassembledFrameBytes;
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

function ChooseProtocol(const ReadyLine: string): Integer;
var
  Obj: TJSONObject;
  Versions: TJSONValue;
  Item: TJSONValue;
  HasV1, HasV2: Boolean;
begin
  Obj := JsonObject(ReadyLine);
  try
    Versions := nil;
    if Obj <> nil then
      Versions := Obj.GetValue('supportedProtocolVersions');
    { Older runtimes announce no list and speak v1 only. }
    if not (Versions is TJSONArray) then
      Exit(1);
    HasV1 := False;
    HasV2 := False;
    for Item in TJSONArray(Versions) do
      if Item is TJSONNumber then
      begin
        HasV1 := HasV1 or (TJSONNumber(Item).AsInt = 1);
        HasV2 := HasV2 or (TJSONNumber(Item).AsInt = 2);
      end;
    if HasV2 then
      Result := 2
    else if HasV1 then
      Result := 1
    else
      Result := 0;
  finally
    Obj.Free;
  end;
end;

function BuildNegotiateFrame(const Id: string; Version: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'negotiate_protocol');
    Obj.AddPair('protocolVersion', TJSONNumber.Create(Version));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function WithRequestId(const FrameType, Frame: string; var NextId: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Frame);
  if Obj = nil then
    Exit('');
  try
    if FrameType <> 'extension_ui_response' then
    begin
      Obj.RemovePair('id').Free;
      Obj.AddPair('id', NewRequestId(NextId));
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
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

function BuildPromptFrame(const Id, Message: string; const ImagesJson: string): string;
var
  Obj: TJSONObject;
  Images: TJSONValue;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'prompt');
    Obj.AddPair('message', Message);
    if ImagesJson <> '' then
    begin
      Images := TJSONObject.ParseJSONValue(ImagesJson);
      if Images is TJSONArray then
        Obj.AddPair('images', Images)
      else
        Images.Free;
    end;
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
function TryBuildPromptFrame(Ready, HostToolsSent: Boolean; const Id, Message: string;
  out Frame: string; const ImagesJson: string): Boolean;
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
  Frame := BuildPromptFrame(Id, Message, ImagesJson);
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
