unit RADAgent.SessionData;

{ Readers for omp replies the chat shows as they are (user messages to branch from, the session
  tree, the last answer, a subagent transcript, a shell command). No VCL, no ToolsAPI. }

interface

uses
  System.JSON;

type
  TBranchMessage = record
    EntryId, Text: string;
  end;

  { One user or assistant message of the session tree. Depth grows only where the tree forks;
    OnPath: on the way from the root to the current leaf. }
  TTreeLine = record
    EntryId, Text: string;
    Depth: Integer;
    IsUser, OnPath: Boolean;
  end;

  TBashResult = record
    Output: string;
    ExitCode: Integer;
    Cancelled, Truncated: Boolean;
  end;

{ The command a response answers, '' for other frames; Ok: success was not false. }
function ResponseOf(const Line: string; out Ok: Boolean): string;
{ get_branch_messages: the user messages of the current path, oldest first. }
function ParseBranchMessages(const Line: string; out Items: TArray<TBranchMessage>): Boolean;
{ get_tree: messages in tree order. }
function ParseTree(const Line: string; out Items: TArray<TTreeLine>): Boolean;
{ data.text of a response (get_last_assistant_text), '' when absent. }
function ResponseText(const Line: string): string;
{ The body of the last fenced code block in Markdown text, '' when there is none. }
function LastCodeBlock(const Text: string): string;
{ get_subagent_messages as Markdown: one heading per message, tool calls named. }
function TranscriptMarkdown(const Line: string): string;
{ get_subagents as Markdown lines. }
function SubagentListMarkdown(const Line: string): string;
function ParseBash(const Line: string; out Bash: TBashResult): Boolean;
{ The data object of a successful response, cloned; nil otherwise. The caller frees it. }
function ResponseDataClone(const Line: string): TJSONObject;
implementation

uses
  System.SysUtils, System.Generics.Collections, RADAgent.RpcJson;

function ResponseOf(const Line: string; out Ok: Boolean): string;
var
  Obj: TJSONObject;
begin
  Result := '';
  Ok := False;
  Obj := JsonObject(Line);
  try
    if (Obj = nil) or (JsonStr(Obj, 'type') <> 'response') then
      Exit;
    Result := JsonStr(Obj, 'command');
    Ok := not IsJsonFalse(Obj.GetValue('success'));
  finally
    Obj.Free;
  end;
end;

function DataOf(Obj: TJSONObject): TJSONObject;
begin
  Result := nil;
  if (Obj <> nil) and not IsJsonFalse(Obj.GetValue('success')) then
    Result := JsonChild(Obj, 'data');
end;

function OneLine(const Text: string; MaxLen: Integer): string;
begin
  Result := CollapseWhitespace(Text);
  if Length(Result) > MaxLen then
    Result := Copy(Result, 1, MaxLen - 1) + '…';
end;

function ParseBranchMessages(const Line: string; out Items: TArray<TBranchMessage>): Boolean;
var
  Obj, Data: TJSONObject;
  Item: TJSONValue;
  Message: TBranchMessage;
begin
  Items := nil;
  Obj := JsonObject(Line);
  try
    Data := DataOf(Obj);
    Result := (Data <> nil) and (Data.GetValue('messages') is TJSONArray);
    if Result then
      for Item in TJSONArray(Data.GetValue('messages')) do
        if Item is TJSONObject then
        begin
          Message.EntryId := JsonStr(TJSONObject(Item), 'entryId');
          Message.Text := JsonStr(TJSONObject(Item), 'text');
          if Message.EntryId <> '' then
            Items := Items + [Message];
        end;
  finally
    Obj.Free;
  end;
end;

function ParseTree(const Line: string; out Items: TArray<TTreeLine>): Boolean;
var
  Obj, Data: TJSONObject;
  Parents: TDictionary<string, string>;
  Lines: TList<TTreeLine>;
  OnPath: TDictionary<string, Boolean>;
  Id: string;
  Index: Integer;
  Item: TTreeLine;

  procedure Walk(Node: TJSONObject; const ParentId: string; Depth: Integer);
  var
    Entry, Msg: TJSONObject;
    Children: TJSONArray;
    Child: TJSONValue;
    EntryId, Role: string;
    Line: TTreeLine;
  begin
    Entry := JsonChild(Node, 'entry');
    EntryId := JsonStr(Entry, 'id');
    if EntryId <> '' then
      Parents.AddOrSetValue(EntryId, ParentId);
    Msg := JsonChild(Entry, 'message');
    Role := JsonStr(Msg, 'role');
    if (JsonStr(Entry, 'type') = 'message') and ((Role = 'user') or (Role = 'assistant')) and
      (Trim(ContentText(Msg.GetValue('content'))) <> '') then
    begin
      Line := Default(TTreeLine);
      Line.EntryId := EntryId;
      Line.Text := OneLine(ContentText(Msg.GetValue('content')), 90);
      Line.Depth := Depth;
      Line.IsUser := Role = 'user';
      Lines.Add(Line);
    end;
    if not (Node.GetValue('children') is TJSONArray) then
      Exit;
    Children := TJSONArray(Node.GetValue('children'));
    for Child in Children do
      if Child is TJSONObject then
        if Children.Count > 1 then
          Walk(TJSONObject(Child), EntryId, Depth + 1)
        else
          Walk(TJSONObject(Child), EntryId, Depth);
  end;

