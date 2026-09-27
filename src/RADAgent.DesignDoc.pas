unit RADAgent.DesignDoc;

{ The project's DESIGN.md (Google Labs DESIGN.md format): the chosen RAD Studio style under
  radstudio:, the colors read from that style as style-* tokens, and the platform preset's tokens
  and guidance for everything a style does not define. English: omp reads it. No ToolsAPI. }

interface

uses
  RADAgent.DesignCatalog;

{ Dark: the style's counterpart (FileName '' when there is none). PresetId: the preset to use. }
function ComposeDesignDoc(const ProjectName: string; const Style, Dark: TDesignStyle;
  const PresetId: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

function Quoted(const Value: string): string;
begin
  Result := '"' + StringReplace(StringReplace(Value, '\', '\\', [rfReplaceAll]), '"', '\"',
    [rfReplaceAll]) + '"';
end;

{ backgroundColor -> background-color; textDisabled -> text-disabled. }
function TokenName(const Role: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Role do
    if CharInSet(C, ['A'..'Z']) then
      Result := Result + '-' + LowerCase(C)
    else
      Result := Result + C;
end;

procedure AddStyleColors(Lines: TStrings; const Style: TDesignStyle; const Suffix: string);
var
  Pair: TPair<string, string>;
begin
  for Pair in Style.Colors do
    Lines.Add('  style-' + TokenName(Pair.Key) + Suffix + ': ' + Quoted(Pair.Value));
end;

{ Splits a preset into its front matter lines (without the --- lines) and its body. }
procedure SplitPreset(const Text: string; FrontMatter: TStrings; out Body: string);
var
  All: TStringList;
  Index, Closing: Integer;
begin
  FrontMatter.Clear;
  Body := Text;
  All := TStringList.Create;
  try
    All.Text := Text;
    if (All.Count = 0) or (Trim(All[0]) <> '---') then
      Exit;
    Closing := -1;
    for Index := 1 to All.Count - 1 do
      if Trim(All[Index]) = '---' then
      begin
        Closing := Index;
        Break;
      end;
    if Closing < 0 then
      Exit;
    for Index := 1 to Closing - 1 do
      FrontMatter.Add(All[Index]);
    Body := '';
    for Index := Closing + 1 to All.Count - 1 do
      Body := Body + All[Index] + sLineBreak;
  finally
    All.Free;
  end;
end;

function TopKey(const Line: string): string;
begin
  Result := '';
  if (Line <> '') and not CharInSet(Line[1], [' ', #9, '#', '-']) and (Pos(':', Line) > 0) then
    Result := Trim(Copy(Line, 1, Pos(':', Line) - 1));
end;

function StyleParagraph(const Style, Dark: TDesignStyle; const PresetId: string): string;
begin
  Result := Format('Controls are drawn by the RAD Studio %s style "%s" (%s)',
    [Style.Framework, Style.Name, Style.FileName]);
  if Dark.FileName <> '' then
    Result := Result + Format('; its dark counterpart is "%s" (%s)', [Dark.Name, Dark.FileName]);
  Result := Result + Format('. Where its look comes from: %s (basis: %s', [Style.System, Style.Basis]);
  if Style.Evidence <> '' then
    Result := Result + '; ' + Style.Evidence;
  Result := Result + Format('). Spacing, type ramp, radii and the guidance below come from the %s ' +
    'preset', [PresetTitle(PresetId)]);
  if SameText(Style.PresetBasis, 'match') and SameText(Style.Preset, PresetId) then
    Result := Result + ', the design system the style itself follows.'
  else
    Result := Result + ', chosen to supplement the style: it is not where the style comes from, so ' +
      'where the two disagree on a control''s own look, the style wins.';
  Result := Result + ' The style-* colors are what the style paints; use them for custom surfaces ' +
    'so they match the controls, and use the preset colors only where the style has no role.';
end;

function ComposeDesignDoc(const ProjectName: string; const Style, Dark: TDesignStyle;
  const PresetId: string): string;
var
  Lines, Preset: TStringList;
  Body, Key, Paragraph: string;
  Index: Integer;
  HasColors, Inserted: Boolean;
begin
  Lines := TStringList.Create;
  Preset := TStringList.Create;
  try
    SplitPreset(PresetText(PresetId), Preset, Body);
    Lines.Add('---');
    Lines.Add('version: alpha');
    Lines.Add('name: ' + Quoted(ProjectName + ' design'));
    Lines.Add('description: ' + Quoted(Format('%s (%s) uses the RAD Studio style %s for controls and ' +
      'the %s preset for layout, type and shape.', [ProjectName, Style.Framework, Style.Name,
      PresetTitle(PresetId)])));
    Lines.Add('radstudio:');
    Lines.Add('  framework: ' + Style.Framework);
    Lines.Add('  style: ' + Quoted(Style.Name));
    Lines.Add('  styleFile: ' + Quoted(Style.FileName));
    if Dark.FileName <> '' then
    begin
      Lines.Add('  darkStyle: ' + Quoted(Dark.Name));
      Lines.Add('  darkStyleFile: ' + Quoted(Dark.FileName));
    end;
    Lines.Add('  provenance: ' + Quoted(Style.System + ' (' + Style.Basis + ')'));
    Lines.Add('  preset: ' + PresetId);
    if SameText(Style.Preset, PresetId) then
      Lines.Add('  presetBasis: ' + Style.PresetBasis)
    else
      Lines.Add('  presetBasis: user-choice');
    HasColors := False;
    Inserted := False;
    for Index := 0 to Preset.Count - 1 do
    begin
      Key := TopKey(Preset[Index]);
      if SameText(Key, 'version') or SameText(Key, 'name') or SameText(Key, 'description') then
        Continue;
      Lines.Add(Preset[Index]);
      if SameText(Key, 'colors') then
      begin
        HasColors := True;
        AddStyleColors(Lines, Style, '');
        AddStyleColors(Lines, Dark, '-dark');
        Inserted := True;
      end;
    end;
    if not HasColors and ((Length(Style.Colors) > 0) or (Length(Dark.Colors) > 0)) then
    begin
      Lines.Add('colors:');
      AddStyleColors(Lines, Style, '');
      AddStyleColors(Lines, Dark, '-dark');
      Inserted := True;
    end;
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('# ' + ProjectName + ' design');
    Lines.Add('');
    Paragraph := StyleParagraph(Style, Dark, PresetId);
    if not Inserted then
      Paragraph := Paragraph + ' No colors could be read from this style.';
    { The paragraph opens the Overview section so the section order stays the spec's. }
    Index := Pos('## Overview', Body);
    if Index > 0 then
    begin
      Index := Index + Length('## Overview');
      Body := Copy(Body, 1, Index - 1) + sLineBreak + sLineBreak + Paragraph + sLineBreak +
        Copy(Body, Index, MaxInt);
    end
    else
      Body := '## Overview' + sLineBreak + sLineBreak + Paragraph + sLineBreak + sLineBreak + Body;
    Result := Lines.Text + Body;
  finally
    Preset.Free;
    Lines.Free;
  end;
end;

end.
