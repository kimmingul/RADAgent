unit RpcEventsTests;

interface

uses
  TestCheck;

procedure RunRpcEventsTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Math, DelphiAgent.RpcEvents, DelphiAgent.RpcResponses;

procedure TestTextDelta(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello world"}}');
  Check(Ev.Kind = aekTextDelta, 'text_delta: Kind = aekTextDelta');
  Check(Ev.Text = 'Hello world', 'text_delta: Text = Hello world');
end;

procedure TestTextEnd(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"text_end","contentIndex":0,"content":"Hello world"}}');
  Check(Ev.Kind = aekTextEnd, 'text_end: Kind = aekTextEnd');
end;

procedure TestThinking(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"thinking..."}}');
  Check(Ev.Kind = aekThinking, 'thinking: Kind = aekThinking');
  Check(Ev.Text = 'thinking...', 'thinking: Text = thinking...');
end;

procedure TestToolCallStart(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"toolcall_start","contentIndex":0,"partial":{"role":"assistant","content":[{"type":"toolCall","id":"t1","name":"bash"}]}}}');
  Check(Ev.Kind = aekToolCallStart, 'toolcall_start: Kind = aekToolCallStart');
  Check(Ev.ToolName = 'bash', 'toolcall_start: ToolName = bash');
end;

procedure TestToolStartBash(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"toolu_014VCsj3MTMJK9VSxiibNsfG","toolName":"bash","args":{"command":"echo hi"},"intent":"Running echo hi"}');
  Check(Ev.Kind = aekToolStart, 'tool_start bash: Kind = aekToolStart');
  Check(Ev.ToolId = 'toolu_014VCsj3MTMJK9VSxiibNsfG', 'tool_start bash: ToolId match');
  Check(Ev.ToolName = 'bash', 'tool_start bash: ToolName match');
  Check(Ev.Detail = 'Running echo hi', 'tool_start bash: Detail = intent');

  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"toolu_b2","toolName":"bash","args":{"command":"git status"}}');
  Check(Ev.Detail = 'git status', 'tool_start bash: fallback to command');
end;

procedure TestXdWriteMapping(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"toolu_02","toolName":"write","args":{"path":"xd://rad.compile","content":"{}"}}');
  Check(Ev.Kind = aekToolStart, 'xd write: Kind = aekToolStart');
  Check(Ev.ToolId = 'toolu_02', 'xd write: ToolId match');
  Check(Ev.ToolName = 'rad.compile', 'xd write: ToolName mapped to rad.compile');
  Check(Ev.Detail = 'xd://rad.compile', 'xd write: Detail fallback to path');

  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"toolu_03","toolName":"read","args":{"path":"xd://rad.read_buffer"}}');
  Check(Ev.ToolName = 'rad.read_buffer', 'xd read: ToolName mapped to rad.read_buffer');
end;

procedure TestToolEndErrorAndText(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"tool_execution_end","toolCallId":"toolu_03","toolName":"bash","result":{"content":[{"type":"text","text":"Command failed: exit 1"}]},"isError":true}');
  Check(Ev.Kind = aekToolEnd, 'tool_end: Kind = aekToolEnd');
  Check(Ev.ToolId = 'toolu_03', 'tool_end: ToolId match');
  Check(Ev.ToolName = 'bash', 'tool_end: ToolName match');
  Check(Ev.IsError = True, 'tool_end: IsError = True');
  Check(Ev.Text = 'Command failed: exit 1', 'tool_end: Text match');

  Ev := ParseAgentEvent('{"type":"tool_execution_end","toolCallId":"toolu_04","toolName":"write","args":{"path":"xd://rad.compile"},"result":{"content":[{"type":"text","text":"Build ok"}]},"isError":false}');
  Check(Ev.ToolName = 'rad.compile', 'tool_end xd: ToolName mapped');
  Check(Ev.IsError = False, 'tool_end xd: IsError = False');
  Check(Ev.Text = 'Build ok', 'tool_end xd: Text match');
end;

procedure TestAgentEndIsTerminal(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"agent_end","messages":[],"isTerminal":false}');
  Check(Ev.Kind = aekAgentEnd, 'agent_end: Kind match');
  Check(Ev.IsTerminal = False, 'agent_end: isTerminal false -> False');

  Ev := ParseAgentEvent('{"type":"agent_end","messages":[]}');
  Check(Ev.Kind = aekAgentEnd, 'agent_end absent: Kind match');
  Check(Ev.IsTerminal = True, 'agent_end: isTerminal absent -> True');

  Ev := ParseAgentEvent('{"type":"agent_end","messages":[],"isTerminal":true}');
  Check(Ev.IsTerminal = True, 'agent_end: isTerminal true -> True');
