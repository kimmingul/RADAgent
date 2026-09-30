unit RADAgent.ChatPageMessages;

{ JSON messages for the chat page (src\chat\chat.js). Field "t" is the kind. No VCL. }

interface

uses
  RADAgent.RpcEvents, RADAgent.RpcResponses, RADAgent.RpcQueue, RADAgent.AgentSettings;

{ ts: when it was sent (ms since 1970, UTC), shown on hover. }
function PageUser(const Text: string): string;
{ A message sent while omp works: Queue is 'steer' (read at the next step) or 'followUp'; Sent is
  the text omp got, which its queue reports list. }
function PageQueuedUser(const Text, Queue, Sent: string): string;
{ omp's pending messages. FromState: a get_state answer, which follows every queue change omp
  reported, so a message missing from it was lost (omp restarted), not read. }
function PageQueue(const Snapshot: TQueueSnapshot; FromState: Boolean): string;
{ omp's answer to calling off a queued message (Queue as in PageQueuedUser). }
function PageQueueRemoved(const Sent, Queue: string; Removed: Boolean): string;
{ A panel over the chat with Markdown (a subagent transcript, the shortcut list). }
function PageSheet(const Title, Markdown: string): string;
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
{ A notice ending in a web link (LinkText opens Url in the browser). }
function PageLinkNotice(const Level, Text, LinkText, Url: string): string;
{ A notice naming models ("provider/model"); the page puts each one's logo in front of it. }
function PageModelNotice(const Level, Text: string; const Models: array of string): string;
{ The model answering from here on ("provider/model"). }
function PageModel(const Selector: string): string;
{ A turn ended: when it started and ended (ms since 1970, UTC), and whether the user stopped it. }
function PageTurnEnd(StartedAt, EndedAt: Int64; Stopped: Boolean): string;
function PageClear: string;
{ A reloaded conversation. User messages carry ts (sent); the last answer of each turn carries
  started/ended/stopped like turnEnd, from the times omp recorded. }
function PageHistory(const Items: TArray<THistoryItem>): string;

implementation

uses
  System.SysUtils, System.JSON, RADAgent.RpcJson;

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
  Result := Build('user', ['text', 'ts'], [Text, IntToStr(UnixMs)]);
end;

function PageQueuedUser(const Text, Queue, Sent: string): string;
begin
  Result := Build('user', ['text', 'queue', 'sent', 'ts'], [Text, Queue, Sent, IntToStr(UnixMs)]);
end;

function StringArray(const Items: TArray<string>): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in Items do
    Result.Add(Item);
end;

function PageQueue(const Snapshot: TQueueSnapshot; FromState: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'queue');
    Obj.AddPair('steering', StringArray(Snapshot.Steering));
    Obj.AddPair('followUp', StringArray(Snapshot.FollowUp));
    Obj.AddPair('state', TJSONBool.Create(FromState));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageQueueRemoved(const Sent, Queue: string; Removed: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'queueRemoved');
    Obj.AddPair('sent', Sent);
    Obj.AddPair('queue', Queue);
    Obj.AddPair('removed', TJSONBool.Create(Removed));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageSheet(const Title, Markdown: string): string;
begin
  Result := Build('sheet', ['title', 'text'], [Title, Markdown]);
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

function PageLinkNotice(const Level, Text, LinkText, Url: string): string;
begin
  Result := Build('notice', ['level', 'text', 'linkText', 'url'], [Level, Text, LinkText, Url]);
end;

function PageModelNotice(const Level, Text: string; const Models: array of string): string;
var
  Obj: TJSONObject;
  List: TJSONArray;
  Model: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'notice');
    Obj.AddPair('level', Level);
    Obj.AddPair('text', Text);
    List := TJSONArray.Create;
    for Model in Models do
      if Model <> '' then
        List.Add(Model);
    Obj.AddPair('models', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PageModel(const Selector: string): string;
begin
  Result := Build('model', ['model'], [Selector]);
end;

procedure AddTurnTimes(Obj: TJSONObject; StartedAt, EndedAt: Int64; Stopped: Boolean);
begin
  if (StartedAt <= 0) or (EndedAt < StartedAt) then
    Exit;
  Obj.AddPair('started', TJSONNumber.Create(StartedAt));
  Obj.AddPair('ended', TJSONNumber.Create(EndedAt));
  Obj.AddPair('stopped', TJSONBool.Create(Stopped));
end;

function PageTurnEnd(StartedAt, EndedAt: Int64; Stopped: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'turnEnd');
    AddTurnTimes(Obj, StartedAt, EndedAt, Stopped);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
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
  SentAt: Int64;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'history');
    List := TJSONArray.Create;
    SentAt := 0;
    for Index := 0 to High(Items) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('role', Items[Index].Role);
      Item.AddPair('text', Items[Index].Text);
      if Items[Index].Model <> '' then
        Item.AddPair('model', Items[Index].Model);
      if Items[Index].Checkpoint > 0 then
        Item.AddPair('seq', TJSONNumber.Create(Items[Index].Checkpoint));
      if Items[Index].Role = 'user' then
      begin
        SentAt := Items[Index].Timestamp;
        if SentAt > 0 then
          Item.AddPair('ts', TJSONNumber.Create(SentAt));
        { A turn without an answer (stopped before any output): its logged end, if any. }
        AddTurnTimes(Item, SentAt, Items[Index].CompletedAt, Items[Index].Stopped);
      end
      { The turn's last answer: the next message is the user's, or there is none. }
      else if (Index = High(Items)) or (Items[Index + 1].Role = 'user') then
        AddTurnTimes(Item, SentAt, Items[Index].CompletedAt, Items[Index].Stopped);
      List.AddElement(Item);
    end;
    Obj.AddPair('items', List);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
