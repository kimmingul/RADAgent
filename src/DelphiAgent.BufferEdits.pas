unit DelphiAgent.BufferEdits;

{ rad.insert_at_caret: approved text at the editor caret (saved afterwards like every changing
  rad.* tool, see ChatActions.HandleHostToolCall). Other code changes are omp's own edits on
  disk, which DelphiAgent.IdeFiles loads back into the IDE. Main thread only. }

interface

uses
  DelphiAgent.Approval;

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;

implementation

uses
  System.SysUtils, ToolsAPI, DelphiAgent.IdeContext;

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  View: IOTAEditView;
  Current: TEditorText;
  StartRow: Integer;
begin
  Result := False;
  Problem := '';
  if Text = '' then
  begin
    Problem := 'text가 비어 있습니다.';
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) or (View.Buffer = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  Current := CurrentEditorText;
  if (Approval = nil) or not Approval.ApproveChange(Current.FileName, '', Text) then
  begin
    Problem := '사용자가 버퍼 반영을 승인하지 않았습니다.';
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  StartRow := View.CursorPos.Line;
  View.Position.InsertText(Text);
  Result := True;
  Approval.ChangeApplied(Current.FileName, '', Text, StartRow);
end;

end.
