unit RADAgent.DesignLintRules;

{ Design lint rules evaluation: spacing, typography, literal-color, radius.
  Pure TypInfo/RTTI property inspection with no FMX units in the BPL. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TDesignLintFinding = record
    Component: string;
    Rule: string;
    Value: string;
    Expected: string;
    Message: string;
  end;

  TDesignRulesContext = record
    Framework: string;
    StyleName: string;
    PixelsPerInch: Integer;
    SpacingScale: TArray<Double>;
    RoundedScale: TArray<Double>;
    FontSizes: TArray<Double>;
    FontFamilies: TArray<string>;
    Colors: TArray<Cardinal>;
  end;

function ParentName(Component: TComponent): string;
function IsControlAligned(Component: TComponent): Boolean;
function IsInScale(Value: Double; const Scale: TArray<Double>; Tolerance: Double): Boolean;
function ScaleToString(const Scale: TArray<Double>; const UnitStr: string = 'px'): string;
function GetNumericProp(Instance: TObject; const PropName: string; out Val: Double): Boolean;
{ The object property, nil when the class has no such published property. }
function ObjProp(Instance: TObject; const PropName: string): TObject;
procedure AddFinding(var Findings: TList<TDesignLintFinding>; const Comp, Rule, Val, Exp, Msg: string);

procedure CheckSpacing(Component: TComponent; const Ctx: TDesignRulesContext; var Findings: TList<TDesignLintFinding>);
procedure CheckTypography(Component: TComponent; const Ctx: TDesignRulesContext; var Findings: TList<TDesignLintFinding>);
procedure CheckColors(Component: TComponent; const Ctx: TDesignRulesContext; var Findings: TList<TDesignLintFinding>);
procedure CheckRadius(Component: TComponent; const Ctx: TDesignRulesContext; var Findings: TList<TDesignLintFinding>);

implementation

uses
  System.TypInfo, System.Rtti, Vcl.Controls;

function ObjProp(Instance: TObject; const PropName: string): TObject;
begin
  Result := nil;
  if (Instance <> nil) and (GetPropInfo(Instance, PropName) <> nil) then
    Result := GetObjectProp(Instance, PropName);
end;

procedure AddFinding(var Findings: TList<TDesignLintFinding>; const Comp, Rule, Val, Exp, Msg: string);
var
  Item: TDesignLintFinding;
begin
  Item.Component := Comp; Item.Rule := Rule; Item.Value := Val;
  Item.Expected := Exp; Item.Message := Msg;
  Findings.Add(Item);
end;

function ParentName(Component: TComponent): string;
var
  Context: TRttiContext;
  Prop: TRttiProperty;
  Value: TObject;
begin
  Result := '';
  if Component is TControl then
  begin
    if TControl(Component).Parent <> nil then Result := TControl(Component).Parent.Name;
    Exit;
  end;
  Value := Component;
  repeat
    Prop := Context.GetType(Value.ClassType).GetProperty('Parent');
    if (Prop = nil) or not Prop.IsReadable or (Prop.PropertyType.TypeKind <> tkClass) then Exit;
    Value := Prop.GetValue(Value).AsObject;
  until not (Value is TComponent) or (TComponent(Value).Name <> '');
  if Value is TComponent then Result := TComponent(Value).Name;
end;

function GetNumericProp(Instance: TObject; const PropName: string; out Val: Double): Boolean;
var
  Prop: PPropInfo;
begin
  Val := 0; Result := False;
  if Instance <> nil then Prop := GetPropInfo(Instance, PropName) else Prop := nil;
  if Prop = nil then Exit;
  case Prop.PropType^.Kind of
    tkInteger: begin Val := GetOrdProp(Instance, Prop); Result := True; end;
    tkFloat: begin Val := GetFloatProp(Instance, Prop); Result := True; end;
    tkInt64: begin Val := GetInt64Prop(Instance, Prop); Result := True; end;
  end;
end;

function IsInScale(Value: Double; const Scale: TArray<Double>; Tolerance: Double): Boolean;
var
  Target: Double;
begin
  Result := False;
  for Target in Scale do
    if Abs(Value - Target) <= Tolerance + 0.0001 then Exit(True);
end;

function ScaleToString(const Scale: TArray<Double>; const UnitStr: string = 'px'): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Scale) do
  begin
    if I > 0 then Result := Result + ', ';
    Result := Result + FormatFloat('0.#', Scale[I], TFormatSettings.Invariant);
  end;
  if (Result <> '') and (UnitStr <> '') then Result := Result + UnitStr;
end;

