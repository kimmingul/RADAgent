unit RADAgent.DesignLintType;

{ rad.design_lint typography rules. Text: the font size must be on the DESIGN.md type ramp and
  the family one of its families (weight or optical-size families of an allowed family count).
  Icon glyphs (a family naming Icons, MDL2 Assets or Symbol) are not text: their size must be one
  Microsoft recommends for Segoe Fluent Icons (16, 20, 24, 32, 40, 48, 64) and their family is not
  checked. VCL reads Font (ParentFont False; px from a negative Height at the form's
  PixelsPerInch, else Size in points); FMX reads TextSettings.Font where StyledSettings leaves it to
  the control. Properties through TypInfo only. }

interface

uses
  System.Classes, System.Generics.Collections, RADAgent.DesignLintRules;

procedure CheckTypography(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);

implementation

uses
  System.SysUtils, System.StrUtils, System.TypInfo;

function IsIconFamily(const Family: string): Boolean;
begin
  Result := ContainsText(Family, 'Icons') or ContainsText(Family, 'MDL2') or
    ContainsText(Family, 'Symbol');
end;

function MatchesFontFamily(const ControlFamily: string; const AllowedFamilies: TArray<string>): Boolean;
var
  Allowed: string;
begin
  Result := False;
  for Allowed in AllowedFamilies do
    if SameText(ControlFamily, Allowed) or ControlFamily.StartsWith(Allowed + ' ', True) or
       (Allowed.StartsWith('Segoe UI', True) and ControlFamily.StartsWith('Segoe UI', True)) then
      Exit(True);
end;

procedure CheckValues(const Name, SizeProp, FamilyProp: string; Px: Double; const Family: string;
  CheckSize, CheckFamily: Boolean; const Ctx: TDesignRulesContext; var Findings: TList<TDesignLintFinding>);
var
  ValStr, ExpStr: string;
  Icons: TArray<Double>;
begin
  ValStr := FormatFloat('0.#', Px, TFormatSettings.Invariant) + 'px';
  if IsIconFamily(Family) then
  begin
    Icons := TArray<Double>.Create(16, 20, 24, 32, 40, 48, 64);
    if CheckSize and (Px > 0) and not IsInScale(Px, Icons, 0.5) then
      AddFinding(Findings, Name, 'icon-size', ValStr, ScaleToString(Icons, 'px'),
        Format('%s.%s (%s) is an icon glyph size off the recommended icon sizes (%s).',
        [Name, SizeProp, ValStr, ScaleToString(Icons, 'px')]));
    Exit;
  end;
  if CheckSize and (Px > 0) and (Length(Ctx.FontSizes) > 0) and not IsInScale(Px, Ctx.FontSizes, 0.5) then
  begin
    ExpStr := ScaleToString(Ctx.FontSizes, 'px');
    AddFinding(Findings, Name, 'font-size', ValStr, ExpStr,
      Format('%s.%s (%s) is not in typography fontSize scale (%s).', [Name, SizeProp, ValStr, ExpStr]));
  end;
  if CheckFamily and (Family <> '') and (Length(Ctx.FontFamilies) > 0) and
    not MatchesFontFamily(Family, Ctx.FontFamilies) then
  begin
    ExpStr := string.Join(', ', Ctx.FontFamilies);
    AddFinding(Findings, Name, 'font-family', Family, ExpStr,
      Format('%s.%s ("%s") is not in typography fontFamily (%s).', [Name, FamilyProp, Family, ExpStr]));
  end;
end;

function StrProp(Instance: TObject; const PropName: string): string;
begin
  Result := '';
  if (Instance <> nil) and (GetPropInfo(Instance, PropName) <> nil) then
    Result := GetStrProp(Instance, PropName);
end;

procedure CheckTypography(Component: TComponent; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  FontObj, TextSettingsObj: TObject;
  Value, Px: Double;
  PPI: Integer;
  SizeProp: string;
begin
  if Ctx.Framework = 'VCL' then
  begin
    if (GetPropInfo(Component, 'ParentFont') <> nil) and (GetOrdProp(Component, 'ParentFont') <> 0) then
      Exit;
    FontObj := ObjProp(Component, 'Font');
    if FontObj = nil then
      Exit;
    Px := 0;
    SizeProp := 'Font.Height';
    if GetNumericProp(FontObj, 'Height', Value) and (Value < 0) then
    begin
      PPI := Ctx.PixelsPerInch;
      if PPI <= 0 then
        PPI := 96;
      Px := -Value * 96.0 / PPI;
    end
    else if GetNumericProp(FontObj, 'Size', Value) and (Value > 0) then
    begin
      Px := Value * 96.0 / 72.0;
      SizeProp := 'Font.Size';
    end;
    CheckValues(Component.Name, SizeProp, 'Font.Name', Px, StrProp(FontObj, 'Name'), True, True, Ctx,
      Findings);
  end
  else
  begin
    TextSettingsObj := ObjProp(Component, 'TextSettings');
    FontObj := ObjProp(TextSettingsObj, 'Font');
    if FontObj = nil then
      Exit;
    if not GetNumericProp(FontObj, 'Size', Px) then
      Px := 0;
    CheckValues(Component.Name, 'TextSettings.Font.Size', 'TextSettings.Font.Family', Px,
      StrProp(FontObj, 'Family'), not HasStyledSetting(Component, TextSettingsObj, 'Size'),
      not HasStyledSetting(Component, TextSettingsObj, 'Family'), Ctx, Findings);
  end;
end;

end.
