unit StyleCatalog.Rules;

interface

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  StyleCatalog.Types;

procedure AssignProvenanceAndPreset(var Entry: TStyleEntry);
procedure AssignPairs(var Entries: TArray<TStyleEntry>);
function StyleEntryToJSON(const Entry: TStyleEntry): string;

implementation

procedure AssignProvenanceAndPreset(var Entry: TStyleEntry);
var
  LowFile, LowTitle, P: string;
  OnlyApple, OnlyAndroid: Boolean;
begin
  LowFile := LowerCase(Entry.FileName);
  LowTitle := LowerCase(Entry.StyleName);

  if Entry.Theme <> 'dark' then
  begin
    if (Pos('dark', LowFile) > 0) or (Pos('black', LowFile) > 0) or
       (Pos('dark', LowTitle) > 0) or (Pos('black', LowTitle) > 0) then
      Entry.Theme := 'dark';
  end;

  if StartsText('windowsmodern', LowFile) and (Entry.Framework = 'VCL') then
  begin
    Entry.Provenance.System := 'windows-11';
    Entry.Provenance.Basis := 'vendor-statement';
    Entry.Provenance.Evidence := 'RAD Studio 13.1: six new Windows 11-specific VCL styles https://blogs.embarcadero.com/announcing-the-availability-of-rad-studio-13-florence-update-1/';
    Entry.Preset := 'fluent-windows11';
    Entry.PresetBasis := 'match';
  end
  else if StartsText('windows10', LowFile) or StartsText('win10modern', LowFile) then
  begin
    Entry.Provenance.System := 'windows-10';
    if (Entry.Framework = 'FMX') and (Pos('windows 10', LowTitle) > 0) then
    begin
      Entry.Provenance.Basis := 'file-content';
      Entry.Provenance.Evidence := 'FMX style title declares Windows 10';
    end
    else
    begin
      Entry.Provenance.Basis := 'name';
      Entry.Provenance.Evidence := 'Windows 10 style name';
    end;
    Entry.Preset := 'fluent-windows11';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('metropolisui', LowFile) then
  begin
    Entry.Provenance.System := 'windows-8-metro';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'Metropolis UI style name';
    Entry.Preset := 'fluent-windows11';
    Entry.PresetBasis := 'policy';
  end
  else if LowFile = 'material_3.0.fmxstyle' then
  begin
    Entry.Provenance.System := 'material-3';
    Entry.Provenance.Basis := 'file-content';
    Entry.Provenance.Evidence := 'Material 3 tokens and typography in style archive';
    Entry.Preset := 'material3';
    Entry.PresetBasis := 'match';
  end
  else if (LowFile = 'androidlight.fsf') or (LowFile = 'androiddark.fsf') then
  begin
    Entry.Provenance.System := 'android-holo';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'Android Holo style name';
    Entry.Preset := 'material3';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('androidl', LowFile) then
  begin
    Entry.Provenance.System := 'android-5-material';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'Android L style name';
    Entry.Preset := 'material3';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('androidwear', LowFile) then
  begin
    Entry.Provenance.System := 'android-wear';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'Android Wear style name';
    Entry.Preset := 'material3';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('googleglass', LowFile) then
  begin
    Entry.Provenance.System := 'google-glass';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'Google Glass style name';
    Entry.Preset := 'material3';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('macos', LowFile) or StartsText('yosemite', LowFile) or (Entry.SubFolder = 'MacOS') then
  begin
    Entry.Provenance.System := 'macos';
    if (Pos('macos', LowTitle) > 0) or (Pos('osx', LowTitle) > 0) or (IndexStr('macOS', Entry.Platforms) >= 0) then
    begin
      Entry.Provenance.Basis := 'file-content';
      Entry.Provenance.Evidence := 'macOS style title/target';
    end
    else
    begin
      Entry.Provenance.Basis := 'name';
      Entry.Provenance.Evidence := 'macOS style name';
    end;
    Entry.Preset := 'apple-macos';
    Entry.PresetBasis := 'policy';
  end
  else if StartsText('ios', LowFile) or (Entry.SubFolder = 'iOS') then
  begin
    Entry.Provenance.System := 'ios';
    Entry.Provenance.Basis := 'name';
    Entry.Provenance.Evidence := 'iOS style; no iOS preset yet';
    Entry.Preset := 'apple-macos';
    Entry.PresetBasis := 'policy';
  end
  else
  begin
    Entry.Provenance.System := 'none';
    Entry.Provenance.Basis := 'none';
    Entry.Provenance.Evidence := 'Embarcadero skin';
    if Entry.Framework = 'VCL' then
      Entry.Preset := 'fluent-windows11'
    else
    begin
      OnlyApple := (Length(Entry.Platforms) > 0);
      OnlyAndroid := (Length(Entry.Platforms) > 0);
      for P in Entry.Platforms do
      begin
        if (P <> 'macOS') and (P <> 'iOS') then OnlyApple := False;
        if P <> 'Android' then OnlyAndroid := False;
      end;
      if OnlyApple then
        Entry.Preset := 'apple-macos'
      else if OnlyAndroid then
        Entry.Preset := 'material3'
      else
        Entry.Preset := 'fluent-windows11';
    end;
    Entry.PresetBasis := 'policy';
  end;
