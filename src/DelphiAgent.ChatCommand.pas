unit DelphiAgent.ChatCommand;

{ Maps chat input onto omp RPC frames that already exist. No new command types. }

interface

uses
  System.SysUtils;

type
  TChatCommand = (
    ccPrompt,
    ccNewSession,
    ccAbort,
    ccListModels,
    ccSetModel,
    ccFast,
    ccThinking,
    ccSlashAsPrompt);

function ClassifyChat(const Text: string; out Arg1, Arg2: string): TChatCommand;
function BuildIdTypeFrame(const Id, FrameType: string): string;
function BuildSetModelFrame(const Id, Provider, ModelId: string): string;
function BuildSetFastFrame(const Id: string; Enabled: Boolean): string;
function BuildSetThinkingFrame(const Id, Level: string): string;
function StateModelAndCwd(const Line: string; out Model, Cwd: string): Boolean;
function ModelListText(const Line: string): string;

type
  TExtensionUi = record
    Id: string;
    Method: string;
    Title: string;
    Message: string;
    Options: TArray<string>;
  end;

function ParseExtensionUi(const Line: string; out Ui: TExtensionUi): Boolean;
function BuildUiReply(const Id, Value: string; Confirmed, Cancelled: Boolean): string;

implementation

uses
  System.Classes, System.JSON, DelphiAgent.RpcProtocol;

function FirstToken(const Text: string; out Rest: string): string;
var
  P: Integer;
begin
  Rest := Trim(Text);
  P := Pos(' ', Rest);
  if P = 0 then
  begin
    Result := Rest;
    Rest := '';
  end
  else
  begin
    Result := Copy(Rest, 1, P - 1);
    Rest := Trim(Copy(Rest, P + 1, MaxInt));
  end;
end;

function ClassifyChat(const Text: string; out Arg1, Arg2: string): TChatCommand;
var
  Head, Rest, A, B: string;
begin
  Arg1 := '';
  Arg2 := '';
  Head := FirstToken(Trim(Text), Rest);
  if SameText(Head, '/clear') or SameText(Head, '/new') then
    Exit(ccNewSession);
  if SameText(Head, '/abort') then
    Exit(ccAbort);
  if SameText(Head, '/model') then
  begin
    if Rest = '' then
      Exit(ccListModels);
    A := FirstToken(Rest, B);
    if (A <> '') and (B <> '') and (Pos(' ', B) = 0) then
    begin
      Arg1 := A;
      Arg2 := B;
      Exit(ccSetModel);
    end;
    Exit(ccSlashAsPrompt);
  end;
  if SameText(Head, '/fast') then
  begin
    if (Rest = '') or SameText(Rest, 'on') or SameText(Rest, 'off') then
    begin
      Arg1 := Rest;
      Exit(ccFast);
    end;
    Exit(ccSlashAsPrompt);
  end;
  if SameText(Head, '/thinking') or SameText(Head, '/effort') then
  begin
    if (Rest = '') or (Pos(' ', Rest) = 0) then
    begin
      Arg1 := Rest;
      Exit(ccThinking);
    end;
    Exit(ccSlashAsPrompt);
  end;
  if (Head <> '') and (Head[1] = '/') then
    Exit(ccSlashAsPrompt);
  Result := ccPrompt;
end;

