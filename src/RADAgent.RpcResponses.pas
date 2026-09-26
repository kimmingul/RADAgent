unit RADAgent.RpcResponses;

{ Parsers for omp command responses (state, commands, models, login, history). No VCL. }

interface

type
  TSlashCommand = record Name, Description, Hint: string; end;
  TTodoItem = record Phase, Content, Status: string; end;
  TStateInfo = record
    Provider, ModelId, ThinkingLevel, SessionFile, SessionName, Cwd: string;
    ContextPercent: Double;
    HasContext, IsStreaming: Boolean;
    Todos: TArray<TTodoItem>;
  end;
  { Model: "provider/model" of an assistant message, when omp recorded it. }
  { Timestamp: ms since 1970 (UTC) when omp recorded it, 0 when unknown; CompletedAt: when an
    answer finished (its Timestamp when omp gave no completedAt); Stopped: the user stopped it.
    Checkpoint: the git checkpoint taken just before a user message was sent, 0 when none. }
  THistoryItem = record
    Role, Text, Model: string;
    Timestamp, CompletedAt: Int64;
    Checkpoint: Integer;
    Stopped: Boolean;
  end;
  TLoginProvider = record Id, Name: string; Authenticated: Boolean; end;

function ParseAvailableCommands(const Line: string; out Commands: TArray<TSlashCommand>): Boolean;
function ParseStateInfo(const Line: string; out Info: TStateInfo): Boolean;
function ParseMessagesPage(const Line: string; out Items: TArray<THistoryItem>; out NextCursor: string): Boolean;
{ get_available_models as sorted "provider/id" selectors. }
function ParseModelList(const Line: string; out Models: TArray<string>): Boolean;
function ParseThinkingLevels(const Line: string; out Levels: TArray<string>): Boolean;
function ParseLoginProviders(const Line: string; out Providers: TArray<TLoginProvider>): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, RADAgent.RpcJson;

{ Data object of a successful response to Command, or nil. Root stays owned by the caller. }
function ResponseData(Root: TJSONObject; const Command: string): TJSONObject;
begin
  Result := nil;
  if (Root <> nil) and (JsonStr(Root, 'type') = 'response') and (JsonStr(Root, 'command') = Command) and
    not IsJsonFalse(Root.GetValue('success')) then
    Result := JsonChild(Root, 'data');
end;

function ParseAvailableCommands(const Line: string; out Commands: TArray<TSlashCommand>): Boolean;
var
  Root, Data, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
  Name: string;
begin
  Commands := nil;
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  try
    List := nil;
    if (JsonStr(Root, 'type') = 'available_commands_update') and (Root.GetValue('commands') is TJSONArray) then
      List := TJSONArray(Root.GetValue('commands'))
    else
    begin
      Data := ResponseData(Root, 'get_available_commands');
      if (Data <> nil) and (Data.GetValue('commands') is TJSONArray) then
        List := TJSONArray(Data.GetValue('commands'));
    end;
    if List = nil then
      Exit;
    SetLength(Commands, List.Count);
    for Index := 0 to List.Count - 1 do
      if List.Items[Index] is TJSONObject then
      begin
        Item := TJSONObject(List.Items[Index]);
        Name := JsonStr(Item, 'name');
        if Name.StartsWith('/') then
          Name := Copy(Name, 2, MaxInt);
        Commands[Index].Name := Name;
        Commands[Index].Description := JsonStr(Item, 'description');
        if Item.GetValue('input') is TJSONObject then
          Commands[Index].Hint := JsonStr(TJSONObject(Item.GetValue('input')), 'hint')
        else if Item.GetValue('input') is TJSONString then
          Commands[Index].Hint := TJSONString(Item.GetValue('input')).Value
        else
          Commands[Index].Hint := JsonStr(Item, 'hint');
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

procedure ReadTodos(Data: TJSONObject; var Info: TStateInfo);
var
  Phases, Tasks: TJSONArray;
  Phase, Task: TJSONObject;
  P, T: Integer;
  Item: TTodoItem;
begin
  if not (Data.GetValue('todoPhases') is TJSONArray) then
    Exit;
  Phases := TJSONArray(Data.GetValue('todoPhases'));
  for P := 0 to Phases.Count - 1 do
    if Phases.Items[P] is TJSONObject then
    begin
      Phase := TJSONObject(Phases.Items[P]);
      if not (Phase.GetValue('tasks') is TJSONArray) then
        Continue;
      Tasks := TJSONArray(Phase.GetValue('tasks'));
      for T := 0 to Tasks.Count - 1 do
        if Tasks.Items[T] is TJSONObject then
        begin
          Task := TJSONObject(Tasks.Items[T]);
          Item.Phase := JsonStr(Phase, 'name');
          Item.Content := JsonStr(Task, 'content');
          Item.Status := JsonStr(Task, 'status');
          Info.Todos := Info.Todos + [Item];
        end;
    end;
end;

function ParseStateInfo(const Line: string; out Info: TStateInfo): Boolean;
var
  Root, Data, Model, Context: TJSONObject;