end;

procedure AssignPairs(var Entries: TArray<TStyleEntry>);
var
  I, J: Integer;
  StemI, StemJ: string;
begin
  for I := 0 to High(Entries) do
  begin
    Entries[I].Pair := '';
    if (Entries[I].Theme = 'unknown') or (Entries[I].Theme = '') then
      Continue;

    StemI := GetStem(Entries[I].FileName);
    for J := 0 to High(Entries) do
    begin
      if I = J then
        Continue;
      if Entries[I].Framework <> Entries[J].Framework then
        Continue;
      if (Entries[J].Theme = 'unknown') or (Entries[J].Theme = '') then
        Continue;
      if Entries[I].Theme = Entries[J].Theme then
        Continue;

      StemJ := GetStem(Entries[J].FileName);
      if StemI = StemJ then
      begin
        Entries[I].Pair := Entries[J].FileName;
        Break;
      end;
    end;
  end;
end;

function StyleEntryToJSON(const Entry: TStyleEntry): string;
var
  PlatJSON: string;
  LoadableStr: string;
  I: Integer;
begin
  PlatJSON := '[';
  for I := 0 to High(Entry.Platforms) do
  begin
    PlatJSON := PlatJSON + '"' + Entry.Platforms[I] + '"';
    if I < High(Entry.Platforms) then
      PlatJSON := PlatJSON + ', ';
  end;
  PlatJSON := PlatJSON + ']';

  if Entry.Loadable then
    LoadableStr := 'true'
  else
    LoadableStr := 'false';

  Result := '    {'#10 +
    Format('      "file": "%s",'#10, [Entry.FileName]) +
    Format('      "folder": "%s",'#10, [Entry.Folder]) +
    Format('      "subfolder": "%s",'#10, [Entry.SubFolder]) +
    Format('      "framework": "%s",'#10, [Entry.Framework]) +
    Format('      "format": "%s",'#10, [Entry.FormatName]) +
    Format('      "name": "%s",'#10, [Entry.StyleName]) +
    Format('      "platforms": %s,'#10, [PlatJSON]) +
    Format('      "theme": "%s",'#10, [Entry.Theme]) +
    Format('      "loadable": %s,'#10, [LoadableStr]) +
    Format('      "colors": %s,'#10, [Entry.Colors.ToJSON('      ')]) +
    Format('      "pair": "%s",'#10, [Entry.Pair]) +
    '      "provenance": {'#10 +
    Format('        "system": "%s",'#10, [Entry.Provenance.System]) +
    Format('        "basis": "%s",'#10, [Entry.Provenance.Basis]) +
    Format('        "evidence": "%s"'#10, [Entry.Provenance.Evidence]) +
    '      },'#10 +
    Format('      "preset": "%s",'#10, [Entry.Preset]) +
    Format('      "presetBasis": "%s"'#10, [Entry.PresetBasis]) +
    '    }';
end;

end.
