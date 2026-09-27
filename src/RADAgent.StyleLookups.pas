unit RADAgent.StyleLookups;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.JSON;

{ Reads an FMX style file (.style, .fsf) and returns JSON listing every top-level
  style object (direct children of the TStyleContainer root) that has a StyleName,
  with its class and, when set, Height/Width/FixedHeight/FixedWidth. }
function StyleLookupsJson(const StylePath, Filter: string): string;
implementation

const
  MaxLookups = 300;
type
  TLookupItem = record
    Name, ClassName: string;
    Height, Width, FixedHeight, FixedWidth: Double;
    HasHeight, HasWidth, HasFixedHeight, HasFixedWidth: Boolean;
  end;

function NumberJson(Value: Double): TJSONNumber;
begin
  if Frac(Value) = 0 then Result := TJSONNumber.Create(Trunc(Value))
  else Result := TJSONNumber.Create(Value);
end;

function ErrorJson(const Msg: string): string;
var Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONBool.Create(False));
    Obj.AddPair('error', Msg);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function ExtractClassName(const Line: string): string;
var P: Integer;
begin
  P := Pos(' ', Line);
  if P > 0 then Result := Trim(Copy(Line, P + 1, MaxInt)) else Result := Line;
  P := Pos(':', Result);
  if P > 0 then Result := Trim(Copy(Result, P + 1, MaxInt));
  P := Pos('[', Result);
  if P > 0 then Result := Trim(Copy(Result, 1, P - 1));
end;

function ExtractPropValue(const Line: string): string;
var P: Integer;
begin
  P := Pos('=', Line);
  if P > 0 then Result := Trim(Copy(Line, P + 1, MaxInt)) else Result := '';
end;

