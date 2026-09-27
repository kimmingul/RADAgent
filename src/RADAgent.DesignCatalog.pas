unit RADAgent.DesignCatalog;

{ The VCL and FMX styles RAD Studio installs, from src\design\style-map.json (RCDATA DESIGN_STYLES,
  made by scripts\StyleCatalog): name, light or dark, the counterpart of the other theme, colors
  read from the style, where its look comes from (provenance) and which platform preset
  (src\design\presets, RCDATA DESIGN_PRESET_*) supplies what a style does not define: spacing,
  type ramp, corner radii. Style files added to the Styles folder later are listed as unclassified.
  No ToolsAPI. }

interface

uses
  System.Generics.Collections;

type
  TDesignStyle = record
    FileName, Framework, Format, Name, Theme, Pair: string;
    Platforms: TArray<string>;
    Loadable: Boolean;
    { Role (background, surface, text, textDisabled, accent, accentText, border) -> #RRGGBB. }
    Colors: TArray<TPair<string, string>>;
    { system (windows-11, material-3, none, ...), basis (vendor-statement, file-content, name, none,
      unclassified) and the evidence for it. }
    System, Basis, Evidence: string;
    { Preset id and whether it is the style's own design system (match) or a chosen supplement
      (policy). }
    Preset, PresetBasis: string;
    { The installed file ('' when missing) and the same with a $(BDSCOMMONDIR)/$(BDS) macro. }
    Path, MacroPath: string;
  end;

{ Installed styles of Framework ('VCL' or 'FMX'): styles matching their preset first, then by how
  well their provenance is known, unclassified ones last. }
function InstalledStyles(const Framework: string): TArray<TDesignStyle>;
{ An installed style of Framework by file name (with or without extension) or style name. }
function FindStyle(const Framework, FileOrName: string; out Style: TDesignStyle): Boolean;
{ The DESIGN.md text of a preset ('' for an unknown id) and its display name. }
function PresetText(const Id: string): string;
function PresetTitle(const Id: string): string;
function PresetIds: TArray<string>;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows, Winapi.ShlObj,
  System.Generics.Defaults, Vcl.Themes;

const
  Presets: array[0..2, 0..2] of string = (
    ('fluent-windows11', 'DESIGN_PRESET_FLUENT', 'Windows 11 (Fluent 2)'),
    ('material3', 'DESIGN_PRESET_MATERIAL3', 'Material 3'),
    ('apple-macos', 'DESIGN_PRESET_MACOS', 'macOS (Apple HIG)'));

function ResourceText(const Name: string): string;
var
  Stream: TResourceStream;
  Bytes: TBytes;
begin
  Result := '';
  if FindResource(HInstance, PChar(Name), RT_RCDATA) = 0 then
    Exit;
  Stream := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then
      Stream.ReadBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function PresetIds: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(Presets) do
    Result := Result + [Presets[Index, 0]];
end;

function PresetText(const Id: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(Presets) do
    if SameText(Presets[Index, 0], Id) then
      Exit(ResourceText(Presets[Index, 1]));
end;

function PresetTitle(const Id: string): string;
var
  Index: Integer;
begin
  Result := Id;
  for Index := 0 to High(Presets) do
    if SameText(Presets[Index, 0], Id) then
      Exit(Presets[Index, 2]);
end;

function BdsDir: string;
begin
  Result := GetEnvironmentVariable('BDS');
  if Result = '' then
    Result := ExtractFileDir(ExtractFileDir(ParamStr(0)));
  Result := ExcludeTrailingPathDelimiter(Result);
end;

{ $(BDSCOMMONDIR): the IDE sets it; else Public Documents\Embarcadero\Studio\<version>. }
function CommonDir: string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  Result := GetEnvironmentVariable('BDSCOMMONDIR');
  if (Result = '') and Succeeded(SHGetFolderPath(0, CSIDL_COMMON_DOCUMENTS, 0, 0, Buf)) then
    Result := TPath.Combine(TPath.Combine(Buf, 'Embarcadero\Studio'), ExtractFileName(BdsDir));
  Result := ExcludeTrailingPathDelimiter(Result);
end;

function RedistDir(const Framework: string): string;
begin
  if SameText(Framework, 'FMX') then
    Result := BdsDir + '\Redist\styles\Fmx'
  else
    Result := BdsDir + '\Redist\styles\vcl';
end;

{ Sets Path and MacroPath from the catalog's folder fields; False when the file is not there. }
function Locate(var Style: TDesignStyle; const Folder, Subfolder: string): Boolean;
var
  Relative: string;
begin
  Relative := Style.FileName;
  if Subfolder <> '' then
    Relative := Subfolder + '\' + Relative;
  if SameText(Folder, 'redist') then
  begin
    Style.Path := TPath.Combine(RedistDir(Style.Framework), Style.FileName);
    if SameText(Style.Framework, 'FMX') then
      Style.MacroPath := '$(BDS)\Redist\styles\Fmx\' + Style.FileName
    else
      Style.MacroPath := '$(BDS)\Redist\styles\vcl\' + Style.FileName;
  end
  else
  begin
    Style.Path := TPath.Combine(CommonDir + '\Styles', Relative);
    Style.MacroPath := '$(BDSCOMMONDIR)\Styles\' + Relative;
  end;
  Result := FileExists(Style.Path);
  if not Result then
    Style.Path := '';
end;

function JsonText(Obj: TJSONObject; const Name: string): string;
begin
  Result := '';
  if (Obj <> nil) and (Obj.GetValue(Name) is TJSONString) then
    Result := TJSONString(Obj.GetValue(Name)).Value;
end;

function ReadEntry(Item: TJSONObject; out Style: TDesignStyle): Boolean;
var
  Value, Platform: TJSONValue;
  Colors, Provenance: TJSONObject;
  Pair: TJSONPair;
begin
  Style := Default(TDesignStyle);
  Style.FileName := JsonText(Item, 'file');
  Style.Framework := JsonText(Item, 'framework');
  Style.Format := JsonText(Item, 'format');
  Style.Name := JsonText(Item, 'name');
  Style.Theme := JsonText(Item, 'theme');
  Style.Pair := JsonText(Item, 'pair');
  Style.Preset := JsonText(Item, 'preset');
  Style.PresetBasis := JsonText(Item, 'presetBasis');
  Style.Loadable := not ((Item.GetValue('loadable') is TJSONBool) and
    not TJSONBool(Item.GetValue('loadable')).AsBoolean);
  Value := Item.GetValue('platforms');
  if Value is TJSONArray then
    for Platform in TJSONArray(Value) do
      if Platform is TJSONString then
        Style.Platforms := Style.Platforms + [TJSONString(Platform).Value];
  if Item.GetValue('colors') is TJSONObject then
  begin
    Colors := TJSONObject(Item.GetValue('colors'));
    for Pair in Colors do
      if Pair.JsonValue is TJSONString then
        Style.Colors := Style.Colors + [TPair<string, string>.Create(Pair.JsonString.Value,
          TJSONString(Pair.JsonValue).Value)];
  end;
  if Item.GetValue('provenance') is TJSONObject then
  begin
    Provenance := TJSONObject(Item.GetValue('provenance'));
    Style.System := JsonText(Provenance, 'system');
    Style.Basis := JsonText(Provenance, 'basis');
    Style.Evidence := JsonText(Provenance, 'evidence');
  end;
  Result := Locate(Style, JsonText(Item, 'folder'), JsonText(Item, 'subfolder'));
end;

{ A style file the catalog does not know: its name (VCL: from the file header), no colors, the
  framework's usual preset as a policy. }
function Unclassified(const Framework, Path, Relative: string): TDesignStyle;
var
  Info: TStyleInfo;
begin
  Result := Default(TDesignStyle);
  Result.FileName := ExtractFileName(Path);
  Result.Framework := Framework;
  Result.Format := LowerCase(Copy(ExtractFileExt(Path), 2, MaxInt));
  Result.Name := ChangeFileExt(Result.FileName, '');
  if SameText(Framework, 'VCL') and TStyleManager.IsValidStyle(Path, Info) then
    Result.Name := Info.Name;
  Result.Theme := 'unknown';
  Result.Loadable := not SameText(Result.Format, 'fmxstyle');
  Result.System := 'unknown';
  Result.Basis := 'unclassified';
  Result.Evidence := 'Not in RAD Agent''s catalog (added after RAD Studio was installed).';
  Result.Preset := 'fluent-windows11';
  Result.PresetBasis := 'policy';
  Result.Path := Path;
  Result.MacroPath := '$(BDSCOMMONDIR)\Styles\' + Relative;
end;

function IsStyleFile(const Framework, Path: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  if SameText(Framework, 'VCL') then
    Result := Ext = '.vsf'
  else
    Result := (Ext = '.style') or (Ext = '.fsf');
end;

{ Pick-list order: a style whose preset is its own design system, then verified provenance, then
  provenance by name only, then Embarcadero skins, then unclassified files. }
function Rank(const Style: TDesignStyle): Integer;
begin
  if SameText(Style.PresetBasis, 'match') then
    Result := 0
  else if SameText(Style.Basis, 'vendor-statement') or SameText(Style.Basis, 'file-content') then
    Result := 1
  else if SameText(Style.Basis, 'name') then
    Result := 2
  else if SameText(Style.Basis, 'none') then
    Result := 3
  else
    Result := 4;
end;

function InstalledStyles(const Framework: string): TArray<TDesignStyle>;
var
  Root: TJSONValue;
  Item: TJSONValue;
  Style: TDesignStyle;
  Known: TDictionary<string, Boolean>;
  Path, StylesDir: string;
begin
  Result := nil;
  Known := TDictionary<string, Boolean>.Create;
  Root := TJSONObject.ParseJSONValue(ResourceText('DESIGN_STYLES'));
  try
    if (Root is TJSONObject) and (TJSONObject(Root).GetValue('styles') is TJSONArray) then
      for Item in TJSONArray(TJSONObject(Root).GetValue('styles')) do
        if (Item is TJSONObject) and ReadEntry(TJSONObject(Item), Style) and
          SameText(Style.Framework, Framework) then
        begin
          Result := Result + [Style];
          Known.AddOrSetValue(LowerCase(Style.FileName), True);
        end;
    StylesDir := CommonDir + '\Styles';
    if TDirectory.Exists(StylesDir) then
      for Path in TDirectory.GetFiles(StylesDir, '*.*', TSearchOption.soAllDirectories) do
        if IsStyleFile(Framework, Path) and not Known.ContainsKey(LowerCase(ExtractFileName(Path))) then
        begin
          Known.Add(LowerCase(ExtractFileName(Path)), True);
          Result := Result + [Unclassified(Framework, Path,
            ExtractRelativePath(IncludeTrailingPathDelimiter(StylesDir), Path))];
        end;
    { Within a rank, by file name. }
    TArray.Sort<TDesignStyle>(Result, TComparer<TDesignStyle>.Construct(
      function(const A, B: TDesignStyle): Integer
      begin
        Result := Rank(A) - Rank(B);
        if Result = 0 then
          Result := CompareText(A.FileName, B.FileName);
      end));
  finally
    Root.Free;
    Known.Free;
  end;
end;

function FindStyle(const Framework, FileOrName: string; out Style: TDesignStyle): Boolean;
var
  Item: TDesignStyle;
  Wanted: string;
begin
  Result := False;
  Style := Default(TDesignStyle);
  Wanted := Trim(FileOrName);
  if Wanted = '' then
    Exit;
  for Item in InstalledStyles(Framework) do
    if SameText(Item.FileName, Wanted) or SameText(ChangeFileExt(Item.FileName, ''), Wanted) or
      SameText(Item.Name, Wanted) then
    begin
      Style := Item;
      Exit(True);
    end;
end;

end.
