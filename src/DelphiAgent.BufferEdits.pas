unit DelphiAgent.BufferEdits;

{ Approved edits to open IDE buffers. Never saves. Refuses when the buffer moved since the
  prompt snapshot. Main thread only. }

interface

type
  IAgentApproval = interface
    ['{B1C2A8E4-7F0D-4C3A-9E21-6D5A4B3C2D10}']
    function ApproveBufferChange(const FileName, Preview: string): Boolean;
    procedure ShowConflict(const FileName: string);
  end;

const
  SEditCancelled = '{"ok":false,"cancelled":true}';

function LineCountOf(const Text: string): Integer;
function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
function ApplyEdit(const Path, Content: string; NewText: string; StartLine, EndLine: Integer;
  const Approval: IAgentApproval; out Problem: string): Boolean;

implementation

uses
  System.SysUtils, ToolsAPI, DelphiAgent.IdeContext, DelphiAgent.DirtyBuffers;

const
  SConflict = '충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다.';

function LineCountOf(const Text: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if Text = '' then
    Exit;
  Result := 1;
  for Index := 1 to Length(Text) do
    if Text[Index] = #10 then
      Inc(Result);
end;

function FindSource(const Path: string): IOTASourceEditor;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
begin
  Result := nil;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.FindModule(Path);
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Result) and
      SameText(Result.FileName, Path) then
      Exit;
  Result := nil;
end;

function LineByte(const Text: string; LineNo: Integer): Integer;
var
  Line, Index: Integer;
begin
  if LineNo <= 1 then
    Exit(0);
  Line := 1;
  Index := 1;
  while (Index <= Length(Text)) and (Line < LineNo) do
  begin
    if Text[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetByteCount(Copy(Text, 1, Index - 1));
end;

function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  Services: IOTAEditorServices;
  View: IOTAEditView;
  Current: TEditorText;
begin
  Result := False;
  Problem := '';
  if Text = '' then
  begin
    Problem := 'text가 비어 있습니다.';
    Exit;
  end;
  Services := BorlandIDEServices as IOTAEditorServices;
  View := Services.TopView;
  if (View = nil) or (View.Position = nil) or (View.Buffer = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  Current := CurrentEditorText;
  if SnapshotConflicts(Current.FileName, Current.Text) then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Current.FileName);
    Problem := SConflict;
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveBufferChange(Current.FileName, Text) then
  begin
    Problem := '사용자가 버퍼 반영을 승인하지 않았습니다.';
    Exit;
  end;
  if SnapshotConflicts(Current.FileName, BufferText(Current.FileName)) then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Current.FileName);
    Problem := SConflict;
    Exit;
  end;
  View := (BorlandIDEServices as IOTAEditorServices).TopView;
  if (View = nil) or (View.Position = nil) then
  begin
    Problem := '활성 에디터가 없습니다.';
    Exit;
  end;
  View.Position.InsertText(Text);
  Result := True;
end;

function ApplyEdit(const Path, Content: string; NewText: string; StartLine, EndLine: Integer;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Current, Preview: string;
  StartPos, EndPos: Integer;
  Source: IOTASourceEditor;
  Writer: IOTAEditWriter;
  Bytes: TBytes;
begin
  Result := False;
  Problem := '';
  Source := FindSource(Path);
  if Source = nil then
  begin
    Problem := '열린 버퍼가 없습니다.';
    Exit;
  end;
  Current := BufferText(Path);
  if Content <> '' then
    Preview := Content
  else if (StartLine > 0) and (EndLine >= StartLine) then
  begin
    { Line-range edits replace whole lines: keep the line break before the next line. }
    if (NewText <> '') and not NewText.EndsWith(#10) and (EndLine < LineCountOf(Current)) then
      NewText := NewText + sLineBreak;
    Preview := NewText;
  end
  else
  begin
    Problem := 'content 또는 줄 범위가 없습니다.';
    Exit;
  end;
  if SnapshotConflicts(Path, Current) then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Path);
    Problem := SConflict;
    Exit;
  end;
  if (Approval = nil) or not Approval.ApproveBufferChange(Path, Preview) then
  begin
    Problem := SEditCancelled;
    Exit;
  end;
  { Byte offsets below come from Current; refuse if the buffer moved while the dialog was up. }
  if BufferText(Path) <> Current then
  begin
    if Approval <> nil then
      Approval.ShowConflict(Path);
    Problem := SConflict;
    Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(Preview + #0);
  Writer := Source.CreateUndoableWriter;
  try
    if Content <> '' then
    begin
      StartPos := 0;
      EndPos := TEncoding.UTF8.GetByteCount(Current);
    end
    else
    begin
      StartPos := LineByte(Current, StartLine);
      EndPos := LineByte(Current, EndLine + 1);
    end;
    Writer.CopyTo(StartPos);
    Writer.DeleteTo(EndPos);
    Writer.Insert(PAnsiChar(Bytes));
  finally
    Writer := nil;
  end;
  Result := True;
end;

end.
