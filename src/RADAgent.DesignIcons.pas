unit RADAgent.DesignIcons;

{ rad.design_icons: Segoe Fluent Icons glyphs by name, from the code point list Microsoft Learn
  publishes (src\design\icons, RCDATA DESIGN_ICONS_FLUENT). The model gets the exact code point and
  the literal for Delphi and C++ instead of guessing private-use characters. No ToolsAPI. }

interface

{ Query: words matched case-insensitively against icon names (any word matches; an exact name
  ranks first). Empty query: the catalog's notes and a sample. }
function DesignIconsJson(const Query: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, Winapi.Windows;

const
  MaxResults = 40;

function CatalogText: string;
var
  Stream: TResourceStream;
  Bytes: TBytes;
begin
  Result := '';
  if FindResource(HInstance, 'DESIGN_ICONS_FLUENT', RT_RCDATA) = 0 then
    Exit;
  Stream := TResourceStream.Create(HInstance, 'DESIGN_ICONS_FLUENT', RT_RCDATA);
  try
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then
      Stream.ReadBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function IconJson(const Code, Name: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('codePoint', 'U+' + Code);
  Result.AddPair('delphi', '#$' + Code);
  Result.AddPair('cpp', 'L"\u' + Code + '"');
end;

{ 0 = the name is the query or one of its words, 1 = starts with a word, 2 = contains a word,
  -1 = no match. }
function Score(const Name: string; const Words: TArray<string>; const Whole: string): Integer;
var
  Word: string;
begin
  if SameText(Name, Whole) then
    Exit(0);
  Result := -1;
  for Word in Words do
    if SameText(Name, Word) then
      Exit(0)
    else if Name.StartsWith(Word, True) then
      Result := 1
    else if (Result < 0) and Name.ToLower.Contains(Word.ToLower) then
      Result := 2;
end;

function DesignIconsJson(const Query: string): string;
var
  Root, Reply: TJSONObject;
  Icons, Found: TJSONArray;
  Item: TJSONValue;
  Words: TArray<string>;
  Ranked: array[0..2] of TList<TJSONArray>;
  Rank, Index, Total: Integer;
  Pair: TJSONArray;
begin
  Root := TJSONObject.ParseJSONValue(CatalogText) as TJSONObject;
  if Root = nil then
    Exit('{"ok":false,"error":"The icon catalog is missing from RAD Agent."}');
  Reply := TJSONObject.Create;
  for Rank := 0 to 2 do
    Ranked[Rank] := TList<TJSONArray>.Create;
  try
    Reply.AddPair('font', Root.GetValue<string>('font'));
    Reply.AddPair('fallbackFont', Root.GetValue<string>('fallbackFont'));
    Reply.AddPair('notes', Root.GetValue<string>('notes'));
    Reply.AddPair('source', Root.GetValue<string>('source'));
    Icons := Root.GetValue('icons') as TJSONArray;
    Words := Trim(Query).Split([' ', ',', ';'], TStringSplitOptions.ExcludeEmpty);
    Total := 0;
    for Item in Icons do
    begin
      Pair := Item as TJSONArray;
      if Length(Words) = 0 then
        Rank := 2
      else
        Rank := Score(Pair.Items[1].Value, Words, Trim(Query));
      if Rank < 0 then
        Continue;
      Inc(Total);
      Ranked[Rank].Add(Pair);
    end;
    Found := TJSONArray.Create;
    Reply.AddPair('icons', Found);
    for Rank := 0 to 2 do
      for Index := 0 to Ranked[Rank].Count - 1 do
        if Found.Count < MaxResults then
          Found.AddElement(IconJson(Ranked[Rank][Index].Items[0].Value, Ranked[Rank][Index].Items[1].Value));
    Reply.AddPair('matches', TJSONNumber.Create(Total));
    if Total > Found.Count then
      Reply.AddPair('more', TJSONNumber.Create(Total - Found.Count));
    Result := Reply.ToJSON;
  finally
    for Rank := 0 to 2 do
      Ranked[Rank].Free;
    Reply.Free;
    Root.Free;
  end;
end;

end.
