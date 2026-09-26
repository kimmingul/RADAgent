unit RADAgent.BufferEdits;

{ rad.insert_at_caret: approved text at the editor caret (saved afterwards like every changing
  rad.* tool, see ChatActions.HandleHostToolCall). Other code changes are omp's own edits on
  disk, which RADAgent.IdeFiles loads back into the IDE. Main thread only. }

interface

uses
  RADAgent.Approval;

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;

implementation

uses
  System.SysUtils, ToolsAPI, RADAgent.IdeContext;

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  View: IOTAEditView;
  TargetFile: string;
  TargetLine, TargetCol, StartRow: Integer;
begin
  Result := False;
  Problem := '';
  if Text = '' then
  begin
    Problem := 'Text cannot be empty.';
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Problem := 'No active editor.';
    Exit;
  end;
  TargetFile := View.Buffer.FileName;
  TargetLine := View.CursorPos.Line;
  TargetCol := View.CursorPos.Col;
  if (Approval = nil) or not Approval.ApproveChange(TargetFile, '', Text) then
  begin
    Problem := 'User did not approve applying changes to buffer.';
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) or (View.Buffer = nil) or
    not SameText(View.Buffer.FileName, TargetFile) or
    (View.CursorPos.Line <> TargetLine) or (View.CursorPos.Col <> TargetCol) then
  begin
    Problem := 'The editor or caret changed while waiting for approval; ask again.';
    Exit;
  end;
  StartRow := View.CursorPos.Line;
  View.Position.InsertText(Text);
  Result := True;
  Approval.ChangeApplied(View.Buffer.FileName, '', Text, StartRow);
end;

end.