function ExtractQuotedString(const S: string): string;
var Len: Integer;
begin
  Result := Trim(S);
  Len := Length(Result);
  if (Len >= 2) and (Result[1] = '''') and (Result[Len] = '''') then
    Result := Copy(Result, 2, Len - 2);
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

procedure TryReadNum(const Trimmed, Prefix: string; var HasVal: Boolean;
  var Num: Double; const Fmt: TFormatSettings);
var Val: Double;
begin
  if (not HasVal) and (StartsText(Prefix + ' =', Trimmed) or StartsText(Prefix + '=', Trimmed)) then
    if TryStrToFloat(ExtractPropValue(Trimmed), Val, Fmt) then
    begin
      Num := Val;
      HasVal := True;
    end;
end;

procedure ReadFixedProperty(const Trimmed: string; var Item: TLookupItem; const Fmt: TFormatSettings);
begin
  TryReadNum(Trimmed, 'FixedHeight', Item.HasFixedHeight, Item.FixedHeight, Fmt);
  TryReadNum(Trimmed, 'FixedWidth', Item.HasFixedWidth, Item.FixedWidth, Fmt);
end;

procedure ReadProperty(const Trimmed: string; var Item: TLookupItem; const Fmt: TFormatSettings);
begin
  if StartsText('StyleName =', Trimmed) or StartsText('StyleName=', Trimmed) then
    Item.Name := ExtractQuotedString(ExtractPropValue(Trimmed))
  else
  begin
    TryReadNum(Trimmed, 'Height', Item.HasHeight, Item.Height, Fmt);
    TryReadNum(Trimmed, 'Size.Height', Item.HasHeight, Item.Height, Fmt);
    TryReadNum(Trimmed, 'Width', Item.HasWidth, Item.Width, Fmt);
    TryReadNum(Trimmed, 'Size.Width', Item.HasWidth, Item.Width, Fmt);
    ReadFixedProperty(Trimmed, Item, Fmt);
  end;
end;

function ParseTextStream(Stream: TStream; const Filter: string;
  var Lookups: TArray<TLookupItem>; var Total: Integer): Boolean;
var
  Reader: TStreamReader;
  Line, Trimmed, LowFilter: string;
  Indent, RootIndent, ChildIndent, PropIndent: Integer;
  Current: TLookupItem;
  HasCurrent: Boolean;
  Fmt: TFormatSettings;

  procedure SaveCurrent;
  begin
    if HasCurrent and (Current.Name <> '') and
      ((LowFilter = '') or (Pos(LowFilter, LowerCase(Current.Name)) > 0)) then
    begin
      Inc(Total);
      if Length(Lookups) < MaxLookups then
      begin
        SetLength(Lookups, Length(Lookups) + 1);
        Lookups[High(Lookups)] := Current;
      end;
    end;
    HasCurrent := False;
    Current := Default(TLookupItem);
  end;

begin
  Result := False;
  Fmt := TFormatSettings.Invariant;
  LowFilter := LowerCase(Filter);
  RootIndent := -1;
  ChildIndent := -1;
  PropIndent := -1;
  HasCurrent := False;
  Reader := TStreamReader.Create(Stream, TEncoding.UTF8, True, 65536);
  try
    while not Reader.EndOfStream do
    begin
      Line := Reader.ReadLine;
      Indent := 1;
      while (Indent <= Length(Line)) and (Line[Indent] = ' ') do Inc(Indent);
      Dec(Indent);
      if Indent >= Length(Line) then Continue;
      Trimmed := Copy(Line, Indent + 1, MaxInt);
      if (Trimmed = '') or StartsText('//', Trimmed) or StartsText('{', Trimmed) then Continue;

      if (Indent = ChildIndent) and SameText(Trimmed, 'end') then
      begin
        SaveCurrent;
        Continue;
      end;

      if StartsText('object ', Trimmed) or StartsText('inherited ', Trimmed) or StartsText('inline ', Trimmed) then
      begin
        if RootIndent = -1 then
        begin
          if Pos('TStyleContainer', Trimmed) = 0 then Exit(False);
          RootIndent := Indent;
          Result := True;
        end
        else if (ChildIndent = -1) or (Indent = ChildIndent) then
        begin
          SaveCurrent;
          ChildIndent := Indent;
          PropIndent := -1;
          Current.ClassName := ExtractClassName(Trimmed);
          HasCurrent := True;
        end;
      end
      else if HasCurrent then
      begin
        if (PropIndent = -1) and (Indent > ChildIndent) then PropIndent := Indent;
        if Indent = PropIndent then
          ReadProperty(Trimmed, Current, Fmt)
        else if Indent = PropIndent + 2 then
          ReadFixedProperty(Trimmed, Current, Fmt);
      end;
    end;
    SaveCurrent;
  finally
    Reader.Free;
  end;
end;

function ParseChunkTopLevel(Stream: TStream; const DefaultName: string;
  out Item: TLookupItem): Boolean;
var
  Reader: TStreamReader;
  Line, Trimmed: string;
  Indent, PropIndent: Integer;
  InRoot: Boolean;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Invariant;
  Item := Default(TLookupItem);
  Item.Name := DefaultName;
  InRoot := False;
  PropIndent := -1;
  Reader := TStreamReader.Create(Stream, TEncoding.UTF8, True, 4096);
  try
    while not Reader.EndOfStream do
    begin
      Line := Reader.ReadLine;
      Indent := 1;
      while (Indent <= Length(Line)) and (Line[Indent] = ' ') do Inc(Indent);
      Dec(Indent);
      if Indent >= Length(Line) then Continue;
      Trimmed := Copy(Line, Indent + 1, MaxInt);
      if (Trimmed = '') or StartsText('//', Trimmed) or StartsText('{', Trimmed) then Continue;

      if StartsText('object ', Trimmed) or StartsText('inherited ', Trimmed) or StartsText('inline ', Trimmed) then
      begin
        if not InRoot then
        begin
          InRoot := True;
          Item.ClassName := ExtractClassName(Trimmed);
        end
        else if Indent > 2 then
          Break;
      end
      else if InRoot then
      begin
        if PropIndent = -1 then PropIndent := Indent;
        if Indent = PropIndent then
          ReadProperty(Trimmed, Item, Fmt)
        else if Indent = PropIndent + 2 then
          ReadFixedProperty(Trimmed, Item, Fmt);
      end;
    end;
  finally
    Reader.Free;
  end;
  Result := InRoot and (Item.Name <> '');
end;

procedure ParseFsfStyle(Stream: TStream; const Filter: string;
  var Lookups: TArray<TLookupItem>; var Total: Integer);
var
  Sig: array[0..12] of AnsiChar;
  R: TReader;
  IndexNames: TArray<string>;
  IndexSizes: TArray<Integer>;
  I: Integer;
  BinStream, TxtStream: TMemoryStream;
  Item: TLookupItem;
  LowFilter: string;
begin
  LowFilter := LowerCase(Filter);
  Stream.ReadBuffer(Sig[0], 13);
  R := TReader.Create(Stream, 1024);
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

  for I := 0 to High(IndexNames) do
  begin
    if IndexNames[I] = '' then
    begin
      Stream.Seek(IndexSizes[I], soCurrent);
      Continue;
    end;

    if (LowFilter = '') or (Pos(LowFilter, LowerCase(IndexNames[I])) > 0) then
    begin
      Inc(Total);
      if Length(Lookups) < MaxLookups then
      begin
        BinStream := TMemoryStream.Create;
        TxtStream := TMemoryStream.Create;
        try
          BinStream.CopyFrom(Stream, IndexSizes[I]);
          BinStream.Position := 0;
          ObjectBinaryToText(BinStream, TxtStream);
          TxtStream.Position := 0;
          if ParseChunkTopLevel(TxtStream, IndexNames[I], Item) then
          begin
            SetLength(Lookups, Length(Lookups) + 1);
            Lookups[High(Lookups)] := Item;
          end;
        finally
          BinStream.Free;
          TxtStream.Free;
        end;
        Continue;
      end;
    end;
    Stream.Seek(IndexSizes[I], soCurrent);
  end;
end;

function StyleLookupsJson(const StylePath, Filter: string): string;
var
  FS: TFileStream;
  TxtStream: TMemoryStream;
  Header: array[0..15] of AnsiChar;
  HeaderRead, Total, I: Integer;
  Lookups: TArray<TLookupItem>;
  Obj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  FileName, SigStr: string;
  IsText, IsFsf, IsBinaryStyle, IsZip: Boolean;
begin
  FileName := ExtractFileName(StylePath);
  if not FileExists(StylePath) then
    Exit(ErrorJson('Style file not found: ' + StylePath));

  if SameText(ExtractFileExt(StylePath), '.fmxstyle') then
    Exit(ErrorJson(FileName + ' is a Style Designer project (.fmxstyle) and cannot be loaded by applications.'));

  SetLength(Lookups, 0);
  Total := 0;

  try
    FS := TFileStream.Create(StylePath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size = 0 then
        Exit(ErrorJson('Style file is empty: ' + FileName));

      FillChar(Header, SizeOf(Header), 0);
      HeaderRead := FS.Read(Header[0], SizeOf(Header));
      FS.Position := 0;

      IsZip := (HeaderRead >= 4) and (Header[0] = 'P') and (Header[1] = 'K') and
        (Header[2] = #3) and (Header[3] = #4);
      if IsZip then
        Exit(ErrorJson(FileName + ' is a Style Designer project (.fmxstyle) and cannot be loaded by applications.'));
      SetString(SigStr, PAnsiChar(@Header[0]), HeaderRead);
      IsFsf := StartsText('FMX_STYLE', SigStr);
      IsBinaryStyle := (HeaderRead >= 4) and (Header[0] = 'T') and (Header[1] = 'P') and
        (Header[2] = 'F') and (Header[3] = '0');
      if (HeaderRead >= 3) and (Header[0] = #$EF) and (Header[1] = #$BB) and (Header[2] = #$BF) then
        SetString(SigStr, PAnsiChar(@Header[3]), HeaderRead - 3);
      IsText := StartsText('object ', TrimLeft(SigStr));

      if IsFsf then
        ParseFsfStyle(FS, Filter, Lookups, Total)
      else if IsBinaryStyle then
      begin
        TxtStream := TMemoryStream.Create;
        try
          ObjectBinaryToText(FS, TxtStream);
          TxtStream.Position := 0;
          if not ParseTextStream(TxtStream, Filter, Lookups, Total) then Exit(ErrorJson('Not a valid FMX style file: ' + FileName));
        finally
          TxtStream.Free;
        end;
      end
      else if IsText then
      begin
        if not ParseTextStream(FS, Filter, Lookups, Total) then Exit(ErrorJson('Not a valid FMX style file: ' + FileName));
      end
      else
        Exit(ErrorJson('Not a valid FMX style file: ' + FileName));
    finally
      FS.Free;
    end;

    Obj := TJSONObject.Create;
    try
      Obj.AddPair('ok', TJSONBool.Create(True));
      Obj.AddPair('style', FileName);
      Obj.AddPair('count', TJSONNumber.Create(Length(Lookups)));
      Arr := TJSONArray.Create;
      Obj.AddPair('lookups', Arr);
      for I := 0 to High(Lookups) do
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.AddPair('name', Lookups[I].Name);
        ItemObj.AddPair('class', Lookups[I].ClassName);
        if Lookups[I].HasHeight then ItemObj.AddPair('height', NumberJson(Lookups[I].Height));
        if Lookups[I].HasWidth then ItemObj.AddPair('width', NumberJson(Lookups[I].Width));
        if Lookups[I].HasFixedHeight then ItemObj.AddPair('fixedHeight', NumberJson(Lookups[I].FixedHeight));
        if Lookups[I].HasFixedWidth then ItemObj.AddPair('fixedWidth', NumberJson(Lookups[I].FixedWidth));
        Arr.AddElement(ItemObj);
      end;
      if Total > Length(Lookups) then Obj.AddPair('more', TJSONNumber.Create(Total - Length(Lookups)));
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  except
    on E: Exception do Result := ErrorJson(E.Message);
  end;
end;

end.
