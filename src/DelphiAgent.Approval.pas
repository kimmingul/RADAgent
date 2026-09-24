unit DelphiAgent.Approval;

{ User approval contract for every host tool that changes IDE state. DelphiAgent.ChatApproval
  implements it for the chat. }

interface

type
  IAgentApproval = interface
    ['{B1C2A8E4-7F0D-4C3A-9E21-6D5A4B3C2D10}']
    { Target is the file or IDE area. Before '' means no diff: show After as is. True on approve. }
    function ApproveChange(const Target, Before, After: string): Boolean;
    { An approved edit reached the buffer. Before '' means text inserted at Line. }
    procedure ChangeApplied(const FileName, Before, After: string; Line: Integer);
  end;

const
  SEditCancelled = '{"ok":false,"cancelled":true}';

{ For a batch the user already approved as a whole: approves every step, forwards the rest. }
function PreApproved(const Approval: IAgentApproval): IAgentApproval;

implementation

type
  TPreApproved = class(TInterfacedObject, IAgentApproval)
  private
    FInner: IAgentApproval;
  public
    constructor Create(const Inner: IAgentApproval);
    function ApproveChange(const Target, Before, After: string): Boolean;
    procedure ChangeApplied(const FileName, Before, After: string; Line: Integer);
  end;

constructor TPreApproved.Create(const Inner: IAgentApproval);
begin
  inherited Create;
  FInner := Inner;
end;

function TPreApproved.ApproveChange(const Target, Before, After: string): Boolean;
begin
  Result := True;
end;

procedure TPreApproved.ChangeApplied(const FileName, Before, After: string; Line: Integer);
begin
  if FInner <> nil then
    FInner.ChangeApplied(FileName, Before, After, Line);
end;

function PreApproved(const Approval: IAgentApproval): IAgentApproval;
begin
  Result := TPreApproved.Create(Approval);
end;

end.
