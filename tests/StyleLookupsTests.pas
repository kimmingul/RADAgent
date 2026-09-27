unit StyleLookupsTests;

{ Tests for RADAgent.StyleLookups: FMX style lookups extraction and format handling. }

interface

uses
  TestCheck;

procedure RunStyleLookupsTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  RADAgent.StyleLookups;
const
  Win10Path = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Styles\Win10Modern.Style';
  MacFsfPath = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Styles\MacOS\macOSGraphite.fsf';
  MaterialPath = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Styles\Material_3.0.fmxstyle';

procedure TestInstalledWin10(const Check: TCheckProc);
var
  Json: string;
  Val, LookupsVal, ItemVal: TJSONValue;
  Obj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  FoundButton, FoundSpeed, FoundBg, FoundNestedText: Boolean;
  NameStr: string;
begin
  if not FileExists(Win10Path) then
  begin
    Check(True, 'Win10Modern.Style missing - skipped installed file checks');
    Exit;
  end;

  Json := StyleLookupsJson(Win10Path, '');
  Val := TJSONObject.ParseJSONValue(Json);
  Check(Val is TJSONObject, 'Win10Modern returns valid JSON');
  if not (Val is TJSONObject) then
  begin
    Val.Free;
    Exit;
  end;

  Obj := TJSONObject(Val);
  try
    Check(Obj.GetValue<Boolean>('ok', False), 'Win10Modern parses with ok:true');
    Check(Obj.GetValue<string>('style', '') = 'Win10Modern.Style', 'Win10Modern style file name matches');
    Check(Obj.GetValue<Integer>('count', 0) > 100, 'Win10Modern has > 100 lookups');

    LookupsVal := Obj.GetValue('lookups');
    Check(LookupsVal is TJSONArray, 'lookups is a JSON array');
    if LookupsVal is TJSONArray then
    begin
      Arr := TJSONArray(LookupsVal);
      FoundButton := False;
      FoundSpeed := False;
      FoundBg := False;
      FoundNestedText := False;

      for I := 0 to Arr.Count - 1 do
      begin
        ItemVal := Arr.Items[I];
        if ItemVal is TJSONObject then
        begin
          ItemObj := TJSONObject(ItemVal);
          NameStr := ItemObj.GetValue<string>('name', '');
          if SameText(NameStr, 'buttonstyle') then
          begin
            FoundButton := True;
            Check(ItemObj.GetValue<string>('class', '') = 'TLayout', 'buttonstyle class is TLayout');
          end
          else if SameText(NameStr, 'speedbuttonstyle') then
          begin
            FoundSpeed := True;
            Check(ItemObj.GetValue<string>('class', '') = 'TLayout', 'speedbuttonstyle class is TLayout');
            Check(ItemObj.GetValue<Double>('fixedHeight', 0) = 46, 'speedbuttonstyle has fixedHeight 46');
          end
          else if SameText(NameStr, 'backgroundstyle') then
          begin
            FoundBg := True;
            Check(ItemObj.GetValue<string>('class', '') = 'TRectangle', 'backgroundstyle class is TRectangle');
            Check(ItemObj.GetValue<Double>('height', 0) = 50, 'backgroundstyle height is 50');
            Check(ItemObj.GetValue<Double>('width', 0) = 50, 'backgroundstyle width is 50');
          end
          else if SameText(NameStr, 'text') then
            FoundNestedText := True;
        end;
      end;

      Check(FoundButton, 'buttonstyle is listed');
      Check(FoundSpeed, 'speedbuttonstyle is listed');
      Check(FoundBg, 'backgroundstyle is listed');
      Check(not FoundNestedText, 'nested StyleName text inside labelstyle is NOT listed');
    end;
  finally
    Obj.Free;
  end;

  { Filter test }
  Json := StyleLookupsJson(Win10Path, 'buttonstyle');
  Val := TJSONObject.ParseJSONValue(Json);
  try
    if Val is TJSONObject then
    begin
      LookupsVal := TJSONObject(Val).GetValue('lookups');
      if LookupsVal is TJSONArray then
      begin
        Arr := TJSONArray(LookupsVal);
        Check(Arr.Count > 0, 'buttonstyle filter returns results');
        FoundBg := False;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
            if SameText(TJSONObject(Arr.Items[I]).GetValue<string>('name', ''), 'backgroundstyle') then
              FoundBg := True;
        Check(not FoundBg, 'backgroundstyle excluded when filtering for buttonstyle');
      end;
    end;
  finally
    Val.Free;
  end;