function BuildIdTypeFrame(const Id, FrameType: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', FrameType);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildSetModelFrame(const Id, Provider, ModelId: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_model');
    Obj.AddPair('provider', Provider);
    Obj.AddPair('modelId', ModelId);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildSetFastFrame(const Id: string; Enabled: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_fast_mode');
    if Enabled then
      Obj.AddPair('enabled', TJSONTrue.Create)
    else
      Obj.AddPair('enabled', TJSONFalse.Create);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildSetThinkingFrame(const Id, Level: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_thinking_level');
    Obj.AddPair('level', Level);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function JsonStr(Obj: TJSONObject; const Name: string): string;
begin
  Result := '';
  if (Obj <> nil) and (Obj.GetValue(Name) is TJSONString) then
    Result := TJSONString(Obj.GetValue(Name)).Value;
end;

function StateModelAndCwd(const Line: string; out Model, Cwd: string): Boolean;
var
  Root, Data, ModelObj: TJSONObject;
  Value: TJSONValue;
begin
  Model := '';
  Cwd := '';
  Result := False;
  Value := TJSONObject.ParseJSONValue(Line);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Root := TJSONObject(Value);
  try
    if not SameText(JsonStr(Root, 'command'), 'get_state') then
      Exit;
    if not (Root.GetValue('data') is TJSONObject) then
      Exit;
    Data := TJSONObject(Root.GetValue('data'));
    Cwd := JsonStr(Data, 'cwd');
    if Data.GetValue('model') is TJSONObject then
    begin
      ModelObj := TJSONObject(Data.GetValue('model'));
      Model := JsonStr(ModelObj, 'provider');
      if JsonStr(ModelObj, 'id') <> '' then
      begin
        if Model <> '' then
          Model := Model + '/';
        Model := Model + JsonStr(ModelObj, 'id');
      end;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

procedure CollectModels(const Value: TJSONValue; const Lines: TStringList);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
  Provider, Id, Name: string;
begin
  if Value is TJSONArray then
  begin
    Arr := TJSONArray(Value);
    for Index := 0 to Arr.Count - 1 do
      CollectModels(Arr.Items[Index], Lines);
    Exit;
  end;
  if not (Value is TJSONObject) then
    Exit;
  Obj := TJSONObject(Value);
  Id := JsonStr(Obj, 'id');
  if Id = '' then
    Id := JsonStr(Obj, 'modelId');
  Provider := JsonStr(Obj, 'provider');
  Name := JsonStr(Obj, 'name');
  if Id <> '' then
  begin
    if Provider <> '' then
      Lines.Add(Provider + '/' + Id)
    else if Name <> '' then
      Lines.Add(Name)
    else
      Lines.Add(Id);
  end;
  for Index := 0 to Obj.Count - 1 do
    CollectModels(Obj.Pairs[Index].JsonValue, Lines);
end;

function ModelListText(const Line: string): string;
var
  Value: TJSONValue;
  Root: TJSONObject;
  Lines: TStringList;
begin
  Result := '';
  Value := TJSONObject.ParseJSONValue(Line);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Root := TJSONObject(Value);
  try
    if not SameText(JsonStr(Root, 'command'), 'get_available_models') then
      Exit;
    Lines := TStringList.Create;
    try
      Lines.Sorted := True;
      Lines.Duplicates := dupIgnore;
      CollectModels(Root.GetValue('data'), Lines);
      if Lines.Count = 0 then
        Result := '(no models)'
      else
        Result := Lines.Text;
    finally
      Lines.Free;
    end;
  finally
    Root.Free;
  end;
end;

function ParseExtensionUi(const Line: string; out Ui: TExtensionUi): Boolean;
var
  Value: TJSONValue;
  Root: TJSONObject;
  Options: TJSONArray;
  Index: Integer;
begin
  Result := False;
  Ui.Id := '';
  Ui.Method := '';
  Ui.Title := '';
  Ui.Message := '';
  SetLength(Ui.Options, 0);
  Value := TJSONObject.ParseJSONValue(Line);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  Root := TJSONObject(Value);
  try
    if not SameText(JsonStr(Root, 'type'), 'extension_ui_request') then
      Exit;
    Ui.Id := JsonStr(Root, 'id');
    Ui.Method := JsonStr(Root, 'method');
    Ui.Title := JsonStr(Root, 'title');
    Ui.Message := JsonStr(Root, 'message');
    if Root.GetValue('options') is TJSONArray then
    begin
      Options := TJSONArray(Root.GetValue('options'));
      SetLength(Ui.Options, Options.Count);
      for Index := 0 to Options.Count - 1 do
        if Options.Items[Index] is TJSONString then
          Ui.Options[Index] := TJSONString(Options.Items[Index]).Value;
    end;
    Result := Ui.Id <> '';
  finally
    Root.Free;
  end;
end;

function BuildUiReply(const Id, Value: string; Confirmed, Cancelled: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('type', 'extension_ui_response');
    Obj.AddPair('id', Id);
    if Cancelled then
      Obj.AddPair('cancelled', TJSONTrue.Create)
    else if Value <> '' then
      Obj.AddPair('value', Value)
    else if Confirmed then
      Obj.AddPair('confirmed', TJSONTrue.Create)
    else
      Obj.AddPair('confirmed', TJSONFalse.Create);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
