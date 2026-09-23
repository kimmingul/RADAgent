unit DelphiAgent.ChatActivity;

{ What the agent is doing now, derived from RPC events. No VCL, no ToolsAPI. }

interface

uses
  DelphiAgent.RpcEvents;

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
    { Korean one-liner for the status bar, e.g. 도구 실행 중: rad.compile · 4초 }
    function Text: string;
    property State: TActivity read FState;
    { Tick the current turn started; identifies the turn while Busy. }
    property StartTick: UInt64 read FStartTick;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows;

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
    aekError:
      { A rejected prompt never starts a turn. }
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
    acIdle: Exit('대기');
    acWaiting: Result := '응답 기다리는 중';
    acThinking: Result := '생각하는 중';
    acWriting: Result := '답 쓰는 중';
    acPreparingTool: Result := '도구 준비 중: ' + FToolName;
    acRunningTool: Result := '도구 실행 중: ' + FToolName;
    acCompacting: Result := '대화 압축 중';
    acRetrying: Result := '다시 시도하는 중';
  end;
  Result := Result + ' · ' + IntToStr(ElapsedSeconds) + '초';
end;

end.