end;

procedure TestNoticeAndErrors(const Check: TCheckProc);
var Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"notice","level":"warn","message":"disk space low"}');
  Check(Ev.Kind = aekNotice, 'notice: Kind match');
  Check(Ev.Text = 'disk space low', 'notice: Text match');
  Check(Ev.Level = 'warn', 'notice: Level match');

  Ev := ParseAgentEvent('{"type":"notice","message":"info msg"}');
  Check(Ev.Level = 'info', 'notice: default level info');

  Ev := ParseAgentEvent('{"type":"auto_compaction_start"}');
  Check(Ev.Kind = aekCompactionStart, 'auto_compaction_start match');
  Ev := ParseAgentEvent('{"type":"auto_compaction_end"}');
  Check(Ev.Kind = aekCompactionEnd, 'auto_compaction_end match');
  Ev := ParseAgentEvent('{"type":"auto_retry_start"}');
  Check(Ev.Kind = aekRetryStart, 'auto_retry_start match');
  Ev := ParseAgentEvent('{"type":"auto_retry_end"}');
  Check(Ev.Kind = aekRetryEnd, 'auto_retry_end match');

  Ev := ParseAgentEvent('{"type":"extension_error","error":"crash"}');
  Check(Ev.Kind = aekError, 'extension_error: Kind match');
  Check(Ev.Text = 'crash', 'extension_error: Text match');

  Ev := ParseAgentEvent('{"type":"response","command":"prompt","success":false,"error":"bad input"}');
  Check(Ev.Kind = aekError, 'response failure: Kind match');
  Check(Ev.Text = 'prompt: bad input', 'response failure: Text match');

  Ev := ParseAgentEvent('{"type":"response","command":"prompt","success":true}');
  Check(Ev.Kind = aekNone, 'response success: Kind aekNone');
end;

procedure TestAvailableCommands(const Check: TCheckProc);
var
  Cmds: TArray<TSlashCommand>;
  Ok: Boolean;
begin
  Ok := ParseAvailableCommands('{"type":"available_commands_update","commands":[{"name":"/compact","description":"Compact ctx","input":{"hint":"[h]"}},{"name":"clear","description":"Clear","input":{"hint":""}}]}', Cmds);
  Check(Ok, 'available_commands_update: Ok');
  Check(Length(Cmds) = 2, 'available_commands_update: count = 2');
  Check(Cmds[0].Name = 'compact', 'available_commands_update: leading slash stripped');
  Check(Cmds[0].Description = 'Compact ctx', 'available_commands_update: Description match');
  Check(Cmds[0].Hint = '[h]', 'available_commands_update: Hint match');
  Check(Cmds[1].Name = 'clear', 'available_commands_update: Name clear');

  Ok := ParseAvailableCommands('{"id":"req-3","type":"response","command":"get_available_commands","success":true,"data":{"commands":[{"name":"test","description":"Desc","hint":"H"}]}}', Cmds);
  Check(Ok, 'get_available_commands response: Ok');
  Check(Length(Cmds) = 1, 'get_available_commands response: count = 1');
  Check(Cmds[0].Name = 'test', 'get_available_commands response: Name match');
  Check(Cmds[0].Hint = 'H', 'get_available_commands response: Hint fallback');
end;

procedure TestStateInfo(const Check: TCheckProc);
var
  Info: TStateInfo;
  Ok: Boolean;
begin
  Ok := ParseStateInfo('{"id":"req-2","type":"response","command":"get_state","success":true,"data":{"model":{"id":"claude-opus-5-5","provider":"anthropic"},"sessionFile":"C:\\sess.jsonl","sessionName":"TestSession","cwd":"D:\\repo","isStreaming":false,"contextUsage":{"tokens":28613,"contextWindow":1000000,"percent":2.8613}}}', Info);
  Check(Ok, 'get_state: Ok');
  Check(Info.Provider = 'anthropic', 'get_state: Provider');
  Check(Info.ModelId = 'claude-opus-5-5', 'get_state: ModelId');
  Check(Info.SessionFile = 'C:\sess.jsonl', 'get_state: SessionFile');
  Check(Info.SessionName = 'TestSession', 'get_state: SessionName');
  Check(Info.Cwd = 'D:\repo', 'get_state: Cwd');
  Check(Info.IsStreaming = False, 'get_state: IsStreaming False');
  Check(Info.HasContext = True, 'get_state: HasContext True');
  Check(SameValue(Info.ContextPercent, 2.8613, 0.0001), 'get_state: ContextPercent');

  Ok := ParseStateInfo('{"id":"req-2","type":"response","command":"get_state","success":true,"data":{"model":{"id":"m1","provider":"p1"},"isStreaming":true}}', Info);
  Check(Ok, 'get_state without context: Ok');
  Check(Info.HasContext = False, 'get_state without context: HasContext False');
  Check(Info.IsStreaming = True, 'get_state: IsStreaming True');
