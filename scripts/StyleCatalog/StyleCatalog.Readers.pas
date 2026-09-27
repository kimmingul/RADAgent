unit StyleCatalog.Readers;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.Zip,
  System.JSON,
  Vcl.Graphics,
  Vcl.Themes,
  Vcl.Styles,
  StyleCatalog.Types;

function ReadVclStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
function ReadFmxTextStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
function ReadFmxFsfStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
function ReadMaterial3FmxStyle(const FileName: string; var Entry: TStyleEntry): Boolean;

implementation

function ReadVclStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
var
  Info: TStyleInfo;
  Style: TCustomStyleServices;
begin
  Result := False;
  if not TStyleManager.IsValidStyle(FileName, Info) then
    Exit;

  Entry.StyleName := Info.Name;
  Entry.Platforms := ['Windows'];
  Entry.Loadable := True;

  try
    TStyleManager.LoadFromFile(FileName);
    Style := TStyleManager.Style[Info.Name];
    if Style <> nil then
    begin
      Entry.Colors.Background := ColorToHex(ColorToRGB(Style.GetSystemColor(clBtnFace)));
      Entry.Colors.Surface := ColorToHex(ColorToRGB(Style.GetSystemColor(clWindow)));
      Entry.Colors.Text := ColorToHex(ColorToRGB(Style.GetSystemColor(clWindowText)));
      Entry.Colors.TextDisabled := ColorToHex(ColorToRGB(Style.GetSystemColor(clGrayText)));
      Entry.Colors.Accent := ColorToHex(ColorToRGB(Style.GetSystemColor(clHighlight)));
      Entry.Colors.AccentText := ColorToHex(ColorToRGB(Style.GetSystemColor(clHighlightText)));
      Entry.Colors.Border := ColorToHex(ColorToRGB(Style.GetStyleColor(scBorder)));
      Entry.Theme := ThemeFromBackground(Entry.Colors.Background);
      Result := True;
    end;
  except
    Result := False;
  end;
end;

function ExtractPropValue(const Line, PropPrefix: string): string;
var
  P: Integer;
