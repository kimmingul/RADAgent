unit RADAgent.ChatActivity;

{ What the agent is doing now, derived from RPC events. No VCL, no ToolsAPI. }

interface

uses
  RADAgent.RpcEvents;

type
  TActivity = (acIdle, acWaiting, acThinking, acWriting, acPreparingTool, acRunningTool,
    acCompacting, acRetrying);

  TChatActivity = class
  private
    FState: TActivity;
    FToolName: string;
    FStartTick: UInt64;
    FRunningTools: Integer;
  public
    procedure PromptSent;
    procedure Apply(const Event: TAgentEvent);
    procedure Reset;
    function Busy: Boolean;
    function ElapsedSeconds: Integer;
    { Status bar text, e.g. Running tool: rad.compile · 4s }
    function Text: string;
    property State: TActivity read FState;
    { Tick the current turn started; identifies the turn while Busy. }
    property StartTick: UInt64 read FStartTick;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows, RADAgent.Lang;

procedure TChatActivity.PromptSent;
begin
  if FState = acIdle then
    FStartTick := GetTickCount64;
  FState := acWaiting;
end;

procedure TChatActivity.Reset;
begin
  FState := acIdle;
  FToolName := '';
  FRunningTools := 0;
end;

procedure TChatActivity.Apply(const Event: TAgentEvent);
begin
  case Event.Kind of
    aekAgentStart:
      if FState = acIdle then
      begin
        FStartTick := GetTickCount64;
        FState := acWaiting;
      end;
    aekAgentEnd:
      if Event.IsTerminal then
        Reset;
    aekThinking:
      if FRunningTools = 0 then
        FState := acThinking;
    aekTextDelta:
      if FRunningTools = 0 then
        FState := acWriting;
    aekToolCallStart:
      begin
        FToolName := Event.ToolName;
        FState := acPreparingTool;
      end;
    aekToolStart:
      begin
        Inc(FRunningTools);
        FToolName := Event.ToolName;
        FState := acRunningTool;
      end;
    aekToolEnd:
      begin
        if FRunningTools > 0 then
          Dec(FRunningTools);
        if FRunningTools = 0 then
          FState := acWaiting;
      end;
    aekCompactionStart:
      FState := acCompacting;
    aekRetryStart:
      FState := acRetrying;
    aekCompactionEnd, aekRetryEnd:
      if FState <> acIdle then
        FState := acWaiting;
    aekError, aekPromptLocal:
      { A rejected prompt, or a slash command omp handled itself, never starts a turn. }
      if FState = acWaiting then
        Reset;
  end;
end;

function TChatActivity.Busy: Boolean;
begin
  Result := FState <> acIdle;
end;

function TChatActivity.ElapsedSeconds: Integer;
begin
  if FState = acIdle then
    Exit(0);
  Result := Integer((GetTickCount64 - FStartTick) div 1000);
end;

function TChatActivity.Text: string;
begin
  case FState of
    acIdle: Exit(Tr('chatactivity.idle'));
    acWaiting: Result := Tr('chatactivity.waiting');
    acThinking: Result := Tr('chatactivity.thinking');
    acWriting: Result := Tr('chatactivity.writing');
    acPreparingTool: Result := TrF('chatactivity.preparingTool', [FToolName]);
    acRunningTool: Result := TrF('chatactivity.runningTool', [FToolName]);
    acCompacting: Result := Tr('chatactivity.compacting');
    acRetrying: Result := Tr('chatactivity.retrying');
  end;
  Result := TrF('chatactivity.elapsed', [Result, ElapsedSeconds]);
end;

end.