end;

procedure TestInstalledMacFsf(const Check: TCheckProc);
var
  Json: string;
  Val, LookupsVal: TJSONValue;
  Obj: TJSONObject;
  Count: Integer;
begin
  if not FileExists(MacFsfPath) then
  begin
    Check(True, 'macOSGraphite.fsf missing - skipped binary fsf check');
    Exit;
  end;

  Json := StyleLookupsJson(MacFsfPath, '');
  Val := TJSONObject.ParseJSONValue(Json);
  Check(Val is TJSONObject, 'macOSGraphite.fsf returns valid JSON');
  if not (Val is TJSONObject) then
  begin
    Val.Free;
    Exit;
  end;

  Obj := TJSONObject(Val);
  try
    Check(Obj.GetValue<Boolean>('ok', False), 'macOSGraphite.fsf parses with ok:true');
    Count := Obj.GetValue<Integer>('count', 0);
    Check(Count > 0, 'macOSGraphite.fsf parses with >0 lookups (' + IntToStr(Count) + ')');
    LookupsVal := Obj.GetValue('lookups');
    Check(LookupsVal is TJSONArray, 'lookups is an array');
    Check(Json.Contains('"buttonstyle"'), 'macOSGraphite.fsf contains buttonstyle');
  finally
    Obj.Free;
  end;
end;

procedure TestFmxStyleRejection(const Check: TCheckProc);
var
  Json: string;
begin
  if FileExists(MaterialPath) then
  begin
    Json := StyleLookupsJson(MaterialPath, '');
    Check(Json.Contains('"ok":false'), 'installed Material_3.0.fmxstyle returns ok:false');
    Check(Json.Contains('Style Designer project') or Json.Contains('cannot be loaded'),
      'installed fmxstyle returns clear message that it is not loadable');
  end;
end;

procedure TestSyntheticAndErrors(const Check: TCheckProc);
var
  TempDir, TempFile, Json: string;
  Content: string;
  Val, LookupsVal, ItemVal: TJSONValue;
  Obj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  FoundButton, FoundPanel, FoundText: Boolean;
