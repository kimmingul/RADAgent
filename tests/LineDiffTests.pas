unit LineDiffTests;

{ Tests for RADAgent.LineDiff. }

interface

uses
  TestCheck;

procedure RunLineDiffTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Diagnostics, RADAgent.LineDiff;

procedure TestIdentical(const Check: TCheckProc);
var
  Diff: TArray<TDiffLine>;
  I: Integer;
  AllSame: Boolean;
begin
  Diff := DiffLines('Line1'#10'Line2'#10'Line3', 'Line1'#10'Line2'#10'Line3');
  Check(Length(Diff) = 3, 'Identical: length is 3');
  AllSame := True;
  for I := 0 to High(Diff) do
    if Diff[I].Kind <> dkSame then
      AllSame := False;
  Check(AllSame, 'Identical: all lines are dkSame');
  if Length(Diff) = 3 then
  begin
    Check(Diff[0].Text = 'Line1', 'Identical: line 0 text');
    Check(Diff[1].Text = 'Line2', 'Identical: line 1 text');
    Check(Diff[2].Text = 'Line3', 'Identical: line 2 text');
  end;
end;

procedure TestChangedMiddle(const Check: TCheckProc);
var
  Diff: TArray<TDiffLine>;
begin
  Diff := DiffLines('Prefix'#10'OldMiddle'#10'Suffix', 'Prefix'#10'NewMiddle'#10'Suffix');
  Check(Length(Diff) = 4, 'ChangedMiddle: length is 4');
  if Length(Diff) = 4 then
  begin
    Check((Diff[0].Kind = dkSame) and (Diff[0].Text = 'Prefix'), 'ChangedMiddle: prefix same');
    Check((Diff[1].Kind = dkRemoved) and (Diff[1].Text = 'OldMiddle'), 'ChangedMiddle: middle removed');
    Check((Diff[2].Kind = dkAdded) and (Diff[2].Text = 'NewMiddle'), 'ChangedMiddle: middle added');
    Check((Diff[3].Kind = dkSame) and (Diff[3].Text = 'Suffix'), 'ChangedMiddle: suffix same');
  end;
end;

procedure TestCrlfVsLf(const Check: TCheckProc);
var
  Diff: TArray<TDiffLine>;
  I: Integer;
  HasChanges: Boolean;
begin
  Diff := DiffLines('Alpha'#13#10'Beta'#13#10'Gamma'#13#10, 'Alpha'#10'Beta'#10'Gamma'#10);
  Check(Length(Diff) = 3, 'CrlfVsLf: length is 3');
  HasChanges := False;
  for I := 0 to High(Diff) do
    if Diff[I].Kind <> dkSame then
      HasChanges := True;
  Check(not HasChanges, 'CrlfVsLf: same content has no changes');
end;

procedure TestPureInsertionAtEnd(const Check: TCheckProc);
var
  Diff: TArray<TDiffLine>;
begin
  Diff := DiffLines('First'#10'Second', 'First'#10'Second'#10'Third');
  Check(Length(Diff) = 3, 'PureInsertion: length is 3');
  if Length(Diff) = 3 then
  begin
    Check((Diff[0].Kind = dkSame) and (Diff[0].Text = 'First'), 'PureInsertion: line 0 same');
    Check((Diff[1].Kind = dkSame) and (Diff[1].Text = 'Second'), 'PureInsertion: line 1 same');
    Check((Diff[2].Kind = dkAdded) and (Diff[2].Text = 'Third'), 'PureInsertion: line 2 added');
  end;
end;

procedure TestCollapseContext(const Check: TCheckProc);
var
  Before, After: string;
  Diff, Collapsed: TArray<TDiffLine>;
  I: Integer;
begin
  Before := '';
  After := '';
  for I := 0 to 19 do
  begin
    if I > 0 then
    begin
      Before := Before + #10;
      After := After + #10;
    end;
    Before := Before + Format('Row%d', [I]);
    if I = 10 then
      After := After + 'Row10Modified'
    else
      After := After + Format('Row%d', [I]);
  end;

  Diff := DiffLines(Before, After);
  Check(Length(Diff) = 21, 'CollapseContext: uncollapsed diff length is 21');

  Collapsed := CollapseContext(Diff, 3);
  Check(Length(Collapsed) = 10, 'CollapseContext: collapsed length is 10');
  if Length(Collapsed) = 10 then
  begin
    Check((Collapsed[0].Kind = dkSame) and (Collapsed[0].Text = #$2026), 'CollapseContext: leading ellipsis');
    Check((Collapsed[1].Kind = dkSame) and (Collapsed[1].Text = 'Row7'), 'CollapseContext: context Row7');
    Check((Collapsed[2].Kind = dkSame) and (Collapsed[2].Text = 'Row8'), 'CollapseContext: context Row8');
    Check((Collapsed[3].Kind = dkSame) and (Collapsed[3].Text = 'Row9'), 'CollapseContext: context Row9');
    Check((Collapsed[4].Kind = dkRemoved) and (Collapsed[4].Text = 'Row10'), 'CollapseContext: Row10 removed');
    Check((Collapsed[5].Kind = dkAdded) and (Collapsed[5].Text = 'Row10Modified'), 'CollapseContext: Row10Modified added');
    Check((Collapsed[6].Kind = dkSame) and (Collapsed[6].Text = 'Row11'), 'CollapseContext: context Row11');
    Check((Collapsed[7].Kind = dkSame) and (Collapsed[7].Text = 'Row12'), 'CollapseContext: context Row12');
    Check((Collapsed[8].Kind = dkSame) and (Collapsed[8].Text = 'Row13'), 'CollapseContext: context Row13');
    Check((Collapsed[9].Kind = dkSame) and (Collapsed[9].Text = #$2026), 'CollapseContext: trailing ellipsis');
  end;

  Diff := DiffLines(Before, Before);
  Collapsed := CollapseContext(Diff, 3);
  Check(Length(Collapsed) <= 6, 'CollapseContext: unchanged collapses to at most 6 lines');
end;

procedure TestLargeInputFallback(const Check: TCheckProc);
var
  Before, After: string;
  Diff: TArray<TDiffLine>;
  I, RemovedCount, AddedCount: Integer;
  Stopwatch: TStopwatch;
  FoundChange: Boolean;
begin
  Before := '';
  After := '';
  for I := 0 to 2999 do
  begin
    if I > 0 then
    begin
      Before := Before + #10;
      After := After + #10;
    end;
    Before := Before + Format('LargeLine%d', [I]);
    if I = 1500 then
      After := After + 'LargeLine1500Modified'
    else
      After := After + Format('LargeLine%d', [I]);
  end;

  Stopwatch := TStopwatch.StartNew;
  Diff := DiffLines(Before, After);
  Stopwatch.Stop;

  Check(Stopwatch.ElapsedMilliseconds < 1000, 'LargeInput: returns quickly (< 1000ms)');
  Check(Length(Diff) = 3001, 'LargeInput: total lines is 3001');

  RemovedCount := 0;
  AddedCount := 0;
  FoundChange := False;
  for I := 0 to High(Diff) do
  begin
    if Diff[I].Kind = dkRemoved then
    begin
      Inc(RemovedCount);
      Check(Diff[I].Text = 'LargeLine1500', 'LargeInput: removed line content');
      if I = 1500 then
        FoundChange := True;
    end
    else if Diff[I].Kind = dkAdded then
    begin
      Inc(AddedCount);
      Check(Diff[I].Text = 'LargeLine1500Modified', 'LargeInput: added line content');
    end;
  end;

  Check(RemovedCount = 1, 'LargeInput: exactly 1 removed');
  Check(AddedCount = 1, 'LargeInput: exactly 1 added');
  Check(FoundChange, 'LargeInput: changed hunk is located correctly in middle');
end;

procedure RunLineDiffTests(const Check: TCheckProc);
begin
  TestIdentical(Check);
  TestChangedMiddle(Check);
  TestCrlfVsLf(Check);
  TestPureInsertionAtEnd(Check);
  TestCollapseContext(Check);
  TestLargeInputFallback(Check);
end;

end.
