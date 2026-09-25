unit RADAgent.BrandTable;

{ Which logo a provider or a model gets. The rules are src\chat\brands\brands.json (RCDATA
  BRANDS_JSON), the same file the chat page reads (brands.js), so both sides agree:
  - a provider id maps to its service's logo ("openai-codex" -> openai); plan variants share it
    ("gitlab-duo-agent" -> the "gitlab-duo" entry);
  - a model maps to its maker by name ("nemotron-3-super:cloud" -> nvidia), else to the maker
    prefix of router ids ("meta-llama/..."), else to its provider.
  A brand is an index into "order", which is also the column in the logo sprites. No VCL. }

interface

{ -1 when the provider has no logo. }
function ProviderBrand(const Provider: string): Integer;
{ Selector is "provider/model"; -1 when neither the model nor the provider has a logo. }
function SelectorBrand(const Selector: string): Integer;
{ Name of a brand ("claude"), '' for -1. }
function BrandName(Brand: Integer): string;
function BrandCount: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.RegularExpressions,
  System.Generics.Collections, Winapi.Windows;

type
  TModelRule = record
    Pattern: TRegEx;
    Brand: string;
  end;

var
  GLoaded: Boolean;
  GOrder: TArray<string>;
  GProviders: TDictionary<string, string>;
  GPositions: TDictionary<string, Integer>;
  GRules: TArray<TModelRule>;

procedure Load;
var
  Stream: TResourceStream;
  Bytes: TBytes;
  Root: TJSONValue;
  Obj: TJSONObject;
  Pair: TJSONPair;
  Item: TJSONValue;
  Rule: TModelRule;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if FindResource(HInstance, 'BRANDS_JSON', RT_RCDATA) = 0 then
    Exit;
  Stream := TResourceStream.Create(HInstance, 'BRANDS_JSON', RT_RCDATA);
  try
    SetLength(Bytes, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Bytes));
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    if Obj.GetValue('order') is TJSONArray then
      for Item in TJSONArray(Obj.GetValue('order')) do
      begin
        GPositions.AddOrSetValue(Item.Value, Length(GOrder));
        GOrder := GOrder + [Item.Value];
      end;
    if Obj.GetValue('providers') is TJSONObject then
      for Pair in TJSONObject(Obj.GetValue('providers')) do
        GProviders.AddOrSetValue(Pair.JsonString.Value, Pair.JsonValue.Value);
    if Obj.GetValue('models') is TJSONArray then
      for Item in TJSONArray(Obj.GetValue('models')) do
        if (Item is TJSONArray) and (TJSONArray(Item).Count = 2) then
        begin
          Rule.Pattern := TRegEx.Create(TJSONArray(Item).Items[0].Value);
          Rule.Brand := TJSONArray(Item).Items[1].Value;
          GRules := GRules + [Rule];
        end;
  finally
    Root.Free;
  end;
end;

function Position(const Brand: string): Integer;
begin
  if not GPositions.TryGetValue(Brand, Result) then
    Result := -1;
end;

function ProviderKey(const Provider: string): string;
var
  Id, Key, Best: string;
begin
  Load;
  Id := LowerCase(Provider);
  if (Id = '') or GProviders.TryGetValue(Id, Result) then
    Exit;
  Best := '';
  for Key in GProviders.Keys do
    if Id.StartsWith(Key + '-') and (Length(Key) > Length(Best)) then
      Best := Key;
  if Best <> '' then
    Exit(GProviders[Best]);
  if GPositions.ContainsKey(Id) then
    Result := Id
  else
    Result := '';
end;

function ProviderBrand(const Provider: string): Integer;
begin
  Result := Position(ProviderKey(Provider));
end;

function SelectorBrand(const Selector: string): Integer;
var
  Slash: Integer;
  Provider, Model, Name: string;
  Rule: TModelRule;
begin
  Load;
  Slash := Pos('/', Selector);
  if Slash > 0 then
  begin
    Provider := Copy(Selector, 1, Slash - 1);
    Model := LowerCase(Copy(Selector, Slash + 1, MaxInt));
  end
  else
  begin
    Provider := '';
    Model := LowerCase(Selector);
  end;
  Name := Model;
  if Name.Contains('/') then
    Name := Copy(Name, Name.LastIndexOf('/') + 2, MaxInt);
  for Rule in GRules do
    if Rule.Pattern.IsMatch(Name) then
      Exit(Position(Rule.Brand));
  { Router ids carry the maker first: "meta-llama/llama-4". }
  if Model.Contains('/') then
  begin
    Result := ProviderBrand(Copy(Model, 1, Model.IndexOf('/')));
    if Result >= 0 then
      Exit;
  end;
  Result := ProviderBrand(Provider);
end;

function BrandName(Brand: Integer): string;
begin
  Load;
  if (Brand >= 0) and (Brand < Length(GOrder)) then
    Result := GOrder[Brand]
  else
    Result := '';
end;

function BrandCount: Integer;
begin
  Load;
  Result := Length(GOrder);
end;

initialization
  GProviders := TDictionary<string, string>.Create;
  GPositions := TDictionary<string, Integer>.Create;

finalization
  GPositions.Free;
  GProviders.Free;

end.
