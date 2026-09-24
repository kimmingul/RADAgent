unit RADAgent.ChatPageMessages;

{ JSON messages for the chat page (src\chat\chat.js). Field "t" is the kind. No VCL. }

interface

uses
  RADAgent.RpcEvents, RADAgent.RpcResponses, RADAgent.AgentSettings;

function PageUser(const Text: string): string;
function PageDelta(const Text: string): string;
function PageAssistantEnd: string;
function PageThinkingDelta(const Text: string): string;
{ A whole thinking block, for the transcript after it ended. }
function PageThinking(const Text: string): string;
function PageThinkingEnd: string;
function PageToolInputDelta(const Id, Name, Text: string): string;
function PageToolStart(const Id, Name, Detail, Input: string): string;
function PageToolUpdate(const Id, Text: string): string;
function PageToolEnd(const Id: string; Ok: Boolean; Ms: Int64; const ResultText: string): string;
function PageSubagent(const Event: TAgentEvent): string;
{ An approved edit that reached the buffer: +Added -Removed, first changed line. }
function PageFileChange(const Path: string; Added, Removed, Line: Integer): string;
function PageTodos(const Todos: TArray<TTodoItem>): string;
{ Which activity kinds the page shows. }
function PageDisplay(Shows: TChatShows): string;
function PageNotice(const Level, Text: string): string;
function PageTurnEnd: string;
function PageClear: string;
function PageHistory(const Items: TArray<THistoryItem>): string;

implementation

uses
  System.SysUtils, System.JSON;

function Build(const Kind: string; const Names, Values: array of string): string;
var
  Obj: TJSONObject;
  Index: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', Kind);
    for Index := 0 to High(Names) do
      Obj.AddPair(Names[Index], Values[Index]);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageUser(const Text: string): string;
begin
  Result := Build('user', ['text'], [Text]);
end;

function PageDelta(const Text: string): string;
begin
  Result := Build('assistantDelta', ['text'], [Text]);
end;

function PageAssistantEnd: string;
begin
  Result := Build('assistantEnd', [], []);
end;

function PageThinkingDelta(const Text: string): string;
begin
  Result := Build('thinkingDelta', ['text'], [Text]);
end;

function PageThinking(const Text: string): string;
begin
  Result := Build('thinking', ['text'], [Text]);
end;

function PageThinkingEnd: string;
begin
  Result := Build('thinkingEnd', [], []);
end;

function PageToolInputDelta(const Id, Name, Text: string): string;
begin
  Result := Build('toolInputDelta', ['id', 'name', 'text'], [Id, Name, Text]);
end;

function PageToolStart(const Id, Name, Detail, Input: string): string;
begin
  Result := Build('toolStart', ['id', 'name', 'detail', 'input'], [Id, Name, Detail, Input]);
end;

function PageToolUpdate(const Id, Text: string): string;
begin
  Result := Build('toolUpdate', ['id', 'text'], [Id, Text]);
end;

function PageSubagent(const Event: TAgentEvent): string;
begin
  Result := Build('subagent', ['id', 'agent', 'description', 'intent', 'status', 'tools'],
    [Event.ToolId, Event.ToolName, Event.Detail, Event.Text, Event.Level, IntToStr(Event.Count)]);
end;

function PageFileChange(const Path: string; Added, Removed, Line: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'fileChange');
    Obj.AddPair('path', Path);
    Obj.AddPair('name', ExtractFileName(Path));
    Obj.AddPair('added', TJSONNumber.Create(Added));
    Obj.AddPair('removed', TJSONNumber.Create(Removed));
    Obj.AddPair('line', TJSONNumber.Create(Line));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageTodos(const Todos: TArray<TTodoItem>): string;
var
  Obj, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'todos');
    List := TJSONArray.Create;
    for Index := 0 to High(Todos) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('phase', Todos[Index].Phase);
      Item.AddPair('content', Todos[Index].Content);
      Item.AddPair('status', Todos[Index].Status);
      List.AddElement(Item);
    end;
    Obj.AddPair('items', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageDisplay(Shows: TChatShows): string;
var
  Obj, Flags: TJSONObject;
  Show: TChatShow;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'display');
    Flags := TJSONObject.Create;
    for Show := Low(TChatShow) to High(TChatShow) do
      Flags.AddPair(ChatShowKeys[Show], TJSONBool.Create(Show in Shows));
    Obj.AddPair('show', Flags);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageToolEnd(const Id: string; Ok: Boolean; Ms: Int64; const ResultText: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'toolEnd');
    Obj.AddPair('id', Id);
    Obj.AddPair('ok', TJSONBool.Create(Ok));
    Obj.AddPair('ms', TJSONNumber.Create(Ms));
    Obj.AddPair('result', ResultText);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageNotice(const Level, Text: string): string;
begin
  Result := Build('notice', ['level', 'text'], [Level, Text]);
end;

function PageTurnEnd: string;
begin
  Result := Build('turnEnd', [], []);
end;

function PageClear: string;
begin
  Result := Build('clear', [], []);
end;

function PageHistory(const Items: TArray<THistoryItem>): string;
var
  Obj, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'history');
    List := TJSONArray.Create;
    for Index := 0 to High(Items) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('role', Items[Index].Role);
      Item.AddPair('text', Items[Index].Text);
      List.AddElement(Item);
    end;
    Obj.AddPair('items', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
