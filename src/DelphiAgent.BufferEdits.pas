unit DelphiAgent.BufferEdits;

{ Approved edits to open IDE buffers. Never saves. Refuses when the buffer moved since the
  prompt snapshot. Main thread only. }

interface

uses
  DelphiAgent.Approval;

function LineCountOf(const Text: string): Integer;
function InsertAtCaret(const Text: string; const Approval: IAgentApproval;
  out Problem: string): Boolean;
function ApplyEdit(const Path, Content: string; NewText: string; StartLine, EndLine: Integer;
  const Approval: IAgentApproval; out Problem: string): Boolean;

type
  TBufferEdit = record
    Path, Content, NewText: string;
    StartLine, EndLine: Integer;
  end;

{ rad.apply_edits: every edit previewed as one diff, one approval, then each file written once. }
function ApplyEdits(const Edits: TArray<TBufferEdit>; const Approval: IAgentApproval;
  out Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, ToolsAPI,
  DelphiAgent.IdeContext, DelphiAgent.DirtyBuffers;

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
  StartRow: Integer;
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
  if (Approval = nil) or not Approval.ApproveChange(Current.FileName, '', Text) then
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
  StartRow := View.CursorPos.Line;
  View.Position.InsertText(Text);
  Result := True;
  UpdateSnapshot(Current.FileName, BufferText(Current.FileName));
  Approval.ChangeApplied(Current.FileName, '', Text, StartRow);
end;

{ Char index (1-based) where LineNo starts; past the end when LineNo is beyond the text. }
function LineChar(const Text: string; LineNo: Integer): Integer;
var
  Line: Integer;
begin
  Result := 1;
  Line := 1;
  while (Result <= Length(Text)) and (Line < LineNo) do
  begin
    if Text[Result] = #10 then
      Inc(Line);
    Inc(Result);
  end;
end;

{ The buffer text as it will be after the edit, for the approval diff. }
function AfterEdit(const Current, Content, Replacement: string; StartLine, EndLine: Integer): string;
begin
  if Content <> '' then
    Exit(Content);
  Result := Copy(Current, 1, LineChar(Current, StartLine) - 1) + Replacement +
    Copy(Current, LineChar(Current, EndLine + 1), MaxInt);
end;

procedure ReplaceBytes(const Source: IOTASourceEditor; StartPos, EndPos: Integer; const Text: string);
var
  Writer: IOTAEditWriter;
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(Text + #0);
  Writer := Source.CreateUndoableWriter;
  try
    Writer.CopyTo(StartPos);
    Writer.DeleteTo(EndPos);
    Writer.Insert(PAnsiChar(Bytes));
  finally
    Writer := nil;
  end;
end;

{ Writes After over Current by replacing only the part that differs. Rewriting the whole buffer
  left the editor's final line break in place and added one more on every edit. }
procedure ReplaceChanged(const Source: IOTASourceEditor; const Current, After: string);
var
  Prefix, Suffix, MaxSuffix: Integer;
begin
  Prefix := 0;
  while (Prefix < Length(Current)) and (Prefix < Length(After)) and
    (Current[Prefix + 1] = After[Prefix + 1]) do
    Inc(Prefix);
  { Keep CRLF pairs whole. }
  if (Prefix > 0) and (Current[Prefix] = #13) then
    Dec(Prefix);
  MaxSuffix := Length(Current) - Prefix;
  if Length(After) - Prefix < MaxSuffix then
    MaxSuffix := Length(After) - Prefix;
  Suffix := 0;
  while (Suffix < MaxSuffix) and (Current[Length(Current) - Suffix] = After[Length(After) - Suffix]) do
    Inc(Suffix);
  { A suffix starting at the LF of a CRLF would split the pair; leave the LF in the middle. }
  if (Suffix > 0) and (Current[Length(Current) - Suffix + 1] = #10) and
    (Length(Current) - Suffix > 0) and (Current[Length(Current) - Suffix] = #13) then
    Dec(Suffix);
  ReplaceBytes(Source, TEncoding.UTF8.GetByteCount(Copy(Current, 1, Prefix)),
    TEncoding.UTF8.GetByteCount(Copy(Current, 1, Length(Current) - Suffix)),
    Copy(After, Prefix + 1, Length(After) - Prefix - Suffix));
end;

{ Line-range edits replace whole lines: keep the line break before the next line. }
function RangeText(const Current, NewText: string; EndLine: Integer): string;
begin
  Result := NewText;
  if (Result <> '') and not Result.EndsWith(#10) and (EndLine < LineCountOf(Current)) then
    Result := Result + sLineBreak;
end;

function ApplyEdit(const Path, Content: string; NewText: string; StartLine, EndLine: Integer;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Current, Preview: string;
  Source: IOTASourceEditor;
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
    Preview := RangeText(Current, NewText, EndLine)
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
  if (Approval = nil) or not Approval.ApproveChange(Path, Current,
    AfterEdit(Current, Content, Preview, StartLine, EndLine)) then
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
  ReplaceChanged(Source, Current, AfterEdit(Current, Content, Preview, StartLine, EndLine));
  Result := True;
  UpdateSnapshot(Path, BufferText(Path));
  Approval.ChangeApplied(Path, Current, AfterEdit(Current, Content, Preview, StartLine, EndLine), 0);
end;

{ One file's edits applied bottom-up on its text, so every line number refers to the original. }
function EditedText(const Current: string; Edits: TArray<TBufferEdit>; out Problem: string): string;
var
  Index: Integer;
begin
  Problem := '';
  if (Length(Edits) = 1) and (Edits[0].Content <> '') then
    Exit(Edits[0].Content);
  TArray.Sort<TBufferEdit>(Edits, TComparer<TBufferEdit>.Construct(
    function(const A, B: TBufferEdit): Integer
    begin
      Result := B.StartLine - A.StartLine;
    end));
  Result := Current;
  for Index := 0 to High(Edits) do
  begin
    if (Edits[Index].Content <> '') or (Edits[Index].StartLine < 1) or
      (Edits[Index].EndLine < Edits[Index].StartLine) then
    begin
      Problem := '편집마다 startLine..endLine과 newText가 필요합니다(content는 파일당 하나만): ' +
        Edits[Index].Path;
      Exit;
    end;
    if (Index > 0) and (Edits[Index].EndLine >= Edits[Index - 1].StartLine) then
    begin
      Problem := '같은 파일의 편집 줄 범위가 겹칩니다: ' + Edits[Index].Path;
      Exit;
    end;
    Result := AfterEdit(Result, '', RangeText(Current, Edits[Index].NewText, Edits[Index].EndLine),
      Edits[Index].StartLine, Edits[Index].EndLine);
  end;
end;

function ApplyEdits(const Edits: TArray<TBufferEdit>; const Approval: IAgentApproval;
  out Problem: string): Boolean;
var
  Paths: TList<string>;
  Files: TDictionary<string, TArray<TBufferEdit>>;
  Currents, Afters: TArray<string>;
  Edit: TBufferEdit;
  Group: TArray<TBufferEdit>;
  BeforeAll, AfterAll, Path: string;
  Index: Integer;
begin
  Result := False;
  Problem := '';
  if Length(Edits) = 0 then
  begin
    Problem := 'edits가 비어 있습니다.';
    Exit;
  end;
  Paths := TList<string>.Create;
  Files := TDictionary<string, TArray<TBufferEdit>>.Create;
  try
    for Edit in Edits do
    begin
      if not Files.TryGetValue(LowerCase(Edit.Path), Group) then
        Paths.Add(Edit.Path);
      Files.AddOrSetValue(LowerCase(Edit.Path), Group + [Edit]);
    end;
    SetLength(Currents, Paths.Count);
    SetLength(Afters, Paths.Count);
    for Index := 0 to Paths.Count - 1 do
    begin
      Path := Paths[Index];
      if FindSource(Path) = nil then
      begin
        Problem := '열린 버퍼가 없습니다(rad.open_buffer로 먼저 여세요): ' + Path;
        Exit;
      end;
      Currents[Index] := BufferText(Path);
      if SnapshotConflicts(Path, Currents[Index]) then
      begin
        if Approval <> nil then
          Approval.ShowConflict(Path);
        Problem := SConflict + ' ' + Path;
        Exit;
      end;
      Afters[Index] := EditedText(Currents[Index], Files[LowerCase(Path)], Problem);
      if Problem <> '' then
        Exit;
      BeforeAll := BeforeAll + '=== ' + Path + ' ===' + sLineBreak + Currents[Index] + sLineBreak;
      AfterAll := AfterAll + '=== ' + Path + ' ===' + sLineBreak + Afters[Index] + sLineBreak;
    end;
    if (Approval = nil) or not Approval.ApproveChange(Format('%d개 파일', [Paths.Count]),
      BeforeAll, AfterAll) then
    begin
      Problem := SEditCancelled;
      Exit;
    end;
    for Index := 0 to Paths.Count - 1 do
      if BufferText(Paths[Index]) <> Currents[Index] then
      begin
        if Approval <> nil then
          Approval.ShowConflict(Paths[Index]);
        Problem := SConflict + ' ' + Paths[Index];
        Exit;
      end;
    for Index := 0 to Paths.Count - 1 do
    begin
      ReplaceChanged(FindSource(Paths[Index]), Currents[Index], Afters[Index]);
      UpdateSnapshot(Paths[Index], BufferText(Paths[Index]));
      Approval.ChangeApplied(Paths[Index], Currents[Index], Afters[Index], 0);
    end;
    Result := True;
  finally
    Files.Free;
    Paths.Free;
  end;
end;

end.