begin
  Result := '';
  P := Pos(PropPrefix, Line);
  if P > 0 then
    Result := Trim(Copy(Line, P + Length(PropPrefix), MaxInt));
  Result := Result.Trim([' ', '''', '"']);
end;

procedure ParseFmxTextProperties(const Text: string; var Title, Target, BgColor, TextColor, AccentColor: string);
var
  Lines: TArray<string>;
  I, J: Integer;
  Line, LowLine, LJ, C: string;
begin
  Lines := Text.Split([#13#10, #10]);

  for I := 0 to High(Lines) do
  begin
    Line := Trim(Lines[I]);
    LowLine := LowerCase(Line);

    if (Title = '') and StartsText('title =', LowLine) then
      Title := ExtractPropValue(Line, '=');

    if (Target = '') and StartsText('platformtarget =', LowLine) then
      Target := ExtractPropValue(Line, '=');

    if (BgColor = '') and (Pos('''backgroundstyle''', LowLine) > 0) then
    begin
      for J := Max(0, I - 5) to Min(High(Lines), I + 15) do
      begin
        LJ := LowerCase(Trim(Lines[J]));
        if Pos('fill.color =', LJ) > 0 then
        begin
          C := FmxColorToHex(ExtractPropValue(Lines[J], '='));
          if C <> '' then
          begin
            BgColor := C;
            Break;
          end;
        end;
      end;
    end;

    if (TextColor = '') and (Pos('tbuttonstyletextobject', LowLine) > 0) then
    begin
      for J := I to Min(High(Lines), I + 10) do
      begin
        LJ := LowerCase(Trim(Lines[J]));
        if Pos('normalcolor =', LJ) > 0 then
        begin
          C := FmxColorToHex(ExtractPropValue(Lines[J], '='));
          if C <> '' then
          begin
            TextColor := C;
            Break;
          end;
        end;
      end;
    end;

    if (TextColor = '') and (Pos('''labelstyle''', LowLine) > 0) then
    begin
      for J := I to Min(High(Lines), I + 25) do
      begin
        LJ := LowerCase(Trim(Lines[J]));
        if (Pos('textsettings.fontcolor =', LJ) > 0) or StartsText('color =', LJ) then
        begin
          C := FmxColorToHex(ExtractPropValue(Lines[J], '='));
          if C <> '' then
          begin
            TextColor := C;
            Break;
          end;
        end;
      end;
    end;

    if (AccentColor = '') and (Pos('''caretcolor''', LowLine) > 0) then
    begin
      for J := I to Min(High(Lines), I + 5) do
      begin
        LJ := LowerCase(Trim(Lines[J]));
        if StartsText('color =', LJ) then
        begin
          C := FmxColorToHex(ExtractPropValue(Lines[J], '='));
          if C <> '' then
          begin
            AccentColor := C;
            Break;
          end;
        end;
      end;
    end;

    if (AccentColor = '') and (Pos('''selection''', LowLine) > 0) then
    begin
      for J := I to Min(High(Lines), I + 8) do
      begin
        LJ := LowerCase(Trim(Lines[J]));
        if StartsText('brush.color =', LJ) or StartsText('fill.color =', LJ) or StartsText('color =', LJ) then
        begin
          C := FmxColorToHex(ExtractPropValue(Lines[J], '='));
          if C <> '' then
          begin
            AccentColor := C;
            Break;
          end;
        end;
      end;
    end;
  end;
end;

function ReadFmxTextStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
var
  Text: string;
  Title, Target, BgColor, TextColor, AccentColor: string;
begin
  Result := True;
  try
    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
  except
    Text := TFile.ReadAllText(FileName, TEncoding.ANSI);
  end;

  ParseFmxTextProperties(Text, Title, Target, BgColor, TextColor, AccentColor);

  if Title <> '' then
    Entry.StyleName := Title
  else
    Entry.StyleName := ChangeFileExt(Entry.FileName, '');

  Entry.Platforms := PlatformsFromTarget(Target);
  Entry.Colors.Background := BgColor;
  Entry.Colors.Text := TextColor;
  Entry.Colors.Accent := AccentColor;
  Entry.Theme := ThemeFromBackground(BgColor);
  Entry.Loadable := True;
end;

function ReadFmxFsfStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
var
  FS: TFileStream;
  Sig: array[0..12] of AnsiChar;
  R: TReader;
  IndexNames: TArray<string>;
  IndexSizes: TArray<Integer>;
  I: Integer;
  BinStream, TxtStream: TMemoryStream;
  TxtStr: AnsiString;
  CombinedText: string;
  Title, Target, BgColor, TextColor, AccentColor: string;
begin
  Result := False;
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size < 13 then Exit;
    FS.ReadBuffer(Sig[0], 13);
    if not (StartsText('FMX_STYLE', string(Sig))) then
      Exit;

    R := TReader.Create(FS, 1024);
    try
      R.ReadListBegin;
      while not R.EndOfList do
      begin
        SetLength(IndexNames, Length(IndexNames) + 1);
        SetLength(IndexSizes, Length(IndexSizes) + 1);
        IndexNames[High(IndexNames)] := R.ReadString;
        IndexSizes[High(IndexSizes)] := R.ReadInteger;
      end;
      R.ReadListEnd;
    finally
      R.Free;
    end;

    CombinedText := '';
    for I := 0 to High(IndexNames) do
    begin
      var LowName := LowerCase(IndexNames[I]);
      if (LowName = 'description') or
         (LowName = 'backgroundstyle') or
         (LowName = 'labelstyle') or
         (LowName = 'buttonstyle') or
         (LowName.Contains('caret')) or
         (LowName.Contains('select')) then
      begin
        BinStream := TMemoryStream.Create;
        TxtStream := TMemoryStream.Create;
        try
          BinStream.CopyFrom(FS, IndexSizes[I]);
          BinStream.Position := 0;
          try
            ObjectBinaryToText(BinStream, TxtStream);
            TxtStream.Position := 0;
            SetLength(TxtStr, TxtStream.Size);
            TxtStream.ReadBuffer(TxtStr[1], TxtStream.Size);
            CombinedText := CombinedText + #10 + string(TxtStr);
          except
          end;
        finally
          BinStream.Free;
          TxtStream.Free;
        end;
      end
      else
        FS.Seek(IndexSizes[I], soCurrent);
    end;

    ParseFmxTextProperties(CombinedText, Title, Target, BgColor, TextColor, AccentColor);

    if Title <> '' then
      Entry.StyleName := Title
    else
      Entry.StyleName := ChangeFileExt(Entry.FileName, '');

    Entry.Platforms := PlatformsFromTarget(Target);
    Entry.Colors.Background := BgColor;
    Entry.Colors.Text := TextColor;
    Entry.Colors.Accent := AccentColor;
    Entry.Theme := ThemeFromBackground(BgColor);
    Entry.Loadable := True;
    Result := True;
  finally
    FS.Free;
  end;
end;

function ReadMaterial3FmxStyle(const FileName: string; var Entry: TStyleEntry): Boolean;
var
  Zip: TZipFile;
  Stream: TStream;
  Header: TZipHeader;
  Content: string;
  JSONVal: TJSONValue;
  Arr: TJSONArray;
  Item: TJSONValue;
  Obj: TJSONObject;
  NameVal: string;
  ColorVal: Cardinal;
begin
  Result := False;
  Zip := TZipFile.Create;
  try
    Zip.Open(FileName, zmRead);
    if Zip.IndexOf('colors.json') >= 0 then
    begin
      Zip.Read('colors.json', Stream, Header);
      try
        var StringStream := TStringStream.Create('', TEncoding.UTF8);
        try
          StringStream.CopyFrom(Stream, Stream.Size);
          Content := StringStream.DataString;
        finally
          StringStream.Free;
        end;
      finally
        Stream.Free;
      end;

      JSONVal := TJSONObject.ParseJSONValue(Content);
      if JSONVal is TJSONArray then
      begin
        Arr := TJSONArray(JSONVal);
        for var I := 0 to Arr.Count - 1 do
        begin
          Item := Arr.Items[I];
          if Item is TJSONObject then
          begin
            Obj := TJSONObject(Item);
            NameVal := Obj.GetValue<string>('name', '');
            if Obj.TryGetValue<Cardinal>('color', ColorVal) then
            begin
              var HexCol := Uint32ToHex(ColorVal);
              if SameText(NameVal, 'Background') then Entry.Colors.Background := HexCol
              else if SameText(NameVal, 'Surface') then Entry.Colors.Surface := HexCol
              else if SameText(NameVal, 'Text') and (Entry.Colors.Text = '') then Entry.Colors.Text := HexCol
              else if SameText(NameVal, 'On Surface') and (Entry.Colors.Text = '') then Entry.Colors.Text := HexCol
              else if SameText(NameVal, 'Secondary Text') then Entry.Colors.TextDisabled := HexCol
              else if SameText(NameVal, 'Primary') then Entry.Colors.Accent := HexCol
              else if SameText(NameVal, 'On Primary') then Entry.Colors.AccentText := HexCol
              else if SameText(NameVal, 'Outline') then Entry.Colors.Border := HexCol;
            end;
          end;
        end;
        JSONVal.Free;
      end;
    end;

    Entry.StyleName := 'Material 3.0';
    Entry.Platforms := ['Windows', 'macOS', 'iOS', 'Android', 'Linux'];
    Entry.Theme := ThemeFromBackground(Entry.Colors.Background);
    Entry.Loadable := False;
    Result := True;
  finally
    Zip.Free;
  end;
end;

end.
