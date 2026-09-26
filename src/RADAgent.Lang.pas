unit RADAgent.Lang;

{ User-visible text in the chosen language: English, Japanese, German and French (the languages
  RAD Studio ships in) and Korean. Each language is src\lang\<code>.json (flat key -> text),
  linked as RCDATA LANG_<CODE>. A key missing in a language falls back to English, then to the
  key itself. Delphi-side texts use Format placeholders (%s, %0:s); chat page texts (keys
  "page.*") use numbered placeholders in braces. No ToolsAPI, no VCL. }

interface

type
  TLanguage = (lgAuto, lgEnglish, lgJapanese, lgGerman, lgFrench, lgKorean);

const
  LanguageCodes: array[TLanguage] of string = ('', 'en', 'ja', 'de', 'fr', 'ko');
  { Each language in its own name, for the settings list. }
  LanguageNames: array[TLanguage] of string = ('', 'English', #$65E5#$672C#$8A9E, 'Deutsch',
    'Fran'#$00E7'ais', #$D55C#$AD6D#$C5B4);

var
  { Where the saved choice comes from (a language code, '' for the system language). Set by
    RADAgent.AgentSettings; read on first use. }
  LanguageSetting: function: string;

function Tr(const Key: string): string;
function TrF(const Key: string; const Args: array of const): string;
{ The language of Windows' user interface when RADAgent has it, else English. }
function SystemLanguage: TLanguage;
function LanguageFromCode(const Code: string): TLanguage;
{ Switches the tables; Code '' means the system language. }
procedure SelectLanguage(const Code: string);
{ The language in use (never lgAuto). }
function CurrentLanguage: TLanguage;
{ Changes every time SelectLanguage picks another language. }
function LanguageGeneration: Integer;
(* {"t":"strings","lang":...,"items":{...}} with every "page." key for the chat page. *)
function PageStrings: string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.SyncObjs,
  Winapi.Windows;
var
  GLoaded: Boolean;
  GCurrent: TLanguage = lgEnglish;
  GGeneration: Integer;
  GLock: TCriticalSection;
  GTable, GEnglish: TDictionary<string, string>;
procedure LoadTable(Language: TLanguage; Table: TDictionary<string, string>);
var
  Name: string;
  Stream: TResourceStream;
  Bytes: TBytes;
  Value: TJSONValue;
  Pair: TJSONPair;
begin
  Table.Clear;
  Name := 'LANG_' + UpperCase(LanguageCodes[Language]);
  if FindResource(HInstance, PChar(Name), RT_RCDATA) = 0 then
    Exit;
  Stream := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    SetLength(Bytes, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Bytes).TrimLeft([#$FEFF]));
  try
    if Value is TJSONObject then
      for Pair in TJSONObject(Value) do
        if Pair.JsonValue is TJSONString then
          Table.AddOrSetValue(Pair.JsonString.Value, TJSONString(Pair.JsonValue).Value);
  finally
    Value.Free;
  end;
end;

function SystemLanguage: TLanguage;
begin
  case GetUserDefaultUILanguage and $3FF of
    LANG_JAPANESE: Result := lgJapanese;
    LANG_GERMAN: Result := lgGerman;
    LANG_FRENCH: Result := lgFrench;
    LANG_KOREAN: Result := lgKorean;
  else
    Result := lgEnglish;
  end;
end;

function LanguageFromCode(const Code: string): TLanguage;
var
  Language: TLanguage;
begin
  for Language := lgEnglish to High(TLanguage) do
    if SameText(LanguageCodes[Language], Code) then
      Exit(Language);
  Result := lgAuto;
end;

procedure SelectLanguage(const Code: string);
var
  Language: TLanguage;
  NewTable, OldTable, NewEnglish, OldEnglish: TDictionary<string, string>;
  NeedEnglish: Boolean;
begin
  Language := LanguageFromCode(Code);
  if Language = lgAuto then
    Language := SystemLanguage;

  GLock.Acquire;
  try
    if GLoaded and (Language = GCurrent) then
      Exit;
    NeedEnglish := GEnglish.Count = 0;
  finally
    GLock.Release;
  end;

  NewTable := TDictionary<string, string>.Create;
  NewEnglish := nil;
  OldTable := nil;
  OldEnglish := nil;
  try
    LoadTable(Language, NewTable);
    if NeedEnglish then
    begin
      NewEnglish := TDictionary<string, string>.Create;
      LoadTable(lgEnglish, NewEnglish);
    end;

    GLock.Acquire;
    try
      OldTable := GTable;
      GTable := NewTable;
      NewTable := nil;

      if (NewEnglish <> nil) and (GEnglish.Count = 0) then
      begin
        OldEnglish := GEnglish;
        GEnglish := NewEnglish;
        NewEnglish := nil;
      end;

      GCurrent := Language;
      GLoaded := True;
      Inc(GGeneration);
    finally
      GLock.Release;
    end;
  finally
    NewTable.Free;
    NewEnglish.Free;
    OldTable.Free;
    OldEnglish.Free;
  end;
end;

procedure EnsureLoaded;
begin
  if GLoaded then
    Exit;
  GLock.Acquire;
  try
    if GLoaded then
      Exit;
    if Assigned(LanguageSetting) then
      SelectLanguage(LanguageSetting())
    else
      SelectLanguage('');
  finally
    GLock.Release;
  end;
end;

function CurrentLanguage: TLanguage;
begin
  EnsureLoaded;
  GLock.Acquire;
  try
    Result := GCurrent;
  finally
    GLock.Release;
  end;
end;

function LanguageGeneration: Integer;
begin
  EnsureLoaded;
  GLock.Acquire;
  try
    Result := GGeneration;
  finally
    GLock.Release;
  end;
end;

function Tr(const Key: string): string;
begin
  EnsureLoaded;
  GLock.Acquire;
  try
    if not GTable.TryGetValue(Key, Result) and not GEnglish.TryGetValue(Key, Result) then
      Result := Key;
  finally
    GLock.Release;
  end;
end;

function HasKey(const Key: string): Boolean;
begin
  EnsureLoaded;
  GLock.Acquire;
  try
    Result := GTable.ContainsKey(Key) or GEnglish.ContainsKey(Key);
  finally
    GLock.Release;
  end;
end;
function TrF(const Key: string; const Args: array of const): string;
var
  Name: string;
begin
  { "<key>.one" is the wording for a first value of 1 ("1 item" against "%d items"). }
  Name := Key;
  if (Length(Args) > 0) and (Args[0].VType = vtInteger) and (Args[0].VInteger = 1) and
    HasKey(Key + '.one') then
    Name := Key + '.one';
  try
    Result := Format(Tr(Name), Args);
  except
    { A translation with broken placeholders must not break the caller. }
    Result := Tr(Name);
  end;
end;

function PageStrings: string;
var
  Obj, Items: TJSONObject;
  Key, Val: string;
begin
  EnsureLoaded;
  Obj := TJSONObject.Create;
  try
    GLock.Acquire;
    try
      Obj.AddPair('t', 'strings');
      Obj.AddPair('lang', LanguageCodes[GCurrent]);
      Items := TJSONObject.Create;
      for Key in GEnglish.Keys do
        if Key.StartsWith('page.') then
        begin
          if not GTable.TryGetValue(Key, Val) and not GEnglish.TryGetValue(Key, Val) then
            Val := Key;
          Items.AddPair(Key, Val);
        end;
      Obj.AddPair('items', Items);
    finally
      GLock.Release;
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GTable := TDictionary<string, string>.Create;
  GEnglish := TDictionary<string, string>.Create;

finalization
  FreeAndNil(GEnglish);
  FreeAndNil(GTable);
  FreeAndNil(GLock);
end.