begin
  Info := Default(TStateInfo);
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  try
    Data := ResponseData(Root, 'get_state');
    if Data = nil then
      Exit;
    Model := JsonChild(Data, 'model');
    Info.Provider := JsonStr(Model, 'provider');
    Info.ModelId := JsonStr(Model, 'id');
    Info.ThinkingLevel := JsonStr(Data, 'thinkingLevel');
    Info.SessionFile := JsonStr(Data, 'sessionFile');
    Info.SessionName := JsonStr(Data, 'sessionName');
    Info.Cwd := JsonStr(Data, 'cwd');
    Info.IsStreaming := IsJsonTrue(Data.GetValue('isStreaming'));
    Context := JsonChild(Data, 'contextUsage');
    if (Context <> nil) and (Context.GetValue('percent') is TJSONNumber) then
    begin
      Info.ContextPercent := TJSONNumber(Context.GetValue('percent')).AsDouble;
      Info.HasContext := True;
    end;
    ReadTodos(Data, Info);
    Result := True;
  finally
    Root.Free;
  end;
end;

function ParseMessagesPage(const Line: string; out Items: TArray<THistoryItem>;
  out NextCursor: string): Boolean;
var
  Root, Data, Msg: TJSONObject;
  List: TJSONArray;
  Index, Count: Integer;
  Role, Text: string;
begin
  Items := nil;
  NextCursor := '';
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  try
    Data := ResponseData(Root, 'get_messages_page');
    if Data = nil then
      Data := ResponseData(Root, 'get_messages');
    if Data = nil then
      Exit;
    NextCursor := JsonStr(Data, 'nextCursor');
    Result := True;
    if not (Data.GetValue('messages') is TJSONArray) then
      Exit;
    List := TJSONArray(Data.GetValue('messages'));
    SetLength(Items, List.Count);
    Count := 0;
    for Index := 0 to List.Count - 1 do
    begin
      if not (List.Items[Index] is TJSONObject) then
        Continue;
      Msg := TJSONObject(List.Items[Index]);
      Role := JsonStr(Msg, 'role');
      if (Role <> 'user') and (Role <> 'assistant') then
        Continue;
      Text := ContentText(Msg.GetValue('content'));
      if Text = '' then
        Continue;
      Items[Count].Role := Role;
      Items[Count].Text := Text;
      Items[Count].Model := '';
      Items[Count].Timestamp := JsonInt(Msg, 'timestamp');
      Items[Count].CompletedAt := JsonInt(Msg, 'completedAt', Items[Count].Timestamp);
      Items[Count].Stopped := JsonStr(Msg, 'stopReason') = 'aborted';
      Items[Count].Checkpoint := 0;
      if (Role = 'assistant') and (JsonStr(Msg, 'model') <> '') then
        Items[Count].Model := JsonStr(Msg, 'provider') + '/' + JsonStr(Msg, 'model');
      Inc(Count);
    end;
    SetLength(Items, Count);
  finally
    Root.Free;
  end;
end;

function ParseModelList(const Line: string; out Models: TArray<string>): Boolean;
var
  Root, Data, Model: TJSONObject;
  List: TJSONArray;
  Index: Integer;
  Names: TStringList;
begin
  Models := nil;
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  Names := TStringList.Create;
  try
    Data := ResponseData(Root, 'get_available_models');
    if (Data = nil) or not (Data.GetValue('models') is TJSONArray) then
      Exit;
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    List := TJSONArray(Data.GetValue('models'));
    for Index := 0 to List.Count - 1 do
      if List.Items[Index] is TJSONObject then
      begin
        Model := TJSONObject(List.Items[Index]);
        if (JsonStr(Model, 'provider') <> '') and (JsonStr(Model, 'id') <> '') then
          Names.Add(JsonStr(Model, 'provider') + '/' + JsonStr(Model, 'id'));
      end;
    Models := Names.ToStringArray;
    Result := True;
  finally
    Names.Free;
    Root.Free;
  end;
end;

function ParseThinkingLevels(const Line: string; out Levels: TArray<string>): Boolean;
var
  Root, Data: TJSONObject;
  List: TJSONArray;
  Index: Integer;
begin
  Levels := nil;
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  try
    Data := ResponseData(Root, 'get_available_thinking_levels');
    if (Data = nil) or not (Data.GetValue('levels') is TJSONArray) then
      Exit;
    List := TJSONArray(Data.GetValue('levels'));
    for Index := 0 to List.Count - 1 do
      if List.Items[Index] is TJSONString then
        Levels := Levels + [TJSONString(List.Items[Index]).Value];
    Result := True;
  finally
    Root.Free;
  end;
end;

function ParseLoginProviders(const Line: string; out Providers: TArray<TLoginProvider>): Boolean;
var
  Root, Data, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
  Provider: TLoginProvider;
begin
  Providers := nil;
  Result := False;
  Root := JsonObject(Line);
  if Root = nil then
    Exit;
  try
    Data := ResponseData(Root, 'get_login_providers');
    if (Data = nil) or not (Data.GetValue('providers') is TJSONArray) then
      Exit;
    List := TJSONArray(Data.GetValue('providers'));
    for Index := 0 to List.Count - 1 do
      if List.Items[Index] is TJSONObject then
      begin
        Item := TJSONObject(List.Items[Index]);
        if IsJsonFalse(Item.GetValue('available')) then
          Continue;
        Provider.Id := JsonStr(Item, 'id');
        Provider.Name := JsonStr(Item, 'name');
        Provider.Authenticated := IsJsonTrue(Item.GetValue('authenticated'));
        Providers := Providers + [Provider];
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

end.
