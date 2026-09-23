unit DelphiAgent.LineDiff;

{ LCS-based line diffing and context collapsing for approval dialogs. }

interface

uses
  System.SysUtils, System.Math, System.Generics.Collections;

type
  TDiffKind = (dkSame, dkRemoved, dkAdded);

  TDiffLine = record
    Kind: TDiffKind;
    Text: string;
  end;

{ Splits text on CRLF, LF, or CR. Trailing line break does not produce an extra empty line. }
function SplitLines(const S: string): TArray<string>;

{ Computes a line-by-line diff. Changed hunks produce removed-before-added order. }
function DiffLines(const Before, After: string): TArray<TDiffLine>;

{ Keeps up to Context unchanged lines around changes and collapses long runs into a single '…'.
  If there are no changes, returns at most Context * 2 lines. }
function CollapseContext(const Lines: TArray<TDiffLine>; Context: Integer): TArray<TDiffLine>;

implementation

const
  MaxQuadraticProduct = 4000000;
  EllipsisChar = #$2026; { '…' }

function SplitLines(const S: string): TArray<string>;
var
  Len, I, Start: Integer;
  List: TList<string>;
  Ch: Char;
begin
  if S = '' then
    Exit(nil);
  Len := Length(S);
  List := TList<string>.Create;
  try
    Start := 1;
    I := 1;
    while I <= Len do
    begin
      Ch := S[I];
      if (Ch = #13) or (Ch = #10) then
      begin
        List.Add(Copy(S, Start, I - Start));
        if (Ch = #13) and (I < Len) and (S[I + 1] = #10) then
          Inc(I, 2)
        else
          Inc(I);
        Start := I;
      end
      else
        Inc(I);
    end;
    if Start <= Len then
      List.Add(Copy(S, Start, Len - Start + 1));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function DiffLines(const Before, After: string): TArray<TDiffLine>;
var
  BeforeLines, AfterLines: TArray<string>;
  N, M, Pref, MaxSuff, Suff: Integer;
  MidN, MidM, W, H, Row, PrevRow, LeftVal, UpVal, I, J, K: Integer;
  OutList, BackList: TList<TDiffLine>;
  DP: TArray<Integer>;
  Line: TDiffLine;
begin
  BeforeLines := SplitLines(Before);
  AfterLines := SplitLines(After);
  N := Length(BeforeLines);
  M := Length(AfterLines);

  Pref := 0;
  while (Pref < N) and (Pref < M) and (BeforeLines[Pref] = AfterLines[Pref]) do
    Inc(Pref);

  MaxSuff := Min(N - Pref, M - Pref);
  Suff := 0;
  while (Suff < MaxSuff) and (BeforeLines[N - 1 - Suff] = AfterLines[M - 1 - Suff]) do
    Inc(Suff);

  OutList := TList<TDiffLine>.Create;
  try
    { Common prefix }
    for I := 0 to Pref - 1 do
    begin
      Line.Kind := dkSame;
      Line.Text := BeforeLines[I];
      OutList.Add(Line);
    end;

    MidN := N - Pref - Suff;
    MidM := M - Pref - Suff;

    if (MidN > 0) or (MidM > 0) then
    begin
      if Int64(N) * M > MaxQuadraticProduct then
      begin
        { Large input fallback: prefix/suffix trimmed, middle as removed then added }
        for I := 0 to MidN - 1 do
        begin
          Line.Kind := dkRemoved;
          Line.Text := BeforeLines[Pref + I];
          OutList.Add(Line);
        end;
        for J := 0 to MidM - 1 do
        begin
          Line.Kind := dkAdded;
          Line.Text := AfterLines[Pref + J];
          OutList.Add(Line);
        end;
      end
      else
      begin
        W := MidM + 1;
        H := MidN + 1;
        SetLength(DP, W * H);

        for I := 1 to MidN do
        begin
          Row := I * W;
          PrevRow := (I - 1) * W;
          for J := 1 to MidM do
          begin
            if BeforeLines[Pref + I - 1] = AfterLines[Pref + J - 1] then
              DP[Row + J] := DP[PrevRow + J - 1] + 1
            else
            begin
              LeftVal := DP[Row + J - 1];
              UpVal := DP[PrevRow + J];
              if LeftVal > UpVal then
                DP[Row + J] := LeftVal
              else
                DP[Row + J] := UpVal;
            end;
          end;
        end;

        I := MidN;
        J := MidM;
        BackList := TList<TDiffLine>.Create;
        try
          while (I > 0) or (J > 0) do
          begin
            if (I > 0) and (J > 0) and (BeforeLines[Pref + I - 1] = AfterLines[Pref + J - 1]) then
            begin
              Line.Kind := dkSame;
              Line.Text := BeforeLines[Pref + I - 1];
              BackList.Add(Line);
              Dec(I);
              Dec(J);
            end
            else if (J > 0) and ((I = 0) or (DP[I * W + (J - 1)] >= DP[(I - 1) * W + J])) then
            begin
              Line.Kind := dkAdded;
              Line.Text := AfterLines[Pref + J - 1];
              BackList.Add(Line);
              Dec(J);
            end
            else
            begin
              Line.Kind := dkRemoved;
              Line.Text := BeforeLines[Pref + I - 1];
              BackList.Add(Line);
              Dec(I);
            end;
          end;

          for K := BackList.Count - 1 downto 0 do
            OutList.Add(BackList[K]);
        finally
          BackList.Free;
        end;
      end;
    end;

    { Common suffix }
    for I := 0 to Suff - 1 do
    begin
      Line.Kind := dkSame;
      Line.Text := BeforeLines[N - Suff + I];
      OutList.Add(Line);
    end;

    Result := OutList.ToArray;
  finally
    OutList.Free;
  end;
end;

function CollapseContext(const Lines: TArray<TDiffLine>; Context: Integer): TArray<TDiffLine>;
var
  Len, I, K, FromIdx, ToIdx, MaxKeep: Integer;
  HasChanges, InEllipsis: Boolean;
  Keep: TArray<Boolean>;
  OutList: TList<TDiffLine>;
  EllipsisLine: TDiffLine;
begin
  Len := Length(Lines);
  if Len = 0 then
    Exit(nil);
  if Context < 0 then
    Context := 0;

  HasChanges := False;
  for I := 0 to Len - 1 do
    if Lines[I].Kind <> dkSame then
    begin
      HasChanges := True;
      Break;
    end;

  if not HasChanges then
  begin
    MaxKeep := Context * 2;
    if Len > MaxKeep then
      Len := MaxKeep;
    SetLength(Result, Len);
    for I := 0 to Len - 1 do
      Result[I] := Lines[I];
    Exit;
  end;

  SetLength(Keep, Len);
  for I := 0 to Len - 1 do
    if Lines[I].Kind <> dkSame then
    begin
      FromIdx := Max(0, I - Context);
      ToIdx := Min(Len - 1, I + Context);
      for K := FromIdx to ToIdx do
        Keep[K] := True;
    end;

  EllipsisLine.Kind := dkSame;
  EllipsisLine.Text := EllipsisChar;

  OutList := TList<TDiffLine>.Create;
  try
    InEllipsis := False;
    for I := 0 to Len - 1 do
    begin
      if Keep[I] then
      begin
        InEllipsis := False;
        OutList.Add(Lines[I]);
      end
      else if not InEllipsis then
      begin
        OutList.Add(EllipsisLine);
        InEllipsis := True;
      end;
    end;
    Result := OutList.ToArray;
  finally
    OutList.Free;
  end;
end;

end.
