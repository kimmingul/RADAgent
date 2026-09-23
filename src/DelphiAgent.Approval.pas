unit DelphiAgent.Approval;

{ User approval contract for every host tool that changes IDE state. The chat frame implements it. }

interface

type
  IAgentApproval = interface
    ['{B1C2A8E4-7F0D-4C3A-9E21-6D5A4B3C2D10}']
    { Target is the file or IDE area. Before '' means no diff: show After as is. True on approve. }
    function ApproveChange(const Target, Before, After: string): Boolean;
    procedure ShowConflict(const FileName: string);
  end;

const
  SEditCancelled = '{"ok":false,"cancelled":true}';

implementation

end.