function IsControlAligned(Component: TComponent): Boolean;
var
  Prop: PPropInfo;
  S: string;
begin
  Result := False;
  Prop := GetPropInfo(Component, 'Align');
  if Prop <> nil then
  begin
    S := GetEnumProp(Component, Prop);
    Result := (S <> '') and not SameText(S, 'alNone') and not SameText(S, 'None');
  end;
end;

function HasStyledSetting(Component: TComponent; TextSettingsObj: TObject; const SettingName: string): Boolean;
var
  Prop: PPropInfo;
  Owner: TObject;
begin
  Owner := Component;
  Prop := GetPropInfo(Component, 'StyledSettings');
  if Prop = nil then
  begin
    Owner := TextSettingsObj;
    Prop := GetPropInfo(TextSettingsObj, 'StyledSettings');
  end;
  Result := (Prop = nil) or GetSetProp(Owner, Prop, True).Contains(SettingName);
end;

function MatchesFontFamily(const ControlFamily: string; const AllowedFamilies: TArray<string>): Boolean;
var
  Allowed: string;
begin
  Result := False;
  if (ControlFamily = '') or (Length(AllowedFamilies) = 0) then Exit;
  { Weight or optical-size families of an allowed family count ("Segoe UI Variable Display Semibold"). }
  for Allowed in AllowedFamilies do
    if SameText(ControlFamily, Allowed) or ControlFamily.StartsWith(Allowed + ' ', True) or
       (Allowed.StartsWith('Segoe UI', True) and ControlFamily.StartsWith('Segoe UI', True)) then
      Exit(True);
end;

function IsColorInList(Rgb: Cardinal; const AllowedColors: TArray<Cardinal>): Boolean;
var
  C: Cardinal;
begin
  Result := False;
  for C in AllowedColors do if C = Rgb then Exit(True);
end;

procedure CheckBoundsObj(Component: TComponent; Obj: TObject; const PropName: string;
  const Scale: TArray<Double>; var Findings: TList<TDesignLintFinding>);
var
  Side, ValStr, ExpStr: string;
  Val: Double;
begin
  if Obj = nil then Exit;
  for Side in ['Left', 'Top', 'Right', 'Bottom'] do
    if GetNumericProp(Obj, Side, Val) and (Abs(Val) > 0.001) and not IsInScale(Val, Scale, 0.5) then
    begin
      ValStr := FormatFloat('0.#', Val, TFormatSettings.Invariant) + 'px';
      ExpStr := ScaleToString(Scale, 'px');
      AddFinding(Findings, Component.Name, 'spacing', ValStr, ExpStr,
        Format('%s.%s.%s (%s) is not in spacing scale (%s).', [Component.Name, PropName, Side, ValStr, ExpStr]));
    end;
end;