end;

procedure TestMessagesPage(const Check: TCheckProc);
var
  Items: TArray<THistoryItem>;
  Cursor: string;
  Ok: Boolean;
begin
  Ok := ParseMessagesPage('{"id":"req-p","type":"response","command":"get_messages_page","success":true,"data":{"messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":[{"type":"text","text":"A"},{"type":"text","text":"B"}]},{"role":"system","content":"sys"},{"role":"user","content":""}],"nextCursor":"cur_1"}}', Items, Cursor);
  Check(Ok, 'get_messages_page: Ok');
  Check(Cursor = 'cur_1', 'get_messages_page: Cursor match');
  Check(Length(Items) = 2, 'get_messages_page: Length = 2');
  Check(Items[0].Role = 'user', 'get_messages_page: Item 0 Role');
  Check(Items[0].Text = 'Hi', 'get_messages_page: Item 0 Text');
  Check(Items[1].Role = 'assistant', 'get_messages_page: Item 1 Role');
  Check(Items[1].Text = 'A' + sLineBreak + 'B', 'get_messages_page: Item 1 Text joined');
end;

procedure TestMalformedJson(const Check: TCheckProc);
var
  Ev: TAgentEvent;
  Cmds: TArray<TSlashCommand>;
  Info: TStateInfo;
  Items: TArray<THistoryItem>;
  Cursor: string;
begin
  Ev := ParseAgentEvent('{broken json');
  Check(Ev.Kind = aekNone, 'malformed JSON: aekNone');
  Ev := ParseAgentEvent('');
  Check(Ev.Kind = aekNone, 'empty line: aekNone');
  Ev := ParseAgentEvent('   ');
  Check(Ev.Kind = aekNone, 'spaces line: aekNone');
  Ev := ParseAgentEvent('{"type":"unknown"}');
  Check(Ev.Kind = aekNone, 'unknown type: aekNone');

  Check(not ParseAvailableCommands('{bad', Cmds), 'malformed available commands: False');
  Check(not ParseStateInfo('{bad', Info), 'malformed state info: False');
  Check(not ParseMessagesPage('{bad', Items, Cursor), 'malformed messages page: False');
end;

procedure TestToolResultPreview(const Check: TCheckProc);
begin
  Check(ToolResultPreview('hello', 10) = 'hello', 'ToolResultPreview: short text');
  Check(ToolResultPreview('hello', 5) = 'hello', 'ToolResultPreview: exact length');
  Check(ToolResultPreview('1234567890', 5) = '12345… (5자 생략)', 'ToolResultPreview: capped with suffix');
  Check(ToolResultPreview('   abc   ', 5) = 'abc', 'ToolResultPreview: trimmed');
  Check(ToolResultPreview('abc', 0) = '… (3자 생략)', 'ToolResultPreview: zero max');
  Check(ToolResultPreview('   ', 5) = '', 'ToolResultPreview: whitespace only');
end;

procedure TestDetailCollapse(const Check: TCheckProc);
var
  Ev: TAgentEvent;
  LongCmd: string;
begin
  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"t1","toolName":"bash","args":{"command":"line1\n\t  line2\r\nline3"}}');
  Check(Ev.Detail = 'line1 line2 line3', 'Collapse detail whitespace/newlines');

  LongCmd := StringOfChar('x', 200);
  Ev := ParseAgentEvent('{"type":"tool_execution_start","toolCallId":"t2","toolName":"bash","args":{"command":"' + LongCmd + '"}}');
  Check(Length(Ev.Detail) = 160, 'Detail capped at 160 chars');
  Check(Ev.Detail.EndsWith('…'), 'Detail capped with ellipsis');
end;

procedure TestStreamingEvents(const Check: TCheckProc);
var
  Ev: TAgentEvent;
