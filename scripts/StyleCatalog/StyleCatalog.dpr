{ StyleCatalog: scans RAD Studio VCL and FMX styles to generate style-map.json.
  Run after installing a new RAD Studio release to update the catalog:
  StyleCatalog.exe [-common <BDSCOMMONDIR\Styles>] [-bds <BDS>] [-o <output.json>] }
program StyleCatalog;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  StyleCatalog.Types,
  StyleCatalog.Rules,
  StyleCatalog.Readers;

type
  TFileScanInfo = record
    FileName: string;
    Folder: string;
    SubFolder: string;
    FullPath: string;
    Framework: string;
    FormatName: string;
  end;

procedure ScanDir(const RootDir, Folder: string; ScanMap: TDictionary<string, TFileScanInfo>);
var
  Files: TArray<string>;
  F, Ext, Key, RelSub, SubFolder: string;
  Info: TFileScanInfo;
begin
  if not TDirectory.Exists(RootDir) then
    Exit;

  Files := TDirectory.GetFiles(RootDir, '*.*', TSearchOption.soAllDirectories);
  for F in Files do
  begin
    Ext := LowerCase(TPath.GetExtension(F));
    if (Ext = '.vsf') or (Ext = '.style') or (Ext = '.fsf') or (Ext = '.fmxstyle') then
    begin
      Key := LowerCase(TPath.GetFileName(F));
      if not ScanMap.ContainsKey(Key) then
      begin
        Info.FileName := TPath.GetFileName(F);
        Info.Folder := Folder;
        Info.FullPath := F;
        RelSub := ExtractRelativePath(IncludeTrailingPathDelimiter(RootDir), ExtractFilePath(F));
        RelSub := ExcludeTrailingPathDelimiter(RelSub);
        if (RelSub = '.') or (RelSub = '') then
          SubFolder := ''
        else
          SubFolder := StringReplace(RelSub, '/', '\', [rfReplaceAll]);
        Info.SubFolder := SubFolder;

        if Ext = '.vsf' then
        begin
          Info.Framework := 'VCL';
          Info.FormatName := 'vsf';
        end
        else if Ext = '.fsf' then
        begin
          Info.Framework := 'FMX';
          Info.FormatName := 'fsf';
        end
        else if Ext = '.fmxstyle' then
        begin
          Info.Framework := 'FMX';
          Info.FormatName := 'fmxstyle';
        end
        else
        begin
          Info.Framework := 'FMX';
          Info.FormatName := 'style';
        end;

        ScanMap.Add(Key, Info);
      end;
    end;
  end;
end;

procedure Main;
var
  CommonDir, BdsDir, OutFile: string;
  ScanMap: TDictionary<string, TFileScanInfo>;
  Entries: TList<TStyleEntry>;
  EntriesArr: TArray<TStyleEntry>;
  I: Integer;
  Entry: TStyleEntry;
  ScanInfo: TFileScanInfo;
  JSONStr: string;
  Lines: TStringList;
  VclCount, FmxCount: Integer;
  DarkCount, LightCount, UnknownCount: Integer;
  PresetCounts: TDictionary<string, Integer>;
  Pair: TPair<string, Integer>;
begin
  CommonDir := '';
  BdsDir := '';
  OutFile := '';

  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '-common') and (I < ParamCount) then
    begin
      Inc(I);
      CommonDir := ParamStr(I);
    end
    else if SameText(ParamStr(I), '-bds') and (I < ParamCount) then
    begin
      Inc(I);
      BdsDir := ParamStr(I);
    end
    else if SameText(ParamStr(I), '-o') and (I < ParamCount) then
    begin
      Inc(I);
      OutFile := ParamStr(I);
    end
    else if (CommonDir = '') and not StartsText('-', ParamStr(I)) then
      CommonDir := ParamStr(I)
    else if (BdsDir = '') and not StartsText('-', ParamStr(I)) then
      BdsDir := ParamStr(I);
    Inc(I);
  end;

  if CommonDir = '' then
    CommonDir := GetEnvironmentVariable('BDSCOMMONDIR');
  if (CommonDir <> '') and not SameText(ExtractFileName(CommonDir), 'Styles') then
    CommonDir := TPath.Combine(CommonDir, 'Styles');
  if (CommonDir = '') or not TDirectory.Exists(CommonDir) then
    CommonDir := 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Styles';

  if BdsDir = '' then
    BdsDir := GetEnvironmentVariable('BDS');
  if (BdsDir = '') or not TDirectory.Exists(BdsDir) then
    BdsDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

  if OutFile = '' then
    OutFile := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\src\design\style-map.json'));

  Writeln('StyleCatalog: BDS 37.0 style catalog scanner');
  Writeln('  Common Styles Dir: ', CommonDir);
  Writeln('  BDS Redist Dir:    ', BdsDir);
  Writeln('  Output file:       ', OutFile);

  ScanMap := TDictionary<string, TFileScanInfo>.Create;
  Entries := TList<TStyleEntry>.Create;
  PresetCounts := TDictionary<string, Integer>.Create;
  try
    ScanDir(CommonDir, 'common', ScanMap);
    ScanDir(TPath.Combine(BdsDir, 'Redist\styles\vcl'), 'redist', ScanMap);
    ScanDir(TPath.Combine(BdsDir, 'Redist\styles\Fmx'), 'redist', ScanMap);

    Writeln(Format('Discovered %d unique style files.', [ScanMap.Count]));

    for ScanInfo in ScanMap.Values do
    begin
      Entry := Default(TStyleEntry);
      Entry.FileName := ScanInfo.FileName;
      Entry.Folder := ScanInfo.Folder;
      Entry.SubFolder := ScanInfo.SubFolder;
      Entry.Framework := ScanInfo.Framework;
      Entry.FormatName := ScanInfo.FormatName;
      Entry.FullPath := ScanInfo.FullPath;

      if ScanInfo.FormatName = 'vsf' then
        ReadVclStyle(ScanInfo.FullPath, Entry)
      else if ScanInfo.FormatName = 'fsf' then
        ReadFmxFsfStyle(ScanInfo.FullPath, Entry)
      else if ScanInfo.FormatName = 'fmxstyle' then
        ReadMaterial3FmxStyle(ScanInfo.FullPath, Entry)
      else
        ReadFmxTextStyle(ScanInfo.FullPath, Entry);

      AssignProvenanceAndPreset(Entry);
      Entries.Add(Entry);
    end;

    EntriesArr := Entries.ToArray;
    AssignPairs(EntriesArr);

    TArray.Sort<TStyleEntry>(EntriesArr, TComparer<TStyleEntry>.Construct(
      function(const Left, Right: TStyleEntry): Integer
      begin
        if Left.Framework <> Right.Framework then
        begin
          if Left.Framework = 'VCL' then
            Exit(-1)
          else
            Exit(1);
        end;
        Result := CompareText(Left.FileName, Right.FileName);
      end
    ));

    JSONStr := '{'#10 +
      '  "generator": "scripts/StyleCatalog",'#10 +
      '  "bds": "37.0",'#10 +
      '  "styles": ['#10;

    for I := 0 to High(EntriesArr) do
    begin
      JSONStr := JSONStr + StyleEntryToJSON(EntriesArr[I]);
      if I < High(EntriesArr) then
        JSONStr := JSONStr + ',';
      JSONStr := JSONStr + #10;
    end;
    JSONStr := JSONStr + '  ]'#10 + '}'#10;

    var OutDir := ExtractFilePath(OutFile);
    if (OutDir <> '') and not TDirectory.Exists(OutDir) then
      TDirectory.CreateDirectory(OutDir);

    Lines := TStringList.Create;
    try
      Lines.Text := JSONStr;
      Lines.WriteBOM := False;
      Lines.SaveToFile(OutFile, TEncoding.UTF8);
    finally
      Lines.Free;
    end;
    Writeln('Saved style-map.json to: ', OutFile);

    VclCount := 0;
    FmxCount := 0;
    DarkCount := 0;
    LightCount := 0;
    UnknownCount := 0;

    for Entry in EntriesArr do
    begin
      if Entry.Framework = 'VCL' then Inc(VclCount) else Inc(FmxCount);
      if Entry.Theme = 'dark' then Inc(DarkCount)
      else if Entry.Theme = 'light' then Inc(LightCount)
      else Inc(UnknownCount);

      if PresetCounts.ContainsKey(Entry.Preset) then
        PresetCounts[Entry.Preset] := PresetCounts[Entry.Preset] + 1
      else
        PresetCounts.Add(Entry.Preset, 1);
    end;

    Writeln(#10'=== Summary ===');
    Writeln(Format('Total styles: %d', [Length(EntriesArr)]));
    Writeln(Format('Framework: VCL=%d, FMX=%d', [VclCount, FmxCount]));
    Writeln(Format('Theme:     Light=%d, Dark=%d, Unknown=%d', [LightCount, DarkCount, UnknownCount]));
    Writeln('Preset counts:');
    for Pair in PresetCounts do
      Writeln(Format('  %-20s: %d', [Pair.Key, Pair.Value]));

    Writeln(#10'=== Sample Entries ===');
    if Length(EntriesArr) > 0 then
      Writeln('Sample 1 (VCL):'#10, StyleEntryToJSON(EntriesArr[0]));
    for Entry in EntriesArr do
    begin
      if Entry.Framework = 'FMX' then
      begin
        Writeln(#10'Sample 2 (FMX):'#10, StyleEntryToJSON(Entry));
        Break;
      end;
    end;
    for Entry in EntriesArr do
    begin
      if Entry.FileName = 'Material_3.0.fmxstyle' then
      begin
        Writeln(#10'Sample 3 (Material 3):'#10, StyleEntryToJSON(Entry));
        Break;
      end;
    end;

  finally
    PresetCounts.Free;
    Entries.Free;
    ScanMap.Free;
  end;
end;

begin
  try
    Main;
  except
    on E: Exception do
      Writeln(ErrOutput, 'StyleCatalog error: ', E.Message);
  end;
end.
