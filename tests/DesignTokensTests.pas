unit DesignTokensTests;

{ Tests for RADAgent.DesignTokens: front matter parsing, flow mappings, and token extraction. }

interface

uses
  TestCheck;

procedure RunDesignTokensTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Generics.Collections, RADAgent.DesignTokens;

procedure RunDesignTokensTests(const Check: TCheckProc);
var
  Yaml, YamlFlow: string;
  Map: TFrontMatter;
  Px: Double;
  Rgb: Cardinal;
  Dims, Sizes: TArray<Double>;
  Fams: TArray<string>;
  Cols: TArray<Cardinal>;
begin
  { 1. Nested block maps, quotes with '#' and inline comments, CRLF and sequences }
  Yaml :=
    '---'#13#10 +
    'version: alpha'#13#10 +
    'name: "Nanum #1 Viewer"'#13#10 +
    'radstudio:'#13#10 +
    '  framework: FMX                 # target framework'#13#10 +
    '  style: "Windows 10 #2 Modern"'#13#10 +
    'colors:'#13#10 +
    '  primary: "#0067C0"             # brand blue'#13#10 +
    '  surface: ''#F3F3F3'''#13#10 +
    'spacing:'#13#10 +
    '  xs: 4px'#13#10 +
    '  sm: 8px'#13#10 +
    'typography:'#13#10 +
    '  body:'#13#10 +
    '    fontFamily: Segoe UI Variable'#13#10 +
    '    fontSize: 14px'#13#10 +
    'platforms:'#13#10 +
    '  - Windows'#13#10 +
    '  - macOS'#13#10 +
    'footer: true'#13#10 +
    '---'#13#10 +
    '# Markdown content below';

  Map := ReadFrontMatter(Yaml);
  try
    Check(Map.Count >= 9, 'front matter has parsed keys');
    Check(Map['version'] = 'alpha', 'scalar at root');
    Check(Map['name'] = 'Nanum #1 Viewer', 'quotes with # preserved; no comment truncation');
    Check(Map['radstudio.framework'] = 'FMX', 'nested block key radstudio.framework');
    Check(Map['radstudio.style'] = 'Windows 10 #2 Modern', 'nested key with quoted #');
    Check(Map['colors.primary'] = '#0067C0', 'hex color value unquoted');
    Check(Map['colors.surface'] = '#F3F3F3', 'single quoted hex color');
    Check(Map['spacing.xs'] = '4px', 'spacing.xs dimension');
    Check(Map['typography.body.fontFamily'] = 'Segoe UI Variable', 'three-level nested map');
    Check(Map['typography.body.fontSize'] = '14px', 'three-level nested dimension');
    Check(Map['footer'] = 'true', 'root key after sequence is read');
    Check(not Map.ContainsKey('platforms'), 'sequences are skipped');

    Dims := Dimensions(Map, 'spacing');
    Check(Length(Dims) = 2, 'dimensions for spacing returns 2 values');
    Sizes := FontSizes(Map);
    Check((Length(Sizes) = 1) and (Abs(Sizes[0] - 14.0) < 0.001), 'fontSizes returns 14px');
    Fams := FontFamilies(Map);
    Check((Length(Fams) = 1) and (Fams[0] = 'Segoe UI Variable'), 'fontFamilies returns Segoe UI Variable');
    Cols := Colors(Map);
    Check(Length(Cols) = 2, 'colors returns 2 parsed RGB values');
  finally
    Map.Free;
  end;

  { 2. Single-line flow mappings (contract addition) }
  YamlFlow :=
    '---'#10 +
    'typography:'#10 +
    '  body-medium: { fontFamily: Roboto, fontSize: "14px", fontWeight: 400, lineHeight: "20px" }'#10 +
    'components:'#10 +
    '  button: { height: "40px", padding: "0px 24px", rounded: "{rounded.full}" }'#10 +
    '---';

  Map := ReadFrontMatter(YamlFlow);
  try
    Check(Map['typography.body-medium.fontFamily'] = 'Roboto', 'flow map unquoted value');
    Check(Map['typography.body-medium.fontSize'] = '14px', 'flow map quoted value');
    Check(Map['typography.body-medium.fontWeight'] = '400', 'flow map integer value');
    Check(Map['typography.body-medium.lineHeight'] = '20px', 'flow map line height');
    Check(Map['components.button.height'] = '40px', 'flow map component height');
    Check(Map['components.button.rounded'] = '{rounded.full}', 'flow map value with braces in quotes');
  finally
    Map.Free;
  end;

  { 3. Missing front matter / empty delimiters }
  Map := ReadFrontMatter('No front matter here');
  try
    Check(Map.Count = 0, 'no front matter returns empty map');
  finally
    Map.Free;
  end;

  Map := ReadFrontMatter('---'#13#10'key: value'#13#10);
  try
    Check(Map.Count = 0, 'only one delimiter returns empty map');
  finally
    Map.Free;
  end;

  { 4. DimensionPx: px, rem, em, pt, unitless, full radius, invalid }
  Check(DimensionPx('8px', Px) and (Abs(Px - 8.0) < 0.001), 'dimension 8px');
  Check(DimensionPx('8', Px) and (Abs(Px - 8.0) < 0.001), 'dimension unitless 8');
  Check(DimensionPx('0.5rem', Px) and (Abs(Px - 8.0) < 0.001), 'dimension 0.5rem is 8px');
  Check(DimensionPx('1.5em', Px) and (Abs(Px - 24.0) < 0.001), 'dimension 1.5em is 24px');
  Check(DimensionPx('10pt', Px) and (Abs(Px - (10.0 * 96.0 / 72.0)) < 0.001), 'dimension 10pt conversion');
  Check(DimensionPx('9999px', Px) and (Abs(Px - 9999.0) < 0.001), 'dimension full radius 9999px');
  Check(not DimensionPx('10%', Px), 'dimension percent rejected');
  Check(not DimensionPx('invalid', Px), 'dimension text rejected');
  Check(not DimensionPx('', Px), 'empty dimension rejected');

  { 5. ColorRgb: #RGB, #RRGGBB, #RRGGBBAA (alpha dropped), invalid }
  Check(ColorRgb('#F3A', Rgb) and (Rgb = $00FF33AA), 'color #RGB expanded to $FF33AA');
  Check(ColorRgb('#0067C0', Rgb) and (Rgb = $000067C0), 'color #RRGGBB parsed to $0067C0');
  Check(ColorRgb('#0067C080', Rgb) and (Rgb = $000067C0), 'color #RRGGBBAA alpha dropped');
  Check(not ColorRgb('#12', Rgb), 'color short hex rejected');
  Check(not ColorRgb('#12345', Rgb), 'color 5-digit hex rejected');
  Check(not ColorRgb('#XYZ123', Rgb), 'color non-hex rejected');
  Check(not ColorRgb('blue', Rgb), 'named color rejected');
end;

end.
