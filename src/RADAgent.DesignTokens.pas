unit RADAgent.DesignTokens;

{ YAML front matter parser and design token extraction.
  Parses front matter between the first two '---' markers. Pure RTL. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TFrontMatter = TDictionary<string, string>; { dotted key path -> scalar text, unquoted }

{ Front matter of a DESIGN.md text; an empty dictionary when there is none. Keys keep their case:
  'spacing.sm', 'typography.body.fontSize', 'radstudio.style'. Caller frees. }
function ReadFrontMatter(const Text: string): TFrontMatter;

{ '8px', '8', '0.5rem' / '0.5em' (x16), '10pt' (x96/72). False when not a dimension. }
function DimensionPx(const Value: string; out Px: Double): Boolean;

{ '#RGB', '#RRGGBB', '#RRGGBBAA' -> $RRGGBB (alpha dropped). False otherwise. }
function ColorRgb(const Value: string; out Rgb: Cardinal): Boolean;

{ All values under Prefix ('spacing', 'rounded', ...) that parse as dimensions / colors. }
function Dimensions(Map: TFrontMatter; const Prefix: string): TArray<Double>;
function FontSizes(Map: TFrontMatter): TArray<Double>; { typography.*.fontSize }
function FontFamilies(Map: TFrontMatter): TArray<string>; { typography.*.fontFamily }
function Colors(Map: TFrontMatter): TArray<Cardinal>; { colors.* }

implementation

type
  TStackEntry = record
    Indent: Integer;
    Key: string;
  end;

function FindUnquotedChar(const S: string; StopChar: Char): Integer;
var
  I: Integer;
  InSingle, InDouble, Escaped: Boolean;
begin
  InSingle := False; InDouble := False; Escaped := False;
  for I := 1 to Length(S) do
  begin
    if Escaped then Escaped := False
    else if InDouble and (S[I] = '\') then Escaped := True
    else if (S[I] = '''') and not InDouble then InSingle := not InSingle
    else if (S[I] = '"') and not InSingle then InDouble := not InDouble
    else if (S[I] = StopChar) and not InSingle and not InDouble then Exit(I);
  end;
  Result := 0;
end;

function StripComment(const S: string): string;
var
  P: Integer;
begin
  P := FindUnquotedChar(S, '#');
  if P > 0 then Result := Copy(S, 1, P - 1) else Result := S;
end;

function Unquote(const S: string): string;
var
  T: string;
  L: Integer;
begin
  T := Trim(S);
  L := Length(T);
  if (L >= 2) and (T[1] = '"') and (T[L] = '"') then
    Result := T.Substring(1, L - 2).Replace('\"', '"').Replace('\n', #10).Replace('\r', #13).Replace('\t', #9).Replace('\\', '\')
  else if (L >= 2) and (T[1] = '''') and (T[L] = '''') then
    Result := T.Substring(1, L - 2).Replace('''''', '''')
  else
    Result := T;
end;

procedure ParseFlowMap(const Prefix, Key, FlowText: string; Map: TFrontMatter);
var
  Inner, Chunk, SubKey, SubVal, FullKey: string;
  I, StartIdx, Len, ColonPos: Integer;
  InSingle, InDouble, Escaped: Boolean;
begin
  Inner := Trim(FlowText);
  if (Length(Inner) >= 2) and (Inner[1] = '{') and (Inner[Length(Inner)] = '}') then
    Inner := Trim(Copy(Inner, 2, Length(Inner) - 2));
  if Inner = '' then Exit;
  InSingle := False; InDouble := False; Escaped := False;
  StartIdx := 1; Len := Length(Inner);
  for I := 1 to Len + 1 do
  begin
    if I <= Len then
    begin
      if Escaped then Escaped := False
      else if InDouble and (Inner[I] = '\') then Escaped := True
      else if (Inner[I] = '''') and not InDouble then InSingle := not InSingle
      else if (Inner[I] = '"') and not InSingle then InDouble := not InDouble;
    end;
    if (I > Len) or ((Inner[I] = ',') and not InSingle and not InDouble) then
    begin
      Chunk := Trim(Copy(Inner, StartIdx, I - StartIdx));
      StartIdx := I + 1;
      ColonPos := FindUnquotedChar(Chunk, ':');
      if ColonPos > 0 then
      begin
        SubKey := Trim(Copy(Chunk, 1, ColonPos - 1));
        SubVal := Unquote(Trim(Copy(Chunk, ColonPos + 1, MaxInt)));
        if Prefix <> '' then FullKey := Prefix + '.' + Key + '.' + SubKey
        else FullKey := Key + '.' + SubKey;
        Map.AddOrSetValue(FullKey, SubVal);
      end;
    end;
  end;
end;

function BuildPrefix(const Stack: array of TStackEntry; Count: Integer): string;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to Count - 1 do
  begin
    if K > 0 then Result := Result + '.' + Stack[K].Key
    else Result := Stack[K].Key;
  end;
end;

function ReadFrontMatter(const Text: string): TFrontMatter;
var
  Lines: TArray<string>;
  LineIdx, FirstDashIdx, SecondDashIdx, Indent, ColonPos, StackCount: Integer;
  Line, StrippedLine, Key, Rest, Prefix, FullKey, ScalarVal: string;
  Stack: array of TStackEntry;
begin
  Result := TFrontMatter.Create;
  if Text = '' then Exit;
  Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  FirstDashIdx := -1; SecondDashIdx := -1;
  for LineIdx := 0 to High(Lines) do
    if Trim(Lines[LineIdx]) = '---' then
    begin
      if FirstDashIdx < 0 then FirstDashIdx := LineIdx
      else begin SecondDashIdx := LineIdx; Break; end;
    end;
  if (FirstDashIdx < 0) or (SecondDashIdx <= FirstDashIdx) then Exit;

  SetLength(Stack, 16); StackCount := 0;
  for LineIdx := FirstDashIdx + 1 to SecondDashIdx - 1 do
  begin
    Line := Lines[LineIdx];
    StrippedLine := StripComment(Line);
    if Trim(StrippedLine) = '' then Continue;

    Indent := 0;
    while (Indent < Length(StrippedLine)) and (StrippedLine[Indent + 1] = ' ') do
      Inc(Indent);

    StrippedLine := Trim(StrippedLine);
    if (StrippedLine = '-') or StrippedLine.StartsWith('- ') then Continue;

    ColonPos := FindUnquotedChar(StrippedLine, ':');
    if ColonPos <= 0 then Continue;

    Key := Trim(Copy(StrippedLine, 1, ColonPos - 1));
    Rest := Trim(Copy(StrippedLine, ColonPos + 1, MaxInt));
    if Key = '' then Continue;

    while (StackCount > 0) and (Stack[StackCount - 1].Indent >= Indent) do
      Dec(StackCount);
    Prefix := BuildPrefix(Stack, StackCount);

    if (Length(Rest) >= 2) and (Rest[1] = '{') and (Rest[Length(Rest)] = '}') then
      ParseFlowMap(Prefix, Key, Rest, Result)
    else if Rest = '' then
    begin
      if StackCount >= Length(Stack) then SetLength(Stack, Length(Stack) * 2);
      Stack[StackCount].Indent := Indent;
      Stack[StackCount].Key := Key;
      Inc(StackCount);
    end
    else
    begin
      ScalarVal := Unquote(Rest);
      if Prefix <> '' then FullKey := Prefix + '.' + Key else FullKey := Key;
      Result.AddOrSetValue(FullKey, ScalarVal);
    end;
  end;
end;

function DimensionPx(const Value: string; out Px: Double): Boolean;
var
  S, NumStr, Low: string;
  Mul, Val: Double;
begin
  Px := 0;
  S := Trim(Value);
  if S = '' then Exit(False);
  Low := S.ToLower;
  if Low.EndsWith('px') then begin NumStr := Trim(Copy(S, 1, Length(S) - 2)); Mul := 1.0; end
  else if Low.EndsWith('rem') then begin NumStr := Trim(Copy(S, 1, Length(S) - 3)); Mul := 16.0; end
  else if Low.EndsWith('em') then begin NumStr := Trim(Copy(S, 1, Length(S) - 2)); Mul := 16.0; end
  else if Low.EndsWith('pt') then begin NumStr := Trim(Copy(S, 1, Length(S) - 2)); Mul := 96.0 / 72.0; end
  else begin NumStr := S; Mul := 1.0; end;
  Result := TryStrToFloat(NumStr, Val, TFormatSettings.Invariant);
  if Result then Px := Val * Mul;
end;

function HexDigit(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function ColorRgb(const Value: string; out Rgb: Cardinal): Boolean;
var
  S, Hex: string;
  I, R, G, B: Integer;
begin
  Rgb := 0;
  S := Trim(Value);
  if (Length(S) < 2) or (S[1] <> '#') then Exit(False);
  Hex := Copy(S, 2, MaxInt);
  for I := 1 to Length(Hex) do
    if HexDigit(Hex[I]) < 0 then Exit(False);

  if Length(Hex) = 3 then
  begin
    R := (HexDigit(Hex[1]) shl 4) or HexDigit(Hex[1]);
    G := (HexDigit(Hex[2]) shl 4) or HexDigit(Hex[2]);
    B := (HexDigit(Hex[3]) shl 4) or HexDigit(Hex[3]);
    Rgb := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
    Result := True;
  end
  else if (Length(Hex) = 6) or (Length(Hex) = 8) then
  begin
    R := (HexDigit(Hex[1]) shl 4) or HexDigit(Hex[2]);
    G := (HexDigit(Hex[3]) shl 4) or HexDigit(Hex[4]);
    B := (HexDigit(Hex[5]) shl 4) or HexDigit(Hex[6]);
    Rgb := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
    Result := True;
  end
  else
    Result := False;
end;

function Dimensions(Map: TFrontMatter; const Prefix: string): TArray<Double>;
var
  Pair: TPair<string, string>;
  Key: string;
  Val: Double;
  List: TList<Double>;
  Match: Boolean;
begin
  if Map = nil then Exit(nil);
  List := TList<Double>.Create;
  try
    for Pair in Map do
    begin
      Key := Pair.Key;
      Match := (Prefix = '') or SameText(Key, Prefix) or Key.ToLower.StartsWith(Prefix.ToLower + '.');
      if Match and DimensionPx(Pair.Value, Val) then List.Add(Val);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FontSizes(Map: TFrontMatter): TArray<Double>;
var
  Pair: TPair<string, string>;
  Key: string;
  Val: Double;
  List: TList<Double>;
begin
  if Map = nil then Exit(nil);
  List := TList<Double>.Create;
  try
    for Pair in Map do
    begin
      Key := Pair.Key.ToLower;
      if (Key = 'typography.fontsize') or (Key.StartsWith('typography.') and Key.EndsWith('.fontsize')) then
        if DimensionPx(Pair.Value, Val) then List.Add(Val);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FontFamilies(Map: TFrontMatter): TArray<string>;
var
  Pair: TPair<string, string>;
  Key, Val: string;
  List: TList<string>;
begin
  if Map = nil then Exit(nil);
  List := TList<string>.Create;
  try
    for Pair in Map do
    begin
      Key := Pair.Key.ToLower;
      if (Key = 'typography.fontfamily') or (Key.StartsWith('typography.') and Key.EndsWith('.fontfamily')) then
      begin
        Val := Trim(Pair.Value);
        if (Val <> '') and not List.Contains(Val) then List.Add(Val);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function Colors(Map: TFrontMatter): TArray<Cardinal>;
var
  Pair: TPair<string, string>;
  Key: string;
  C: Cardinal;
  List: TList<Cardinal>;
begin
  if Map = nil then Exit(nil);
  List := TList<Cardinal>.Create;
  try
    for Pair in Map do
    begin
      Key := Pair.Key.ToLower;
      if (Key = 'colors') or Key.StartsWith('colors.') then
        if ColorRgb(Pair.Value, C) and not List.Contains(C) then List.Add(C);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
