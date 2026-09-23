unit DelphiAgent.RpcEvents;

{ Agent session events from omp stdout, reduced to what the chat shows. No VCL. }

interface

uses
  System.SysUtils;

type
  TAgentEventKind = (aekNone, aekAgentStart, aekAgentEnd, aekThinking, aekThinkingEnd, aekTextDelta,
    aekTextEnd, aekToolCallStart, aekToolCallDelta, aekToolStart, aekToolUpdate, aekToolEnd,
    aekNotice, aekCompactionStart, aekCompactionEnd, aekRetryStart, aekRetryEnd, aekFallback,
    aekSubagent, aekError);

  { Subagent: ToolId = id, ToolName = agent, Detail = description, Text = last intent,
    Level = status, Count = tool calls. Retry/fallback: Text is the Korean line to show. }
  TAgentEvent = record
    Kind: TAgentEventKind;
    Text, ToolId, ToolName, Detail, Level: string;
    Count: Integer;
    IsError, IsTerminal: Boolean;
  end;

function ParseAgentEvent(const Line: string): TAgentEvent;
function ToolResultPreview(const Text: string; MaxChars: Integer): string;

implementation

uses
  System.JSON, System.Generics.Collections, DelphiAgent.RpcJson;

function ResolveToolName(const ToolName: string; Args: TJSONObject): string;
var
  Path: string;
begin
  Result := ToolName;
  if ((ToolName = 'write') or (ToolName = 'read')) and (Args <> nil) then
  begin
    Path := JsonStr(Args, 'path');
    if Path.StartsWith('xd://') then
      Result := Copy(Path, Length('xd://') + 1, MaxInt);
  end;
end;

function ToolDetail(Obj, Args: TJSONObject; const RawName: string): string;
begin
  Result := JsonStr(Obj, 'intent');
  if (Result = '') and (Args <> nil) then
  begin
    Result := JsonStr(Args, 'intent');
    if Result = '' then
      Result := JsonStr(Args, 'i');
    if Result = '' then
      if RawName = 'bash' then
        Result := JsonStr(Args, 'command')
      else if (RawName = 'read') or (RawName = 'write') or (RawName = 'edit') then
        Result := JsonStr(Args, 'path');
  end;
  Result := CollapseWhitespace(Result);
  if Length(Result) > 160 then
    Result := Copy(Result, 1, 159) + '…';
end;

{ The tool call content part the stream event is about. }
function StreamPart(Event: TJSONObject): TJSONObject;
var
  Content: TJSONValue;
  Index: Integer;
begin
  Result := JsonChild(Event, 'toolCall');
  if Result <> nil then
    Exit;
  Content := nil;
  if JsonChild(Event, 'partial') <> nil then
    Content := JsonChild(Event, 'partial').GetValue('content');
  if not (Content is TJSONArray) or (TJSONArray(Content).Count = 0) then
    Exit;
  Index := JsonInt(Event, 'contentIndex', 0);
  if (Index < 0) or (Index >= TJSONArray(Content).Count) then
    Index := 0;
  if TJSONArray(Content).Items[Index] is TJSONObject then
    Result := TJSONObject(TJSONArray(Content).Items[Index]);
end;

procedure ReadMessageUpdate(Obj: TJSONObject; var Event: TAgentEvent);
var
  Stream, Part: TJSONObject;
  SubType: string;
begin
  Stream := JsonChild(Obj, 'assistantMessageEvent');
  SubType := JsonStr(Stream, 'type');
  if SubType = 'text_delta' then
  begin
    Event.Kind := aekTextDelta;
    Event.Text := JsonStr(Stream, 'delta');
  end
  else if SubType = 'text_end' then
    Event.Kind := aekTextEnd
  else if (SubType = 'thinking_start') or (SubType = 'thinking_delta') then
  begin
    Event.Kind := aekThinking;
    Event.Text := JsonStr(Stream, 'delta');
  end
  else if SubType = 'thinking_end' then
    Event.Kind := aekThinkingEnd
  else if (SubType = 'toolcall_start') or (SubType = 'toolcall_delta') then
  begin
    if SubType = 'toolcall_start' then
      Event.Kind := aekToolCallStart
    else
      Event.Kind := aekToolCallDelta;
    Part := StreamPart(Stream);
    Event.ToolName := JsonStr(Part, 'name');
    Event.ToolId := JsonStr(Part, 'id');
    Event.Text := JsonStr(Stream, 'delta');
  end;
end;

procedure ReadTool(Obj: TJSONObject; const EvType: string; var Event: TAgentEvent);
var
  Args: TJSONObject;
  RawName: string;
begin
  Args := JsonChild(Obj, 'args');
  Event.ToolId := JsonStr(Obj, 'toolCallId');
  RawName := JsonStr(Obj, 'toolName');
  Event.ToolName := ResolveToolName(RawName, Args);
  if EvType = 'tool_execution_start' then
  begin
    Event.Kind := aekToolStart;
    Event.Detail := ToolDetail(Obj, Args, RawName);
  end
  else if EvType = 'tool_execution_update' then
  begin
    Event.Kind := aekToolUpdate;
    if JsonChild(Obj, 'partialResult') <> nil then
      Event.Text := ContentText(JsonChild(Obj, 'partialResult').GetValue('content'));
  end
  else
  begin
    Event.Kind := aekToolEnd;
    Event.IsError := IsJsonTrue(Obj.GetValue('isError'));
    if JsonChild(Obj, 'result') <> nil then
      Event.Text := ContentText(JsonChild(Obj, 'result').GetValue('content'))
    else
      Event.Text := JsonStr(Obj, 'result');
  end;
