unit RADAgent.DesignProgram;

{ Text edits that give a VCL program its default style, as the IDE's Project Options > Appearance
  page does: the Custom_Styles project option lists the styles linked into the executable, and the
  program source calls TStyleManager.TrySetStyle before the forms are created. Pure text; the
  ToolsAPI side is RADAgent.DesignApply. }

interface

type
  TLinkedStyle = record
    { The style's name (TStyleManager) and its file with a $(BDSCOMMONDIR) or $(BDS) macro. }
    Name, Path: string;
  end;

{ Source of a Delphi .dpr (Cpp False) or a C++Builder project .cpp (Cpp True) whose startup sets
  StyleName: the style units are used or included, and an existing TrySetStyle call is changed
  or a new one follows Application.MainFormOnTaskbar (else Application.Initialize). False with
  Problem when the source has no such startup code. }
function SetProgramStyle(const Source, StyleName: string; Cpp: Boolean; out NewSource,
  Problem: string): Boolean;
{ The Custom_Styles option value with Styles added (a style already listed by name stays as is). }
function MergeCustomStyles(const Current: string; const Styles: array of TLinkedStyle): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.RegularExpressions;

{ Index (1-based) just past the comment or string starting at I, or I when there is none. }
function SkipDelphiNoise(const S: string; I: Integer): Integer;
var
  Len: Integer;
begin
  Result := I;
  Len := Length(S);
  if S[I] = '{' then
  begin
    while (Result <= Len) and (S[Result] <> '}') do
      Inc(Result);
    Inc(Result);
  end
  else if (S[I] = '(') and (I < Len) and (S[I + 1] = '*') then
  begin
    Result := PosEx('*)', S, I + 2);
    if Result = 0 then
      Result := Len + 1
    else
      Inc(Result, 2);
  end
  else if (S[I] = '/') and (I < Len) and (S[I + 1] = '/') then
  begin
    while (Result <= Len) and not CharInSet(S[Result], [#10, #13]) do
      Inc(Result);
  end
  else if S[I] = '''' then
  begin
    Inc(Result);
    while (Result <= Len) and (S[Result] <> '''') do
      Inc(Result);
    Inc(Result);
  end;
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']);
end;

{ Start and end (index of its ';') of the program's uses clause, outside comments and strings. }
function FindUsesClause(const S: string; out First, Semicolon: Integer): Boolean;
var
  I, Next, Len: Integer;
begin
  Result := False;
  First := 0;
  Semicolon := 0;
  Len := Length(S);
  I := 1;
  while I <= Len do
  begin
    Next := SkipDelphiNoise(S, I);
    if Next <> I then
    begin
      I := Next;
      Continue;
    end;
    if First = 0 then
    begin
      if SameText(Copy(S, I, 4), 'uses') and ((I = 1) or not IsIdentChar(S[I - 1])) and
        ((I + 4 > Len) or not IsIdentChar(S[I + 4])) then
      begin
        First := I + 4;
        I := First;
        Continue;
      end;
      if IsIdentChar(S[I]) then
      begin
        { Skip the rest of a word so "reuses" or "MyUses" do not match. }
        while (I <= Len) and IsIdentChar(S[I]) do
          Inc(I);
        Continue;
      end;
    end
    else if S[I] = ';' then
    begin
      Semicolon := I;
      Exit(True);
    end;
    Inc(I);
  end;
end;

function UsesUnit(const Clause, UnitName: string): Boolean;
begin
  Result := TRegEx.IsMatch(Clause, '(^|[\s,])' + TRegEx.Escape(UnitName) + '(\s|,|;|$|\s+in\s)',
    [roIgnoreCase]);
end;

function AddDelphiUses(const S: string; out NewSource: string): Boolean;
var
  First, Semicolon: Integer;
  Clause, Added: string;
begin
  Result := FindUsesClause(S, First, Semicolon);
  if not Result then
    Exit;
  Clause := Copy(S, First, Semicolon - First + 1);
  Added := '';
  if not UsesUnit(Clause, 'Vcl.Themes') and not UsesUnit(Clause, 'Themes') then
    Added := Added + ',' + sLineBreak + '  Vcl.Themes';
  if not UsesUnit(Clause, 'Vcl.Styles') and not UsesUnit(Clause, 'Styles') then
    Added := Added + ',' + sLineBreak + '  Vcl.Styles';
  // Custom_Styles are compiled into <project>.res; a program without {$R *.res} would not get them.
  if TRegEx.IsMatch(S, '\{\$R\s+\*\.res\}', [roIgnoreCase]) then
    NewSource := Copy(S, 1, Semicolon - 1) + Added + Copy(S, Semicolon, MaxInt)
  else
    NewSource := Copy(S, 1, Semicolon - 1) + Added + ';' + sLineBreak + sLineBreak + '{$R *.res}' +
      Copy(S, Semicolon + 1, MaxInt);
end;

function AddCppIncludes(const S: string; out NewSource: string): Boolean;
var
  Match: TMatch;
  Added: string;
begin
  Match := TRegEx.Match(S, '^[ \t]*#include\s*<vcl\.h>[^\r\n]*(\r?\n)', [roIgnoreCase, roMultiLine]);
  Result := Match.Success;
  if not Result then
    Exit;
  Added := '';
  if not TRegEx.IsMatch(S, '#include\s*<Vcl\.Themes\.hpp>', [roIgnoreCase]) then
    Added := Added + '#include <Vcl.Themes.hpp>' + sLineBreak;
  if not TRegEx.IsMatch(S, '#include\s*<Vcl\.Styles\.hpp>', [roIgnoreCase]) then
    Added := Added + '#include <Vcl.Styles.hpp>' + sLineBreak;
  NewSource := Copy(S, 1, Match.Index + Match.Length - 1) + Added +
    Copy(S, Match.Index + Match.Length, MaxInt);
end;

function Literal(const Value: string; Cpp: Boolean): string;
begin
  if Cpp then
    Result := '"' + StringReplace(StringReplace(Value, '\', '\\', [rfReplaceAll]), '"', '\"',
      [rfReplaceAll]) + '"'
  else
    Result := QuotedStr(Value);
end;

{ The existing TrySetStyle call gets StyleName, or a new line follows the anchor. }
function SetStyleCall(const S, StyleName: string; Cpp: Boolean; out NewSource: string): Boolean;
const
  DelphiCall = 'TStyleManager\.TrySetStyle\(\s*''(?:[^'']|'''')*''';
  CppCall = 'TStyleManager::TrySetStyle\(\s*L?"(?:[^"\\]|\\.)*"';
  DelphiAnchors: array[0..1] of string = ('^[ \t]*Application\.MainFormOnTaskbar\s*:=[^\r\n]*\r?\n',
    '^[ \t]*Application\.Initialize\s*;[^\r\n]*\r?\n');
  CppAnchors: array[0..1] of string = ('^[ \t]*Application->MainFormOnTaskbar\s*=[^\r\n]*\r?\n',
    '^[ \t]*Application->Initialize\s*\(\s*\)\s*;[^\r\n]*\r?\n');
var
  Match: TMatch;
  Call, Indent, Anchor: string;
  Anchors: array[0..1] of string;
  Index: Integer;
begin
  Result := False;
  if Cpp then
  begin
    Call := 'TStyleManager::TrySetStyle(' + Literal(StyleName, True);
    Match := TRegEx.Match(S, CppCall);
  end
  else
  begin
    Call := 'TStyleManager.TrySetStyle(' + Literal(StyleName, False);
    Match := TRegEx.Match(S, DelphiCall);
  end;
  if Match.Success then
  begin
    NewSource := Copy(S, 1, Match.Index - 1) + Call + Copy(S, Match.Index + Match.Length, MaxInt);
    Exit(True);
  end;
  for Index := 0 to 1 do
    if Cpp then
      Anchors[Index] := CppAnchors[Index]
    else
      Anchors[Index] := DelphiAnchors[Index];
  for Anchor in Anchors do
  begin
    Match := TRegEx.Match(S, Anchor, [roMultiLine]);
    if not Match.Success then
      Continue;
    Indent := TRegEx.Match(Match.Value, '^[ \t]*').Value;
    NewSource := Copy(S, 1, Match.Index + Match.Length - 1) + Indent + Call + ');' + sLineBreak +
      Copy(S, Match.Index + Match.Length, MaxInt);
    Exit(True);
  end;
end;

function SetProgramStyle(const Source, StyleName: string; Cpp: Boolean; out NewSource,
  Problem: string): Boolean;
var
  WithUnits: string;
begin
  NewSource := Source;
  Problem := '';
  if Cpp then
    Result := AddCppIncludes(Source, WithUnits)
  else
    Result := AddDelphiUses(Source, WithUnits);
  if not Result then
  begin
    if Cpp then
      Problem := 'The project source has no #include <vcl.h>.'
    else
      Problem := 'The program source has no uses clause.';
    Exit;
  end;
  Result := SetStyleCall(WithUnits, StyleName, Cpp, NewSource);
  if not Result then
  begin
    NewSource := Source;
    Problem := 'The project source has no Application.Initialize line to put the style after.';
  end;
end;

{ Custom_Styles entries: Name|VCLSTYLE|Path, separated by ';', in double quotes when they hold
  spaces or ';'. }
function SplitEntries(const Value: string): TArray<string>;
var
  I, Start: Integer;
  Quoted: Boolean;
begin
  Result := nil;
  Quoted := False;
  Start := 1;
  for I := 1 to Length(Value) + 1 do
    if (I > Length(Value)) or ((Value[I] = ';') and not Quoted) then
    begin
      if Trim(Copy(Value, Start, I - Start)) <> '' then
        Result := Result + [Trim(Copy(Value, Start, I - Start))];
      Start := I + 1;
    end
    else if Value[I] = '"' then
      Quoted := not Quoted;
end;

function EntryName(const Entry: string): string;
begin
  Result := Entry.DeQuotedString('"');
  if Pos('|', Result) > 0 then
    Result := Copy(Result, 1, Pos('|', Result) - 1);
end;

function MergeCustomStyles(const Current: string; const Styles: array of TLinkedStyle): string;
var
  Entries: TArray<string>;
  Style: TLinkedStyle;
  Entry, Item: string;
  Known: Boolean;
begin
  Entries := SplitEntries(Current);
  for Style in Styles do
  begin
    Known := False;
    for Entry in Entries do
      if SameText(EntryName(Entry), Style.Name) then
        Known := True;
    if Known then
      Continue;
    Item := Style.Name + '|VCLSTYLE|' + Style.Path;
    if (Pos(' ', Item) > 0) or (Pos(';', Item) > 0) then
      Item := '"' + Item + '"';
    Entries := Entries + [Item];
  end;
  Result := string.Join(';', Entries);
end;

end.