var
  Root: TJSONValue;
begin
  Items := nil;
  Obj := JsonObject(Line);
  Parents := TDictionary<string, string>.Create;
  OnPath := TDictionary<string, Boolean>.Create;
  Lines := TList<TTreeLine>.Create;
  try
    Data := DataOf(Obj);
    Result := (Data <> nil) and (Data.GetValue('tree') is TJSONArray);
    if not Result then
      Exit;
    for Root in TJSONArray(Data.GetValue('tree')) do
      if Root is TJSONObject then
        Walk(TJSONObject(Root), '', 0);
    Id := JsonStr(Data, 'leafId');
    while (Id <> '') and not OnPath.ContainsKey(Id) do
    begin
      OnPath.Add(Id, True);
      if not Parents.TryGetValue(Id, Id) then
        Break;
    end;
    for Index := 0 to Lines.Count - 1 do
    begin
      Item := Lines[Index];
      Item.OnPath := OnPath.ContainsKey(Item.EntryId);
      Items := Items + [Item];
    end;
  finally
    Lines.Free;
    OnPath.Free;
    Parents.Free;
    Obj.Free;
  end;
end;

function ResponseText(const Line: string): string;
var
  Obj: TJSONObject;
begin
  Obj := JsonObject(Line);
  try
    Result := JsonStr(DataOf(Obj), 'text');
  finally
    Obj.Free;
  end;
end;

function LastCodeBlock(const Text: string): string;
var
  Lines: TArray<string>;
  Index, Start: Integer;
begin
  Result := '';
  Lines := Text.Replace(#13#10, #10).Split([#10]);
  Start := -1;
  for Index := 0 to High(Lines) do
    if Lines[Index].TrimLeft.StartsWith('```') then
      if Start < 0 then
        Start := Index
      else
      begin
        Result := string.Join(sLineBreak, Lines, Start + 1, Index - Start - 1);
        Start := -1;
      end;
end;

function ToolCallsOf(Content: TJSONValue): string;
var
  Part: TJSONValue;
begin
  Result := '';
  if Content is TJSONArray then
    for Part in TJSONArray(Content) do
      if (Part is TJSONObject) and (JsonStr(TJSONObject(Part), 'type') = 'toolCall') then
        Result := Result + '- `' + JsonStr(TJSONObject(Part), 'name') + '`' + sLineBreak;
end;

function TranscriptMarkdown(const Line: string): string;
var
  Obj, Data, Msg: TJSONObject;
  Item: TJSONValue;
  Role, Text, Calls: string;
begin
  Result := '';
  Obj := JsonObject(Line);
  try
    Data := DataOf(Obj);
    if (Data = nil) or not (Data.GetValue('messages') is TJSONArray) then
      Exit;
    for Item in TJSONArray(Data.GetValue('messages')) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Msg := TJSONObject(Item);
      Role := JsonStr(Msg, 'role');
      Text := Trim(ContentText(Msg.GetValue('content')));
      Calls := ToolCallsOf(Msg.GetValue('content'));
      if Role = 'toolResult' then
        Text := OneLine(Text, 400);
      if (Text = '') and (Calls = '') then
        Continue;
      Result := Result + '#### ' + Role;
      if Role = 'toolResult' then
        Result := Result + ' · ' + JsonStr(Msg, 'toolName');
      Result := Result + sLineBreak + sLineBreak + Text + sLineBreak + Calls + sLineBreak;
    end;
  finally
    Obj.Free;
  end;
end;

function SubagentListMarkdown(const Line: string): string;
var
  Obj, Data, Agent: TJSONObject;
  Item: TJSONValue;
begin
  Result := '';
  Obj := JsonObject(Line);
  try
    Data := DataOf(Obj);
    if (Data = nil) or not (Data.GetValue('subagents') is TJSONArray) then
      Exit;
    for Item in TJSONArray(Data.GetValue('subagents')) do
      if Item is TJSONObject then
      begin
        Agent := TJSONObject(Item);
        Result := Result + '- **' + JsonStr(Agent, 'id') + '** (' + JsonStr(Agent, 'agent') + ') ' +
          JsonStr(Agent, 'status') + ' — ' + OneLine(JsonStr(Agent, 'description') +
          JsonStr(Agent, 'assignment'), 120) + sLineBreak;
      end;
  finally
    Obj.Free;
  end;
end;

function ParseBash(const Line: string; out Bash: TBashResult): Boolean;
var
  Obj, Data: TJSONObject;
begin
  Bash := Default(TBashResult);
  Obj := JsonObject(Line);
  try
    Data := DataOf(Obj);
    Result := Data <> nil;
    if not Result then
      Exit;
    Bash.Output := JsonStr(Data, 'output');
    Bash.ExitCode := JsonInt(Data, 'exitCode', 0);
    Bash.Cancelled := IsJsonTrue(Data.GetValue('cancelled'));
    Bash.Truncated := IsJsonTrue(Data.GetValue('truncated'));
  finally
    Obj.Free;
  end;
end;

function ResponseDataClone(const Line: string): TJSONObject;
var
  Obj: TJSONObject;
begin
  Result := nil;
  Obj := JsonObject(Line);
  try
    if DataOf(Obj) <> nil then
      Result := TJSONObject(DataOf(Obj).Clone);
  finally
    Obj.Free;
  end;
end;

end.
