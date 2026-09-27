unit RADAgent.PropValues;

{ Property text the form tools accept beyond what SetPropValue converts: identifiers the
  streaming system knows for integer types (clBtnFace, mrOk, crHandPoint, claWhite) and DESIGN.md
  hex colors (#RRGGBB) for TColor (VCL, stored as $00BBGGRR) and TAlphaColor (FMX, $FFRRGGBB).
  No ToolsAPI. }

interface

uses
  System.TypInfo;

{ Sets Prop of Target from an identifier the streaming system knows for its type or, for a color
  type, from #RRGGBB. False (nothing set) for other text: the caller converts it as usual. }
function SetOrdinalText(Target: TObject; Prop: PPropInfo; const Value: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes;

function HexRgb(const Value: string; out Rgb: Cardinal): Boolean;
var
  Parsed: Integer;
begin
  Result := (Length(Value) = 7) and (Value[1] = '#') and TryStrToInt('$' + Copy(Value, 2, 6), Parsed);
  if Result then
    Rgb := Cardinal(Parsed);
end;

function TryOrdinalText(Prop: PPropInfo; const Value: string; out Ordinal: Int64): Boolean;
var
  TypeName, Text: string;
  Ident: TIdentToInt;
  Int: Integer;
  Rgb: Cardinal;
begin
  Result := False;
  Ordinal := 0;
  Text := Trim(Value);
  if (Prop = nil) or not (Prop.PropType^.Kind in [tkInteger, tkInt64]) or (Text = '') then
    Exit;
  TypeName := string(Prop.PropType^.Name);
  if HexRgb(Text, Rgb) then
  begin
    if SameText(TypeName, 'TColor') then
    begin
      Ordinal := ((Rgb and $FF) shl 16) or (Rgb and $FF00) or ((Rgb shr 16) and $FF);
      Exit(True);
    end;
    if SameText(TypeName, 'TAlphaColor') then
    begin
      Ordinal := Int64($FF000000 or Rgb);
      Exit(True);
    end;
    Exit;
  end;
  if Text.StartsWith('#') and (SameText(TypeName, 'TColor') or SameText(TypeName, 'TAlphaColor')) then
    raise EConvertError.CreateFmt('%s: colors are #RRGGBB (DESIGN.md hex, no alpha), a color name ' +
      '(clBtnFace, claWhite) or a number.', [Text]);
  Ident := FindIdentToInt(Prop.PropType^);
  if Assigned(Ident) and Ident(Text, Int) then
  begin
    if SameText(TypeName, 'TAlphaColor') then
      Ordinal := Cardinal(Int)
    else
      Ordinal := Int;
    Result := True;
  end;
end;

function SetOrdinalText(Target: TObject; Prop: PPropInfo; const Value: string): Boolean;
var
  Ordinal: Int64;
begin
  Result := TryOrdinalText(Prop, Value, Ordinal);
  if not Result then
    Exit;
  if Prop.PropType^.Kind = tkInt64 then
    SetInt64Prop(Target, Prop, Ordinal)
  else
    { TAlphaColor is unsigned: the same 32 bits as an Integer. }
    SetOrdProp(Target, Prop, Integer(Cardinal(Ordinal and $FFFFFFFF)));
end;

end.