end;

procedure ReadSubagent(Obj: TJSONObject; var Event: TAgentEvent);
var
  Payload, Progress: TJSONObject;
begin
  Payload := JsonChild(Obj, 'payload');
  if Payload = nil then
    Exit;
  Progress := JsonChild(Payload, 'progress');
  if Progress = nil then
    Progress := Payload;
  Event.Kind := aekSubagent;
  Event.ToolId := JsonStr(Progress, 'id');
  Event.ToolName := JsonStr(Progress, 'agent');
  Event.Detail := CollapseWhitespace(JsonStr(Progress, 'description'));
  Event.Text := CollapseWhitespace(JsonStr(Progress, 'lastIntent'));
  Event.Level := JsonStr(Progress, 'status');
  Event.Count := JsonInt(Progress, 'toolCount', 0);
  if Event.ToolId = '' then
    Event.Kind := aekNone;
end;

procedure ReadRetry(Obj: TJSONObject; const EvType: string; var Event: TAgentEvent);
begin
  if EvType = 'auto_retry_start' then
  begin
    Event.Kind := aekRetryStart;
    Event.Text := Format('다시 시도 %d/%d · %d초 후 · %s', [JsonInt(Obj, 'attempt'),
      JsonInt(Obj, 'maxAttempts'), (JsonInt(Obj, 'delayMs') + 999) div 1000,
      CollapseWhitespace(JsonStr(Obj, 'errorMessage'))]);
  end
  else if EvType = 'auto_retry_end' then
  begin
    Event.Kind := aekRetryEnd;
    Event.IsError := IsJsonFalse(Obj.GetValue('success'));
    if Event.IsError then
      Event.Text := '다시 시도 실패: ' + CollapseWhitespace(JsonStr(Obj, 'finalError'))
    else
      Event.Text := Format('다시 시도 성공 (%d번째)', [JsonInt(Obj, 'attempt')]);
  end
  else if EvType = 'retry_fallback_applied' then
  begin
    Event.Kind := aekFallback;
    Event.Text := Format('모델 대체: %s → %s', [JsonStr(Obj, 'from'), JsonStr(Obj, 'to')]);
  end
  else
  begin
    Event.Kind := aekFallback;
    Event.Text := '대체 모델로 성공: ' + JsonStr(Obj, 'model');
  end;
end;

function ParseAgentEvent(const Line: string): TAgentEvent;
var
  Obj: TJSONObject;
  EvType, Cmd, ErrText: string;
begin
  Result := Default(TAgentEvent);
  Obj := JsonObject(Line);
  if Obj = nil then
    Exit;
  try
    EvType := JsonStr(Obj, 'type');
    if EvType = 'agent_start' then
      Result.Kind := aekAgentStart
    else if EvType = 'agent_end' then
    begin
      Result.Kind := aekAgentEnd;
      Result.IsTerminal := not IsJsonFalse(Obj.GetValue('isTerminal'));
    end
    else if EvType = 'message_update' then
      ReadMessageUpdate(Obj, Result)
    else if (EvType = 'tool_execution_start') or (EvType = 'tool_execution_update') or
      (EvType = 'tool_execution_end') then
      ReadTool(Obj, EvType, Result)
    else if (EvType = 'subagent_lifecycle') or (EvType = 'subagent_progress') then
      ReadSubagent(Obj, Result)
    else if EvType = 'notice' then
    begin
      Result.Kind := aekNotice;
      Result.Text := JsonStr(Obj, 'message');
      Result.Level := JsonStr(Obj, 'level');
      if Result.Level = '' then
        Result.Level := 'info';
    end
    else if EvType = 'auto_compaction_start' then
      Result.Kind := aekCompactionStart
    else if EvType = 'auto_compaction_end' then
      Result.Kind := aekCompactionEnd
    else if (EvType = 'auto_retry_start') or (EvType = 'auto_retry_end') or
      (EvType = 'retry_fallback_applied') or (EvType = 'retry_fallback_succeeded') then
      ReadRetry(Obj, EvType, Result)
    else if EvType = 'extension_error' then
    begin
      Result.Kind := aekError;
      Result.Text := JsonStr(Obj, 'error');
    end
    else if (EvType = 'response') and IsJsonFalse(Obj.GetValue('success')) then
    begin
      Result.Kind := aekError;
      Cmd := JsonStr(Obj, 'command');
      ErrText := JsonStr(Obj, 'error');
      if Cmd <> '' then
        Result.Text := Cmd + ': ' + ErrText
      else
        Result.Text := ErrText;
    end;
  finally
    Obj.Free;
  end;
end;

function ToolResultPreview(const Text: string; MaxChars: Integer): string;
var
  S: string;
begin
  S := Trim(Text);
  if MaxChars <= 0 then
  begin
    if S = '' then
      Exit('');
    Exit(Format('… (%d자 생략)', [Length(S)]));
  end;
  if Length(S) <= MaxChars then
    Exit(S);
  Result := Copy(S, 1, MaxChars) + Format('… (%d자 생략)', [Length(S) - MaxChars]);
end;

end.
