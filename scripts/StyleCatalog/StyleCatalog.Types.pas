unit StyleCatalog.Types;

interface

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Math,
  System.Generics.Collections;

type
  TStyleColors = record
    Background: string;
    Surface: string;
    Text: string;
    TextDisabled: string;
    Accent: string;
    AccentText: string;
    Border: string;
    function HasAny: Boolean;
    function ToJSON(const Indent: string): string;
  end;

  TProvenance = record
    System: string;
    Basis: string;
    Evidence: string;
  end;

  TStyleEntry = record
    FileName: string;
    Folder: string;
    SubFolder: string;
    Framework: string;
    FormatName: string;
    StyleName: string;
    Platforms: TArray<string>;
    Theme: string;
    Loadable: Boolean;
    Colors: TStyleColors;
    Pair: string;
    Provenance: TProvenance;
    Preset: string;
    PresetBasis: string;
    FullPath: string;
  end;

function ColorToHex(AColor: Longint): string;
function FmxColorToHex(const S: string): string;
function Uint32ToHex(AColor: Cardinal): string;
function CalcLuminance(const HexColor: string; out Lum: Double): Boolean;
function ThemeFromBackground(const BgHex: string): string;
function PlatformsFromTarget(const Target: string): TArray<string>;
function GetStem(const AFileName: string): string;

implementation

function ColorToHex(AColor: Longint): string;
var
  R, G, B: Byte;
begin
  R := AColor and $FF;
  G := (AColor shr 8) and $FF;
  B := (AColor shr 16) and $FF;
  Result := Format('#%.2X%.2X%.2X', [R, G, B]);
end;

function Uint32ToHex(AColor: Cardinal): string;
var
  R, G, B: Byte;
begin
  R := (AColor shr 16) and $FF;
  G := (AColor shr 8) and $FF;
  B := AColor and $FF;
  Result := Format('#%.2X%.2X%.2X', [R, G, B]);
end;

function FmxColorToHex(const S: string): string;
var
  Trimmed, Low, HexDigits: string;
begin
  Result := '';
  Trimmed := Trim(S);
  if Trimmed = '' then
    Exit;

  Low := LowerCase(Trimmed);
  if Low = 'clablack' then Exit('#000000');
  if Low = 'cladarkgray' then Exit('#A9A9A9');
  if Low = 'clagainsboro' then Exit('#DCDCDC');
  if Low = 'clagray' then Exit('#808080');
  if Low = 'clalightgray' then Exit('#D3D3D3');
  if Low = 'clanull' then Exit('');
  if Low = 'clared' then Exit('#FF0000');
  if Low = 'clasilver' then Exit('#C0C0C0');
  if Low = 'clawhite' then Exit('#FFFFFF');
  if Low = 'clawhitesmoke' then Exit('#F5F5F5');

  if StartsText('x', Trimmed) then
  begin
    HexDigits := Copy(Trimmed, 2, Length(Trimmed) - 1);
    if Length(HexDigits) = 8 then
      Result := '#' + UpperCase(Copy(HexDigits, 3, 6))
    else if Length(HexDigits) = 6 then
      Result := '#' + UpperCase(HexDigits);
  end;
end;

function SrgbToLinear(C: Byte): Double;
var
  Csrgb: Double;
begin
  Csrgb := C / 255.0;
  if Csrgb <= 0.04045 then
    Result := Csrgb / 12.92
  else
    Result := Power((Csrgb + 0.055) / 1.055, 2.4);
end;

function CalcLuminance(const HexColor: string; out Lum: Double): Boolean;
var
  R, G, B: Integer;
  RL, GL, BL: Double;
begin
  Result := False;
  Lum := 0.0;
  if (Length(HexColor) <> 7) or (HexColor[1] <> '#') then
    Exit;
  try
    R := StrToInt('$' + Copy(HexColor, 2, 2));
    G := StrToInt('$' + Copy(HexColor, 4, 2));
    B := StrToInt('$' + Copy(HexColor, 6, 2));
    RL := SrgbToLinear(R);
    GL := SrgbToLinear(G);
    BL := SrgbToLinear(B);
    Lum := 0.2126 * RL + 0.7152 * GL + 0.0722 * BL;
    Result := True;
  except
    Result := False;
  end;
end;

function ThemeFromBackground(const BgHex: string): string;
var
  Lum: Double;
begin
  if (BgHex = '') or not CalcLuminance(BgHex, Lum) then
    Result := 'unknown'
  else if Lum < 0.4 then
    Result := 'dark'
  else
    Result := 'light';
end;

function PlatformsFromTarget(const Target: string): TArray<string>;
var
  Up: string;
  List: TList<string>;
begin
  Up := UpperCase(Target);
  List := TList<string>.Create;
  try
    if (Pos('[MSWINDOWS]', Up) > 0) or (Pos('[WINDOWS]', Up) > 0) then
      List.Add('Windows');
    if Pos('[MACOS]', Up) > 0 then
      List.Add('macOS');
    if (Pos('[IOS]', Up) > 0) or (Pos('[IOS7]', Up) > 0) or (Pos('[IOSALTERNATE]', Up) > 0) then
      List.Add('iOS');
    if Pos('[ANDROID]', Up) > 0 then
      List.Add('Android');
    if Pos('[LINUX]', Up) > 0 then
      List.Add('Linux');

    if List.Count = 0 then
    begin
      List.Add('Windows');
      List.Add('macOS');
      List.Add('iOS');
      List.Add('Android');
      List.Add('Linux');
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function GetStem(const AFileName: string): string;
var
  Base: string;
begin
  Base := ChangeFileExt(AFileName, '');
  if EndsText('Dark', Base) then
    Base := Copy(Base, 1, Length(Base) - 4)
  else if EndsText('Light', Base) then
    Base := Copy(Base, 1, Length(Base) - 5)
  else if EndsText('Black', Base) then
    Base := Copy(Base, 1, Length(Base) - 5);
  Result := LowerCase(Base);
end;

function TStyleColors.HasAny: Boolean;
begin
  Result := (Background <> '') or (Surface <> '') or (Text <> '') or
            (TextDisabled <> '') or (Accent <> '') or (AccentText <> '') or
            (Border <> '');
end;

function TStyleColors.ToJSON(const Indent: string): string;
var
  Lines: TList<string>;
  I: Integer;
begin
  Lines := TList<string>.Create;
  try
    if Background <> '' then Lines.Add(Format('%s  "background": "%s"', [Indent, Background]));
    if Surface <> '' then Lines.Add(Format('%s  "surface": "%s"', [Indent, Surface]));
    if Text <> '' then Lines.Add(Format('%s  "text": "%s"', [Indent, Text]));
    if TextDisabled <> '' then Lines.Add(Format('%s  "textDisabled": "%s"', [Indent, TextDisabled]));
    if Accent <> '' then Lines.Add(Format('%s  "accent": "%s"', [Indent, Accent]));
    if AccentText <> '' then Lines.Add(Format('%s  "accentText": "%s"', [Indent, AccentText]));
    if Border <> '' then Lines.Add(Format('%s  "border": "%s"', [Indent, Border]));

    if Lines.Count = 0 then
      Result := '{}'
    else
    begin
      Result := '{'#10;
      for I := 0 to Lines.Count - 1 do
      begin
        Result := Result + Lines[I];
        if I < Lines.Count - 1 then
          Result := Result + ',';
        Result := Result + #10;
      end;
      Result := Result + Indent + '}';
    end;
  finally
    Lines.Free;
  end;
end;

end.
