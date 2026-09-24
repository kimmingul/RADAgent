unit DelphiAgent.ChatApproval;

{ The chat's IAgentApproval: approval card in the chat (a modal dialog when no chat page is
  attached), conflict notice, and a file card for every edit that reached a buffer. Main thread only. }

interface

uses
  DelphiAgent.Approval;

type
  { How often IDE changes ask follows the omp approval mode of the project:
    always-ask = every change, write = once per turn, yolo = never (still unsaved, undoable). }
  TChatApproval = class(TInterfacedObject, IAgentApproval)
  private
    { Turn (activity start tick) whose changes the user approved as a whole. }
    FApprovedTurn: UInt64;
  public
    function ApproveChange(const Target, Before, After: string): Boolean;
    procedure ChangeApplied(const FileName, Before, After: string; Line: Integer);
  end;

implementation

uses
  System.SysUtils, DelphiAgent.ApprovalDialog, DelphiAgent.ChatAttention, DelphiAgent.ChatSession,
  DelphiAgent.ChatPageMessages, DelphiAgent.LineDiff, DelphiAgent.ChatApprovalCard;

function TChatApproval.ApproveChange(const Target, Before, After: string): Boolean;
var
  Session: TChatSession;
  PerTurn: Boolean;
  Caption: string;
begin
  Session := ChatSession;
  if Session.Catalog.ApprovalMode = 'yolo' then
    Exit(True);
  PerTurn := (Session.Catalog.ApprovalMode = 'write') and Session.Busy;
  if PerTurn and (FApprovedTurn = Session.Activity.StartTick) then
    Exit(True);
  RequestAttention;
  Caption := Target;
  if PerTurn then
    Caption := '[이번 턴의 나머지 IDE 변경도 함께 승인] ' + Target;
  if InChatApprovals then
    Result := AskInChat(Caption, Before, After)
  else
    Result := AskApprovalDiff(Caption, Before, After);
  if Result and PerTurn then
    FApprovedTurn := Session.Activity.StartTick;
end;

procedure TChatApproval.ChangeApplied(const FileName, Before, After: string; Line: Integer);
var
  Diff: TArray<TDiffLine>;
  Index, Added, Removed, First: Integer;
begin
  Added := 0;
  Removed := 0;
  First := 0;
  if Before = '' then
  begin
    Added := Length(SplitLines(After));
    First := Line;
  end
  else
  begin
    Diff := DiffLines(Before, After);
    { New-file line of the first change: same and added lines advance it. }
    Line := 1;
    for Index := 0 to High(Diff) do
      case Diff[Index].Kind of
        dkSame:
          Inc(Line);
        dkAdded:
          begin
            Inc(Added);
            if First = 0 then
              First := Line;
            Inc(Line);
          end;
        dkRemoved:
          begin
            Inc(Removed);
            if First = 0 then
              First := Line;
          end;
      end;
  end;
  ChatSession.Emit(PageFileChange(FileName, Added, Removed, First));
end;

end.
