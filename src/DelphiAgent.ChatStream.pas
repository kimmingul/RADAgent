unit DelphiAgent.ChatStream;

{ Turns agent events into chat page messages (text, thinking, tools, subagents, notices). Live
  deltas go to the view only; the transcript keeps one message per finished block so a
  re-attached view replays compactly. The page decides what to show. No VCL. }

interface

uses
  System.Classes, System.Generics.Collections, DelphiAgent.RpcEvents, DelphiAgent.RpcResponses;

type
  TPagePost = procedure(const Json: string) of object;

  TChatStream = class
  private
    FPost: TPagePost;
    FTranscript: TStringList;
    FText, FThinking, FTodos: string;
    FInputs: TDictionary<string, string>;
    FStarts: TDictionary<string, UInt64>;
    FLastUpdate: TDictionary<string, UInt64>;
    procedure Flush;
  public
    { Post shows a message on the attached view (if any). }
    constructor Create(const Post: TPagePost);
    destructor Destroy; override;
    { Handles display events; returns False for events the session handles itself. }
    function Apply(const Event: TAgentEvent): Boolean;
    { Adds a message to the transcript and the view. }
    procedure Emit(const Json: string);
    procedure Clear;
    { Shows the todo list when it changed since the last call. }
    procedure ShowTodos(const Todos: TArray<TTodoItem>);
    { Everything a newly attached view needs, unfinished blocks included. }
    function Replay: TArray<string>;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows, DelphiAgent.ChatPageMessages;

const
  MaxTranscript = 4000;
  MaxInputChars = 20000;
  MaxUpdateChars = 8000;
  UpdateIntervalMs = 250;

constructor TChatStream.Create(const Post: TPagePost);
begin
  inherited Create;
  FPost := Post;
  FTranscript := TStringList.Create;
  FInputs := TDictionary<string, string>.Create;
  FStarts := TDictionary<string, UInt64>.Create;
  FLastUpdate := TDictionary<string, UInt64>.Create;
end;

destructor TChatStream.Destroy;
begin
  FLastUpdate.Free;
  FStarts.Free;
  FInputs.Free;
  FTranscript.Free;
  inherited Destroy;
end;

{ Unfinished text/thinking enter the transcript as one message each; the view already has them. }
procedure TChatStream.Flush;
begin
  if FThinking <> '' then
    FTranscript.Add(PageThinking(FThinking));
  if FText <> '' then
    FTranscript.Add(PageDelta(FText));
  FThinking := '';
  FText := '';
end;

procedure TChatStream.Emit(const Json: string);
begin
  Flush;
  FTranscript.Add(Json);
  while FTranscript.Count > MaxTranscript do
    FTranscript.Delete(0);
  FPost(Json);
end;

procedure TChatStream.ShowTodos(const Todos: TArray<TTodoItem>);
var
  Json: string;
begin
  Json := PageTodos(Todos);
  if (Json <> FTodos) and ((FTodos <> '') or (Length(Todos) > 0)) then
    Emit(Json);
  FTodos := Json;
end;

procedure TChatStream.Clear;
begin
  FTranscript.Clear;
  FTodos := '';
  FText := '';
  FThinking := '';
  FInputs.Clear;
  FStarts.Clear;
  FLastUpdate.Clear;
end;

function TChatStream.Replay: TArray<string>;
begin
  Result := FTranscript.ToStringArray;
  if FThinking <> '' then
    Result := Result + [PageThinkingDelta(FThinking)];
  if FText <> '' then
    Result := Result + [PageDelta(FText)];
end;

function Tail(const Text: string; MaxChars: Integer): string;
begin
  if Length(Text) <= MaxChars then
    Result := Text
  else
    Result := '…' + Copy(Text, Length(Text) - MaxChars + 1, MaxChars);
end;

function TChatStream.Apply(const Event: TAgentEvent): Boolean;
var
  Input: string;
  Started, Last: UInt64;
begin
  Result := True;
  case Event.Kind of
    aekTextDelta:
      begin
        FText := FText + Event.Text;
        FPost(PageDelta(Event.Text));
      end;
    aekTextEnd:
      Emit(PageAssistantEnd);
    aekThinking:
      if Event.Text <> '' then
      begin
        FThinking := FThinking + Event.Text;
        FPost(PageThinkingDelta(Event.Text));
      end;
    aekThinkingEnd:
      Emit(PageThinkingEnd);
    aekToolCallDelta:
      if (Event.ToolId <> '') and (Event.Text <> '') then
      begin
        FInputs.TryGetValue(Event.ToolId, Input);
        if Length(Input) < MaxInputChars then
          FInputs.AddOrSetValue(Event.ToolId, Input + Event.Text);
        FPost(PageToolInputDelta(Event.ToolId, Event.ToolName, Event.Text));
      end;
    aekToolStart:
      begin
        FInputs.TryGetValue(Event.ToolId, Input);
        FInputs.Remove(Event.ToolId);
        FStarts.AddOrSetValue(Event.ToolId, GetTickCount64);
        Emit(PageToolStart(Event.ToolId, Event.ToolName, Event.Detail, Input));
      end;
    aekToolUpdate:
      begin
        { bash streams its whole output so far on each update; throttle and keep the tail. }
        if FLastUpdate.TryGetValue(Event.ToolId, Last) and (GetTickCount64 - Last < UpdateIntervalMs) then
          Exit;
        FLastUpdate.AddOrSetValue(Event.ToolId, GetTickCount64);
        FPost(PageToolUpdate(Event.ToolId, Tail(Event.Text, MaxUpdateChars)));
      end;
    aekToolEnd:
      begin
        if not FStarts.TryGetValue(Event.ToolId, Started) then
          Started := GetTickCount64;
        FStarts.Remove(Event.ToolId);
        FLastUpdate.Remove(Event.ToolId);
        Emit(PageToolEnd(Event.ToolId, not Event.IsError, GetTickCount64 - Started,
          ToolResultPreview(Event.Text, 20000)));
      end;
    aekSubagent:
      if Event.Level = 'running' then
        FPost(PageSubagent(Event))
      else
        Emit(PageSubagent(Event));
    aekNotice:
      { omp announces the rad.* devices on every start; the chat already knows them. Plain omp
        info notices get their own level so the page can hide them. }
      if not Event.Text.StartsWith('xd://: mounted') then
        if Event.Level = 'info' then
          Emit(PageNotice('omp', Event.Text))
        else
          Emit(PageNotice(Event.Level, Event.Text));
    aekError:
      Emit(PageNotice('error', Event.Text));
    aekCompactionStart:
      Emit(PageNotice('info', '대화가 길어져 압축합니다.'));
    aekRetryStart, aekFallback:
      Emit(PageNotice('retry', Event.Text));
    aekRetryEnd:
      if Event.IsError then
        Emit(PageNotice('error', Event.Text))
      else
        Emit(PageNotice('retry', Event.Text));
  else
    Result := False;
  end;
end;

end.