procedure CheckSpacing(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  AlignProp: PPropInfo;
begin
  if Length(Ctx.SpacingScale) = 0 then Exit;
  if Ctx.Framework = 'VCL' then
  begin
    AlignProp := GetPropInfo(Component, 'AlignWithMargins');
    if (AlignProp = nil) or (GetOrdProp(Component, AlignProp) <> 0) then
      CheckBoundsObj(Component, ObjProp(Component, 'Margins'), 'Margins', Ctx.SpacingScale, Findings);
  end
  else
    CheckBoundsObj(Component, ObjProp(Component, 'Margins'), 'Margins', Ctx.SpacingScale, Findings);
  CheckBoundsObj(Component, ObjProp(Component, 'Padding'), 'Padding', Ctx.SpacingScale, Findings);
end;

procedure CheckTypography(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  FontObj, TextSettingsObj: TObject;
  ParentProp: PPropInfo;
  PtVal, PxVal, HeightVal: Double;
  Fam, ValStr, ExpStr: string;
  FS: TFormatSettings;
  PPI: Integer;
begin
  FS := TFormatSettings.Invariant;
  if Ctx.Framework = 'VCL' then
  begin
    ParentProp := GetPropInfo(Component, 'ParentFont');
    if (ParentProp <> nil) and (GetOrdProp(Component, ParentProp) <> 0) then Exit;
    FontObj := ObjProp(Component, 'Font');
    if FontObj = nil then Exit;
    if Length(Ctx.FontSizes) > 0 then
    begin
      HeightVal := 0;
      if GetNumericProp(FontObj, 'Height', HeightVal) and (HeightVal < 0) then
      begin
        PPI := Ctx.PixelsPerInch;
        if PPI <= 0 then PPI := 96;
        PxVal := -HeightVal * 96.0 / PPI;
        if not IsInScale(PxVal, Ctx.FontSizes, 0.5) then
        begin
          ValStr := FormatFloat('0.#', PxVal, FS) + 'px';
          ExpStr := ScaleToString(Ctx.FontSizes, 'px');
          AddFinding(Findings, Component.Name, 'font-size', ValStr, ExpStr,
            Format('%s.Font.Height (%s) is not in typography fontSize scale (%s).', [Component.Name, ValStr, ExpStr]));
        end;
      end
      else if GetNumericProp(FontObj, 'Size', PtVal) and (PtVal > 0) then
      begin
        PxVal := PtVal * 96.0 / 72.0;
        if not IsInScale(PxVal, Ctx.FontSizes, 0.5) then
        begin
          ValStr := FormatFloat('0.#', PxVal, FS) + 'px (' + FormatFloat('0.#', PtVal, FS) + 'pt)';
          ExpStr := ScaleToString(Ctx.FontSizes, 'px');
          AddFinding(Findings, Component.Name, 'font-size', ValStr, ExpStr,
            Format('%s.Font.Size (%s) is not in typography fontSize scale (%s).', [Component.Name, ValStr, ExpStr]));
        end;
      end;
    end;
    if Length(Ctx.FontFamilies) > 0 then
    begin
      Fam := GetStrProp(FontObj, 'Name');
      if (Fam <> '') and not MatchesFontFamily(Fam, Ctx.FontFamilies) then
      begin
        ExpStr := string.Join(', ', Ctx.FontFamilies);
        AddFinding(Findings, Component.Name, 'font-family', Fam, ExpStr,
          Format('%s.Font.Name ("%s") is not in typography fontFamily (%s).', [Component.Name, Fam, ExpStr]));
      end;
    end;
  end
  else
  begin
    TextSettingsObj := ObjProp(Component, 'TextSettings');
    if TextSettingsObj = nil then Exit;
    FontObj := ObjProp(TextSettingsObj, 'Font');
    if FontObj = nil then Exit;
    if (Length(Ctx.FontSizes) > 0) and not HasStyledSetting(Component, TextSettingsObj, 'Size') and
      GetNumericProp(FontObj, 'Size', PxVal) and (PxVal > 0) and not IsInScale(PxVal, Ctx.FontSizes, 0.5) then
    begin
      ValStr := FormatFloat('0.#', PxVal, FS) + 'px';
      ExpStr := ScaleToString(Ctx.FontSizes, 'px');
      AddFinding(Findings, Component.Name, 'font-size', ValStr, ExpStr,
        Format('%s.TextSettings.Font.Size (%s) is not in typography fontSize scale (%s).', [Component.Name, ValStr, ExpStr]));
    end;
    if (Length(Ctx.FontFamilies) > 0) and not HasStyledSetting(Component, TextSettingsObj, 'Family') then
    begin
      Fam := GetStrProp(FontObj, 'Family');
      if (Fam <> '') and not MatchesFontFamily(Fam, Ctx.FontFamilies) then
      begin
        ExpStr := string.Join(', ', Ctx.FontFamilies);
        AddFinding(Findings, Component.Name, 'font-family', Fam, ExpStr,
          Format('%s.TextSettings.Font.Family ("%s") is not in typography fontFamily (%s).', [Component.Name, Fam, ExpStr]));
      end;
    end;
  end;
end;

procedure CheckBrushColor(Component: TComponent; Obj: TObject; const PropName: string;
  const Colors: TArray<Cardinal>; var Findings: TList<TDesignLintFinding>);
var
  KindProp, ColorProp: PPropInfo;
  Rgb: Cardinal;
begin
  if Obj = nil then Exit;
  KindProp := GetPropInfo(Obj, 'Kind');
  if (KindProp <> nil) and (GetEnumProp(Obj, KindProp) = 'None') then Exit;
  ColorProp := GetPropInfo(Obj, 'Color');
  if ColorProp <> nil then
  begin
    Rgb := Cardinal(GetOrdProp(Obj, ColorProp)) and $00FFFFFF;
    if not IsColorInList(Rgb, Colors) then
      AddFinding(Findings, Component.Name, 'literal-color', Format('#%0.6x', [Rgb]), 'one of DESIGN.md colors',
        Format('%s.%s.Color (%s) is not in DESIGN.md colors.', [Component.Name, PropName, Format('#%0.6x', [Rgb])]));
  end;
end;

procedure CheckColors(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  Prop, ColorProp: PPropInfo;
  ElementsStr, ValStr, ExpStr: string;
  FontObj, TextSettingsObj: TObject;
  ColorVal: Integer;
begin
  if Ctx.Framework = 'VCL' then
  begin
    if Ctx.StyleName = '' then Exit;
    Prop := GetPropInfo(Component, 'StyleElements');
    if Prop = nil then Exit;
    ElementsStr := GetSetProp(Component, Prop, True);
    if ElementsStr.Contains('seClient') then
    begin
      Prop := GetPropInfo(Component, 'ParentColor');
      ColorProp := GetPropInfo(Component, 'Color');
      if ((Prop = nil) or (GetOrdProp(Component, Prop) = 0)) and (ColorProp <> nil) then
      begin
        ColorVal := GetOrdProp(Component, ColorProp);
        if not ((ColorVal < 0) or (ColorVal = $20000000) or (ColorVal = $1FFFFFFF)) then
        begin
          ValStr := Format('$%0.6x', [ColorVal and $00FFFFFF]);
          ExpStr := 'system color (clBtnFace, clWindow, clWindowText, clHighlight) or remove seClient from StyleElements';
          AddFinding(Findings, Component.Name, 'literal-color', ValStr, ExpStr,
            Format('%s.Color uses literal color (%s) with seClient enabled under style "%s". Use a system color or remove seClient from StyleElements.',
              [Component.Name, ValStr, Ctx.StyleName]));
        end;
      end;
    end;
    if ElementsStr.Contains('seFont') then
    begin
      Prop := GetPropInfo(Component, 'ParentFont');
      FontObj := ObjProp(Component, 'Font');
      if ((Prop = nil) or (GetOrdProp(Component, Prop) = 0)) and (FontObj <> nil) then
      begin
        ColorProp := GetPropInfo(FontObj, 'Color');
        if ColorProp <> nil then
        begin
          ColorVal := GetOrdProp(FontObj, ColorProp);
          if not ((ColorVal < 0) or (ColorVal = $20000000) or (ColorVal = $1FFFFFFF)) then
          begin
            ValStr := Format('$%0.6x', [ColorVal and $00FFFFFF]);
            ExpStr := 'system color or remove seFont from StyleElements';
            AddFinding(Findings, Component.Name, 'literal-color', ValStr, ExpStr,
              Format('%s.Font.Color uses literal color (%s) with seFont enabled under style "%s". Use a system color or remove seFont from StyleElements.',
                [Component.Name, ValStr, Ctx.StyleName]));
          end;
        end;
      end;
    end;
  end
  else
  begin
    if Length(Ctx.Colors) = 0 then Exit;
    TextSettingsObj := ObjProp(Component, 'TextSettings');
    if (TextSettingsObj <> nil) and not HasStyledSetting(Component, TextSettingsObj, 'FontColor') then
    begin
      ColorProp := GetPropInfo(TextSettingsObj, 'FontColor');
      if ColorProp <> nil then
      begin
        ColorVal := Cardinal(GetOrdProp(TextSettingsObj, ColorProp)) and $00FFFFFF;
        if not IsColorInList(ColorVal, Ctx.Colors) then
          AddFinding(Findings, Component.Name, 'literal-color', Format('#%0.6x', [ColorVal]), 'one of DESIGN.md colors',
            Format('%s.TextSettings.FontColor (%s) is not in DESIGN.md colors.', [Component.Name, Format('#%0.6x', [ColorVal])]));
      end;
    end;
    CheckBrushColor(Component, ObjProp(Component, 'Fill'), 'Fill', Ctx.Colors, Findings);
    CheckBrushColor(Component, ObjProp(Component, 'Stroke'), 'Stroke', Ctx.Colors, Findings);
  end;
end;

procedure CheckRadius(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  Val: Double;
  PropName, ValStr, ExpStr: string;
begin
  if (Ctx.Framework <> 'FMX') or (Length(Ctx.RoundedScale) = 0) then Exit;
  for PropName in ['XRadius', 'YRadius'] do
    if GetNumericProp(Component, PropName, Val) and (Val > 0.001) and (Val < 999.0) and
      not IsInScale(Val, Ctx.RoundedScale, 0.5) then
    begin
      ValStr := FormatFloat('0.#', Val, TFormatSettings.Invariant) + 'px';
      ExpStr := ScaleToString(Ctx.RoundedScale, 'px');
      AddFinding(Findings, Component.Name, 'radius', ValStr, ExpStr,
        Format('%s.%s (%s) is not in rounded scale (%s).', [Component.Name, PropName, ValStr, ExpStr]));
    end;
end;

end.