begin
  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","contentIndex":1,"delta":"{\"pa","partial":{"content":[{"type":"thinking","thinking":"x"},{"type":"toolCall","id":"toolu_9","name":"write"}]}}}');
  Check(Ev.Kind = aekToolCallDelta, 'toolcall_delta: Kind');
  Check((Ev.ToolId = 'toolu_9') and (Ev.ToolName = 'write'), 'toolcall_delta: part at contentIndex');
  Check(Ev.Text = '{"pa', 'toolcall_delta: delta text');

  Ev := ParseAgentEvent('{"type":"message_update","assistantMessageEvent":{"type":"thinking_end"}}');
  Check(Ev.Kind = aekThinkingEnd, 'thinking_end: Kind');

  Ev := ParseAgentEvent('{"type":"tool_execution_update","toolCallId":"t5","toolName":"bash","partialResult":{"content":[{"type":"text","text":"line 1\n"}]}}');
  Check((Ev.Kind = aekToolUpdate) and (Ev.ToolId = 't5') and (Ev.Text = 'line 1'#10), 'tool_execution_update: partial text');

  Ev := ParseAgentEvent('{"type":"subagent_progress","payload":{"index":0,"agent":"scout","progress":{"id":"Counter","agent":"scout","status":"running","description":"Count files","lastIntent":"Listing\nfiles","toolCount":3}}}');
  Check((Ev.Kind = aekSubagent) and (Ev.ToolId = 'Counter') and (Ev.ToolName = 'scout'), 'subagent_progress: id and agent');
  Check((Ev.Level = 'running') and (Ev.Count = 3) and (Ev.Text = 'Listing files'), 'subagent_progress: status, tools, intent');
  Ev := ParseAgentEvent('{"type":"subagent_lifecycle","payload":{"id":"Counter","agent":"scout","status":"completed"}}');
  Check((Ev.Kind = aekSubagent) and (Ev.Level = 'completed'), 'subagent_lifecycle: status from payload');

  Ev := ParseAgentEvent('{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2500,"errorMessage":"overloaded"}');
  Check(Ev.Text = '다시 시도 1/3 · 3초 후 · overloaded', 'auto_retry_start: text');
  Ev := ParseAgentEvent('{"type":"retry_fallback_applied","from":"a/x","to":"b/y","role":"default"}');
  Check((Ev.Kind = aekFallback) and (Ev.Text = '모델 대체: a/x → b/y'), 'retry_fallback_applied: text');
end;

procedure TestSettingsResponses(const Check: TCheckProc);
var
  Models, Levels: TArray<string>;
  Providers: TArray<TLoginProvider>;
  Info: TStateInfo;
begin
  Check(ParseModelList('{"type":"response","command":"get_available_models","success":true,"data":{"models":[{"id":"m2","provider":"p"},{"id":"m1","provider":"p"},{"id":"m1","provider":"p"}]}}', Models) and
    (Length(Models) = 2) and (Models[0] = 'p/m1'), 'get_available_models: sorted unique selectors');
  Check(ParseThinkingLevels('{"type":"response","command":"get_available_thinking_levels","success":true,"data":{"levels":["off","high"]}}', Levels) and
    (Length(Levels) = 2) and (Levels[1] = 'high'), 'get_available_thinking_levels');
  Check(ParseLoginProviders('{"type":"response","command":"get_login_providers","success":true,"data":{"providers":[{"id":"a","name":"A","available":true,"authenticated":true},{"id":"b","name":"B","available":false}]}}', Providers) and
    (Length(Providers) = 1) and Providers[0].Authenticated, 'get_login_providers: unavailable skipped');
  Check(not ParseModelList('{"type":"response","command":"get_available_models","success":false}', Models), 'failed response: False');
  Check(ParseStateInfo('{"type":"response","command":"get_state","success":true,"data":{"thinkingLevel":"low","todoPhases":[{"name":"P","tasks":[{"content":"A","status":"completed"},{"content":"B","status":"in_progress"}]}]}}', Info) and
    (Info.ThinkingLevel = 'low') and (Length(Info.Todos) = 2) and (Info.Todos[1].Status = 'in_progress'), 'get_state: thinking level and todos');
end;

procedure RunRpcEventsTests(const Check: TCheckProc);
begin
  TestTextDelta(Check);
  TestTextEnd(Check);
  TestThinking(Check);
  TestToolCallStart(Check);
  TestToolStartBash(Check);
  TestXdWriteMapping(Check);
  TestToolEndErrorAndText(Check);
  TestAgentEndIsTerminal(Check);
  TestNoticeAndErrors(Check);
  TestAvailableCommands(Check);
  TestStateInfo(Check);
  TestMessagesPage(Check);
  TestMalformedJson(Check);
  TestToolResultPreview(Check);
  TestDetailCollapse(Check);
  TestStreamingEvents(Check);
  TestSettingsResponses(Check);
end;

end.