begin
  TempDir := TPath.GetTempPath;

  { 1. Missing file }
  Json := StyleLookupsJson(TPath.Combine(TempDir, 'NonExistent_Fake_Style_98765.style'), '');
  Check(Json.Contains('"ok":false'), 'missing file returns ok:false');

  { 2. Synthetic FMX text style }
  TempFile := TPath.Combine(TempDir, 'RADAgent_Test_Style.style');
  Content :=
    'object TStyleContainer'#13#10 +
    '  object TLayout'#13#10 +
    '    StyleName = ''custombutton'''#13#10 +
    '    Height = 44'#13#10 +
    '    Width = 120'#13#10 +
    '    FixedHeight = 46'#13#10 +
    '    object TText'#13#10 +
    '      StyleName = ''nestedlabel'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object TRectangle'#13#10 +
    '    StyleName = ''custompanel'''#13#10 +
    '    Size.Width = 200.000000000000000000'#13#10 +
    '    Size.Height = 150.000000000000000000'#13#10 +
    '  end'#13#10 +
    '  object TLayout'#13#10 +
    '    Align = Contents'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
  TFile.WriteAllText(TempFile, Content, TEncoding.UTF8);
  try
    Json := StyleLookupsJson(TempFile, '');
    Val := TJSONObject.ParseJSONValue(Json);
    Check(Val is TJSONObject, 'synthetic style parses valid JSON');
    if Val is TJSONObject then
    begin
      Obj := TJSONObject(Val);
      try
        Check(Obj.GetValue<Boolean>('ok', False), 'synthetic style ok is true');
        Check(Obj.GetValue<Integer>('count', 0) = 2, 'synthetic style has count 2 (skips un-styled)');
        LookupsVal := Obj.GetValue('lookups');
        if LookupsVal is TJSONArray then
        begin
          Arr := TJSONArray(LookupsVal);
          FoundButton := False;
          FoundPanel := False;
          FoundText := False;
          for I := 0 to Arr.Count - 1 do
          begin
            ItemVal := Arr.Items[I];
            if ItemVal is TJSONObject then
            begin
              ItemObj := TJSONObject(ItemVal);
              if ItemObj.GetValue<string>('name', '') = 'custombutton' then
              begin
                FoundButton := True;
                Check(ItemObj.GetValue<string>('class', '') = 'TLayout', 'custombutton class is TLayout');
                Check(ItemObj.GetValue<Double>('height', 0) = 44, 'custombutton height is 44');
                Check(ItemObj.GetValue<Double>('width', 0) = 120, 'custombutton width is 120');
                Check(ItemObj.GetValue<Double>('fixedHeight', 0) = 46, 'custombutton fixedHeight is 46');
              end
              else if ItemObj.GetValue<string>('name', '') = 'custompanel' then
              begin
                FoundPanel := True;
                Check(ItemObj.GetValue<string>('class', '') = 'TRectangle', 'custompanel class is TRectangle');
                Check(ItemObj.GetValue<Double>('height', 0) = 150, 'custompanel height is 150');
                Check(ItemObj.GetValue<Double>('width', 0) = 200, 'custompanel width is 200');
              end
              else if ItemObj.GetValue<string>('name', '') = 'nestedlabel' then
                FoundText := True;
            end;
          end;
          Check(FoundButton, 'synthetic custombutton found');
          Check(FoundPanel, 'synthetic custompanel found');
          Check(not FoundText, 'nestedlabel inside custombutton is NOT listed');
        end;
      finally
        Obj.Free;
      end;
    end;

    { Filter synthetic }
    Json := StyleLookupsJson(TempFile, 'panel');
    Check(Json.Contains('"count":1'), 'synthetic filter count is 1');
    Check(Json.Contains('custompanel'), 'synthetic filter includes custompanel');
    Check(not Json.Contains('custombutton'), 'synthetic filter excludes custombutton');
  finally
    if FileExists(TempFile) then
      TFile.Delete(TempFile);
  end;

  { 3. Non-style DFM file (root not TStyleContainer) }
  TempFile := TPath.Combine(TempDir, 'RADAgent_Test_Form.style');
  TFile.WriteAllText(TempFile, 'object TForm1'#13#10'  Caption = ''Form'''#13#10'end'#13#10, TEncoding.UTF8);
  try
    Json := StyleLookupsJson(TempFile, '');
    Check(Json.Contains('"ok":false'), 'non-TStyleContainer file returns ok:false');
  finally
    if FileExists(TempFile) then
      TFile.Delete(TempFile);
  end;

  { 4. Synthetic .fmxstyle file }
  TempFile := TPath.Combine(TempDir, 'RADAgent_Test_Zip.fmxstyle');
  TFile.WriteAllText(TempFile, 'dummy zip content', TEncoding.UTF8);
  try
    Json := StyleLookupsJson(TempFile, '');
    Check(Json.Contains('"ok":false'), 'synthetic .fmxstyle returns ok:false');
    Check(Json.Contains('cannot be loaded by applications'), 'synthetic .fmxstyle error message');
  finally
    if FileExists(TempFile) then
      TFile.Delete(TempFile);
  end;
end;

procedure RunStyleLookupsTests(const Check: TCheckProc);
begin
  TestInstalledWin10(Check);
  TestInstalledMacFsf(Check);
  TestFmxStyleRejection(Check);
  TestSyntheticAndErrors(Check);
end;

end.
